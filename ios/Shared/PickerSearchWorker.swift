import Foundation

struct PickerWorkerSnapshot: Sendable {
    let categories: [BrowseCategory]
    let preferences: BrowsePreferences
    let utilityCounts: [String: BrowseItemCount]
    let canEditVisibility: Bool
    let warning: String?
}

/// One background queue owns both SQLite connections and visibility-file access.
final class PickerSearchWorker: @unchecked Sendable {
    private struct Configuration {
        let databaseURL: URL; let directory: URL; let host: HistoryHost
        let visibility: NativeVisibilityAccess?; let legacyUsage: [UsageEntry]; let seedURL: URL?
    }
    private final class Session {
        let engine: GlyphSearch; let store: Result<NativePersonalizationStore, Error>
        let visibility: NativeVisibilityAccess; let host: HistoryHost
        var usage: [UsageEntry]; let startupWarning: String?
        init(engine: GlyphSearch, store: Result<NativePersonalizationStore, Error>, visibility: NativeVisibilityAccess, host: HistoryHost, usage: [UsageEntry], startupWarning: String?) {
            self.engine = engine; self.store = store; self.visibility = visibility; self.host = host; self.usage = usage; self.startupWarning = startupWarning
        }
    }
    private enum Phase { case pending(Configuration), ready(Session), failed(Error) }
    private let queue = DispatchQueue(label: "Unimagic.search", qos: .userInitiated)
    private var phase: Phase
    init(databaseURL: URL, directory: URL, host: HistoryHost, visibility: NativeVisibilityAccess?, legacyUsage: [UsageEntry], seedURL: URL?) {
        phase = .pending(Configuration(databaseURL: databaseURL, directory: directory, host: host, visibility: visibility, legacyUsage: legacyUsage, seedURL: seedURL))
    }

    func start(completion: @escaping @Sendable (Result<PickerWorkerSnapshot, Error>) -> Void) {
        queue.async { [self] in
            do {
                if case .pending(let config) = phase {
                    let engine = try GlyphSearch(databaseURL: config.databaseURL)
                    let location = NativePersonalizationLocation.local(NativePersonalizationPaths.localDirectory(inApplicationSupport: config.directory))
                    let store = Result { try NativePersonalizationStore(location: location, catalogueRevision: engine.catalogueRevision) }
                    var warning: String?
                    if let value = try? store.get() { do { try importInitialData(config, into: value) } catch { warning = String(describing: error) } }
                    phase = .ready(Session(engine: engine, store: store, visibility: config.visibility ?? .production(for: config.host), host: config.host, usage: config.legacyUsage, startupWarning: warning))
                }
                guard case .ready(let session) = phase else { throw failure() }
                completion(.success(snapshot(session)))
            } catch { phase = .failed(error); completion(.failure(error)) }
        }
    }
    func refresh(usage: [UsageEntry], completion: @escaping @Sendable (Result<PickerWorkerSnapshot, Error>) -> Void) {
        perform({ self.snapshot($0, usage: usage) }, completion: completion)
    }
    func search(query: String, store: LearningStore, completion: @escaping @Sendable ([Glyph]) -> Void) {
        perform({ $0.engine.search(query: query, learned: store.learned, usage: store.usage, limit: 100) }) { result in completion((try? result.get()) ?? []) }
    }
    func glyphs(_ ids: [String], completion: @escaping @Sendable ([Glyph]) -> Void) {
        perform({ session in ids.compactMap { session.engine.glyph(id: $0) } }) { result in completion((try? result.get()) ?? []) }
    }
    func contexts(glyph: Glyph, origin: BrowseOrigin?, completion: @escaping @Sendable ([BrowseContextTarget]) -> Void) {
        perform({ $0.engine.contexts(for: glyph, origin: origin) }) { result in completion((try? result.get()) ?? []) }
    }
    func samples(category: BrowseCategory, completion: @escaping @Sendable ([BrowseOccurrence]) -> Void) {
        perform({ $0.engine.browseSamples(category: category, limit: 6).items }) { result in completion((try? result.get()) ?? []) }
    }
    func page(category: BrowseCategory, cursor: BrowseCursor, usage: [UsageEntry], completion: @escaping @Sendable (Result<BrowsePage, Error>) -> Void) {
        perform({ session in
            if category.isRecent {
                let cursorValue: String?, position: Int
                switch cursor {
                case .history(let value, let offset): cursorValue = value; position = offset
                case .offset(0): cursorValue = nil; position = 0
                default: throw NativeStoreError.invalidCursor
                }
                let store = try session.store.get(), page = try store.readHistoryPage(cursor: cursorValue, limit: 100)
                let items = page.events.enumerated().map { offset, event in
                    BrowseOccurrence(id: category.id + ":event:" + event.eventID, categoryID: category.id, position: position + offset,
                                     glyph: session.engine.historyGlyph(id: event.glyphID, symbol: event.symbol), provenance: .history(event))
                }
                return BrowsePage(items: items, nextCursor: page.nextCursor.map { .history(cursor: $0, position: position + items.count) },
                                  startOffset: position, totalCount: .known(try store.historyCount()))
            }
            guard case .offset(let offset) = cursor else { throw NativeStoreError.invalidCursor }
            return session.engine.browsePage(category: category, usage: usage, offset: offset)
        }, completion: completion)
    }
    func setCategoryEnabled(_ id: String, enabled: Bool, usage: [UsageEntry], completion: @escaping @Sendable (Result<PickerWorkerSnapshot, Error>) -> Void) {
        perform({ session in
            guard session.host == .nativeApp, !session.visibility.isReader else { throw NativeStoreError.readOnly }
            _ = try session.store.get().setCategoryEnabled(id, enabled: enabled)
            return self.snapshot(session, usage: usage)
        }, completion: completion)
    }
    func setCategoryExemplar(_ id: String, exemplar: CategoryExemplar?, usage: [UsageEntry], completion: @escaping @Sendable (Result<PickerWorkerSnapshot, Error>) -> Void) {
        perform({ session in
            _ = try session.store.get().setCategoryExemplar(id, exemplar: exemplar)
            return self.snapshot(session, usage: usage)
        }, completion: completion)
    }
    func record(_ event: PickHistoryEvent, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        perform({ try $0.store.get().appendHistoryEvent(event) }, completion: completion)
    }

    private func snapshot(_ session: Session, usage: [UsageEntry]? = nil) -> PickerWorkerSnapshot {
        var preferences = BrowsePreferences(catalogueRevision: session.engine.catalogueRevision)
        var count: BrowseItemCount = .unknown
        var warnings = session.startupWarning.map { [$0] } ?? []
        func warn(_ error: Error) {
            let message = String(describing: error)
            if !warnings.contains(message) { warnings.append(message) }
        }
        if let usage { session.usage = usage }
        do {
            let store = try session.store.get()
            do { count = .known(try store.historyCount()) } catch { warn(error) }
            do {
                let local = try store.readPreferences()
                // A rejected visibility mirror must not discard readable local personalization.
                preferences = local
                preferences = try effectiveVisibility(local, access: session.visibility)
                try publishVisibility(local, access: session.visibility)
            } catch { warn(error) }
        } catch { warn(error) }
        return PickerWorkerSnapshot(categories: session.engine.categories, preferences: preferences,
                                    utilityCounts: ["utility:recents": count, "utility:frequent": .known(session.usage.filter { $0.count > 0 }.count)],
                                    canEditVisibility: session.host == .nativeApp && !session.visibility.isReader,
                                    warning: warnings.isEmpty ? nil : warnings.joined(separator: " "))
    }
    private func perform<T>(_ work: @escaping (Session) throws -> T, completion: @escaping @Sendable (Result<T, Error>) -> Void) {
        queue.async { [self] in
            guard case .ready(let session) = phase else { completion(.failure(failure())); return }
            do { completion(.success(try work(session))) } catch { completion(.failure(error)) }
        }
    }
    private func failure() -> Error {
        if case .failed(let error) = phase { return error }
        return NativeStoreError.invalidDocument("Glyph library is not ready")
    }

    private struct Seed: Decodable {
        struct Cell: Decodable { let position: Int; let status: String; let glyphID: String?; let symbol: String?; let provenance: String?; let categoryIDs: [String]? }
        let schemaVersion: Int; let importID: String; let sourceSHA256: String; let cells: [Cell]
    }
    private func importInitialData(_ config: Configuration, into store: NativePersonalizationStore) throws {
        let legacy = config.legacyUsage.filter { $0.count > 0 }.map { entry in
            PickHistoryEvent(eventID: "legacy-native-learning-v1:" + config.host.rawValue + ":" + entry.hexseq, glyphID: entry.hexseq,
                             symbol: entry.symbol ?? entry.hexseq.split(separator: " ").compactMap { UInt32($0, radix: 16).flatMap(UnicodeScalar.init).map(String.init) }.joined(),
                             occurredAt: entry.lastUsed.map { $0 * 1_000 }, provenance: .legacyAggregate(source: "Native learning-v1", count: entry.count))
        }
        _ = try store.importHistoryOnce(PickHistoryImport(importID: "legacy-native-learning-v1:" + config.host.rawValue, events: legacy))
        guard let file = config.seedURL else { return }
        let seed = try JSONDecoder().decode(Seed.self, from: Data(contentsOf: file))
        guard seed.schemaVersion == 1, !seed.importID.isEmpty else { throw NativeStoreError.invalidDocument("Invalid Recents seed") }
        var events: [PickHistoryEvent] = []
        for cell in seed.cells.sorted(by: { $0.position < $1.position }) where cell.status == "verified" || cell.status == "reconstructed" {
            guard let id = cell.glyphID, let symbol = cell.symbol, !id.isEmpty, !symbol.isEmpty, cell.position >= 0 else { throw NativeStoreError.invalidDocument("Invalid Recents seed cell") }
            let eventID = seed.importID + ":cell:" + String(cell.position)
            events.append(PickHistoryEvent(eventID: eventID, glyphID: id, symbol: symbol, occurredAt: nil,
                                          provenance: .snapshotImport(importID: seed.importID, source: "UniChar Recents snapshot " + seed.sourceSHA256 + "; " + (cell.provenance ?? cell.status), position: cell.position)))
            _ = try store.applyCategoryDefaults(migrationID: eventID, categoryIDs: cell.categoryIDs ?? [])
        }
        _ = try store.importHistory(PickHistoryImport(importID: seed.importID, events: events))
    }
}
