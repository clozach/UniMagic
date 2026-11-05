import Foundation
import SwiftUI

@main struct PickerModelChecks {
    @MainActor static func wait(_ description: String, _ predicate: () -> Bool) async throws {
        for _ in 0..<1_000 { if predicate() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        fatalError("Timed out: " + description)
    }
    static func check(_ condition: Bool, _ description: String) { precondition(condition, description) }
    @MainActor static func section(_ model: PickerModel, _ id: String) -> PickerBrowseSection { model.sections.first { $0.id == id }! }

    @MainActor static func main() async throws {
        let database = URL(fileURLWithPath: CommandLine.arguments[1]), seed = URL(fileURLWithPath: CommandLine.arguments[2])
        let root = URL(fileURLWithPath: "/tmp/unimagic-browse-engine/model-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appRoot = root.appendingPathComponent("app"), keyboardRoot = root.appendingPathComponent("keyboard"), shared = root.appendingPathComponent("shared/visibility.json")
        try FileManager.default.createDirectory(at: appRoot, withIntermediateDirectories: true)
        let legacy = #"{"version":1,"learned":[],"usage":[{"hexseq":"2014","count":9,"lastUsed":100,"symbol":"—","futureEntry":"keep"}],"futureTop":{"keep":true}}"#
        try Data(legacy.utf8).write(to: appRoot.appendingPathComponent("learning-v1.json"))
        let app = PickerModel(environment: PickerEnvironment(databaseURL: database, directory: appRoot, seedURL: seed), historyHost: .nativeApp, visibility: .appPublisher(shared))
        try await wait("startup metadata and first bounded page") { app.categories.count == 354 && section(app, "set:Emojis").items.count == 100 }
        check(app.selectedCategoryID == "set:Emojis", "Emoji landing")
        check(app.sections.filter { !$0.items.isEmpty }.count == 1, "Only selected section materialized at startup")
        check(app.sections.reduce(0) { $0 + $1.items.count } == 100, "No eager354-page allocation")
        let preview = await app.samples(for: "unichar:Category-MusicalSymbols")
        check(preview.count == 6 && preview.first?.glyph.symbol == "♩", "Bounded async representative samples")
        let appStore = try NativePersonalizationStore(location: .local(NativePersonalizationPaths.localDirectory(inApplicationSupport: appRoot)), catalogueRevision: app.preferences.catalogueRevision)
        check(try appStore.historyCount() == 29, "28 snapshot cells + one legacy aggregate; no fabricated repeated picks")
        let initialEvents = try appStore.readHistoryPage(limit: 100).events
        let snapshots = initialEvents.filter { if case .snapshotImport = $0.provenance { return true }; return false }
        check(snapshots.count == 28 && snapshots.allSatisfy { $0.occurredAt == nil }, "Snapshot timestamps remain unknown")
        check(snapshots.map(\.eventID) == (0..<28).map { "pic4-ebd9475e5bb3c23ab755-v1:cell:" + String($0) }, "Shared deterministic event IDs/source order")
        check(snapshots.contains { $0.symbol.utf8.elementsEqual("™︎".utf8) }, "Reconstructed text-style TM preserved")
        for id in ["block:Runic", "block:Pahawh Hmong", "block:Katakana", "block:Greek and Coptic", "block:Combining Diacritical Marks"] {
            check(app.enabledCategories.contains { $0.id == id }, "Seed enables represented category " + id)
        }
        let engine = try GlyphSearch(databaseURL: database), dash = engine.glyph(id: "2014")!, heart = engine.glyph(id: "2764")!
        app.teach("line", glyph: dash)
        let roundTrip = try JSONSerialization.jsonObject(with: Data(contentsOf: appRoot.appendingPathComponent("learning-v1.json"))) as! [String: Any]
        check((roundTrip["futureTop"] as? [String: Bool])?["keep"] == true, "Unknown learning-v1 root fields preserved")
        check((roundTrip["usage"] as? [[String: Any]])?.first?["futureEntry"] as? String == "keep", "Unknown learning entry fields preserved")
        app.undo()
        check(try appStore.historyCount() == 29, "Learning undo cannot erase history")
        app.setCategoryEnabled("block:Runic", enabled: false)
        try await wait("explicit visibility override") { app.preferences.categoryVisibility["block:Runic"] == false }
        let restarted = PickerModel(environment: PickerEnvironment(databaseURL: database, directory: appRoot, seedURL: seed), historyHost: .nativeApp, visibility: .appPublisher(shared))
        try await wait("idempotent restart") { restarted.categories.count == 354 && !restarted.isLoading }
        check(try appStore.historyCount() == 29, "Seed/legacy import idempotent")
        check(!restarted.enabledCategories.contains { $0.id == "block:Runic" }, "Explicit false survives seed rerun")

        let keyboard = PickerModel(environment: PickerEnvironment(databaseURL: database, directory: keyboardRoot, seedURL: seed), historyHost: .nativeKeyboard, visibility: .keyboardReader(shared))
        try await wait("keyboard initialization") { keyboard.categories.count == 354 && section(keyboard, "set:Emojis").items.count == 100 }
        check(!keyboard.canEditCategoryVisibility, "Keyboard visibility read-only")
        check(!keyboard.enabledCategories.contains { $0.id == "block:Runic" }, "App visibility reaches keyboard")
        let sharedBefore = try Data(contentsOf: shared)
        keyboard.setCategoryExemplar("set:Emojis", exemplar: .unicode("X"))
        try await wait("local keyboard exemplar") { keyboard.categories.first { $0.id == "set:Emojis" }?.symbol == "X" }
        check(app.categories.first { $0.id == "set:Emojis" }?.symbol == "🐻‍❄️", "Exemplars remain separate")
        check(try Data(contentsOf: shared) == sharedBefore, "Keyboard never writes visibility group")
        let keyboardStore = try NativePersonalizationStore(location: .local(NativePersonalizationPaths.localDirectory(inApplicationSupport: keyboardRoot)), catalogueRevision: keyboard.preferences.catalogueRevision)
        keyboard.selectCategory(id: "utility:recents")
        try await wait("initial Recents") { section(keyboard, "utility:recents").items.count == 28 }
        var inserted = ""
        keyboard.picked(.search(heart), symbol: "❤︎", destination: { inserted = $0 }, feedback: "Inserted")
        try await wait("history appended") { (try? keyboardStore.historyCount()) == 29 }
        check(inserted.utf8.elementsEqual("❤︎".utf8), "Exact proxy payload")
        check(section(keyboard, "utility:recents").totalCount == .known(28), "Current Recents snapshot stays stable under pick")
        keyboard.visibleSectionChanged("set:Emojis")
        keyboard.visibleSectionChanged("utility:recents")
        try await wait("scroll away/back refreshes Recents") { section(keyboard, "utility:recents").totalCount == .known(29) && section(keyboard, "utility:recents").items.first?.glyph.symbol.utf8.elementsEqual("❤︎".utf8) == true }
        keyboard.picked(.search(heart), destination: { _ in }, feedback: "Inserted")
        keyboard.refreshConfiguration()
        try await wait("configuration refresh updates existing utility") { section(keyboard, "utility:recents").totalCount == .known(30) && section(keyboard, "utility:recents").items.count == 30 }
        check(try appStore.historyCount() == 29, "App/keyboard histories remain separate")
        let live = try keyboardStore.readHistoryPage(limit: 2).events
        check(live.count == 2 && live[0].eventID != live[1].eventID, "Repeated picks retain separate event IDs")
        check(live.allSatisfy { $0.occurredAt != nil }, "Actual picks have actual times")
        try keyboardStore.appendHistoryEvent(PickHistoryEvent(eventID: "other-instance", glyphID: dash.id, symbol: dash.symbol, occurredAt: Date().timeIntervalSince1970 * 1_000 + 1, provenance: .pick(host: .nativeKeyboard, action: .insert)))
        keyboard.visibleSectionChanged("set:Emojis"); keyboard.visibleSectionChanged("utility:recents")
        try await wait("other-instance history refresh on return") { section(keyboard, "utility:recents").totalCount == .known(31) && section(keyboard, "utility:recents").items.first?.glyph.id == dash.id }

        keyboard.selectCategory(id: "set:Other Glyphs")
        try await wait("full-corpus first page") { section(keyboard, "set:Other Glyphs").items.count == 100 }
        for _ in 0..<5 {
            let before = section(keyboard, "set:Other Glyphs").items.last!.position
            keyboard.loadNextPage("set:Other Glyphs")
            try await wait("forward bounded page") { section(keyboard, "set:Other Glyphs").items.last!.position > before }
        }
        check(section(keyboard, "set:Other Glyphs").items.count == 300, "Fixed category retains at most300 occurrences")
        let anchor = section(keyboard, "set:Other Glyphs").items[100]
        keyboard.visibleSectionChanged("set:Other Glyphs", leadingOccurrenceID: anchor.id)
        keyboard.openDetails(.browse(anchor))
        let contexts = await keyboard.contexts(for: anchor.glyph, origin: anchor.origin)
        let target = contexts.first { $0.categoryID.hasPrefix("block:") && $0.categoryID != "set:Other Glyphs" }!
        let wasEnabled = keyboard.enabledCategories.contains { $0.id == target.categoryID }
        keyboard.showInCategory(target)
        try await wait("context window") { keyboard.navigationTarget?.categoryID == target.categoryID && keyboard.sections.contains { $0.id == target.categoryID && $0.items.contains { $0.id == target.occurrenceID } } }
        check(keyboard.enabledCategories.contains { $0.id == target.categoryID } == wasEnabled, "Context preview does not change persistent visibility")
        let others = keyboard.enabledCategories.filter { $0.id != target.categoryID && $0.id != "set:Other Glyphs" && $0.memberCount > 0 }.prefix(7)
        for category in others {
            keyboard.ensureSectionLoaded(category.id)
            try await wait("viewport-near section") { !section(keyboard, category.id).items.isEmpty }
        }
        check(section(keyboard, "set:Other Glyphs").items.isEmpty, "Origin window actually evicted")
        keyboard.returnFromContext()
        try await wait("evicted late-page return anchor") {
            guard case .occurrence(_, let restored) = keyboard.navigationTarget else { return false }
            return restored.occurrenceID == anchor.id && restored.position == anchor.position && section(keyboard, "set:Other Glyphs").items.contains { $0.id == anchor.id }
        }
        check(keyboard.sections.filter { !$0.items.isEmpty }.count <= 5, "At most five warm section windows")
        keyboard.query = "heart"
        try await wait("live search") { keyboard.results.contains { $0.id == heart.id } && !keyboard.isLoading }
        keyboard.openDetails(.search(heart))
        let heartTarget = await keyboard.contexts(for: heart).first!
        keyboard.showInCategory(heartTarget)
        try await wait("search→context") { keyboard.navigationTarget?.categoryID == heartTarget.categoryID }
        keyboard.returnFromContext()
        try await wait("context→same search selection") { keyboard.query == "heart" && keyboard.searchSelectionID == heart.id && !keyboard.isLoading }

        let many = (0..<800).map { position in PickHistoryEvent(eventID: "large-cell:\(position)", glyphID: heart.id, symbol: heart.symbol, occurredAt: nil, provenance: .snapshotImport(importID: "large-test", source: "test", position: position)) }
        _ = try keyboardStore.importHistory(PickHistoryImport(importID: "large-test", events: many))
        keyboard.query = ""; keyboard.selectCategory(id: "utility:recents")
        try await wait("large history first page") { section(keyboard, "utility:recents").items.count == 100 }
        for _ in 0..<5 {
            let before = section(keyboard, "utility:recents").items.last!.position
            keyboard.loadNextPage("utility:recents")
            try await wait("history keyset page") { section(keyboard, "utility:recents").items.last!.position > before }
        }
        check(section(keyboard, "utility:recents").totalCount == .known(831), "Full history count retained")
        check(section(keyboard, "utility:recents").items.count == 300, "History window bounded")
        let first = section(keyboard, "utility:recents").items.first!.position
        keyboard.loadPreviousPage("utility:recents")
        try await wait("history backward page") { section(keyboard, "utility:recents").items.first!.position < first }
        check(section(keyboard, "utility:recents").items.count == 300, "Backward history window bounded")

        for host in [HistoryHost.nativeApp, .nativeKeyboard] {
            let directory = root.appendingPathComponent("frequent-" + host.rawValue)
            let candidate = PickerModel(environment: PickerEnvironment(databaseURL: database, directory: directory, seedURL: nil), historyHost: host, visibility: .local)
            try await wait("empty-usage host ready") { candidate.categories.count == 354 && !candidate.isLoading }
            let store = try NativePersonalizationStore(location: .local(NativePersonalizationPaths.localDirectory(inApplicationSupport: directory)), catalogueRevision: candidate.preferences.catalogueRevision)
            candidate.picked(.search(heart), destination: { _ in }, feedback: "Picked")
            try await wait("first actual pick") { (try? store.historyCount()) == 1 }
            candidate.visibleSectionChanged("utility:frequent")
            try await wait("continuous Frequent entry") { section(candidate, "utility:frequent").totalCount == .known(1) && section(candidate, "utility:frequent").load == .complete }
            check(section(candidate, "utility:frequent").glyphs.map(\.id) == [heart.id], "Continuous entry includes the new pick")
            let frozen = section(candidate, "utility:frequent").items.first!.glyph.symbol
            candidate.picked(.search(heart), symbol: "❤︎", destination: { _ in }, feedback: "Picked")
            candidate.picked(.search(dash), destination: { _ in }, feedback: "Picked")
            try await wait("picks recorded without moving current window") { (try? store.historyCount()) == 3 }
            check(section(candidate, "utility:frequent").glyphs.map(\.id) == [heart.id] && section(candidate, "utility:frequent").glyphs[0].symbol.utf8.elementsEqual(frozen.utf8), "Frequent stays fixed under the current interaction")
            candidate.visibleSectionChanged("set:Emojis"); candidate.visibleSectionChanged("utility:frequent")
            try await wait("continuous Frequent return") { section(candidate, "utility:frequent").totalCount == .known(2) && section(candidate, "utility:frequent").load == .complete }
            check(section(candidate, "utility:frequent").glyphs.map(\.id) == [heart.id, dash.id], "Continuous return reloads current usage")
            check(section(candidate, "utility:frequent").glyphs[0].symbol.utf8.elementsEqual("❤︎".utf8), "Continuous return preserves latest exact variant")
            for _ in 0..<3 { candidate.picked(.search(dash), destination: { _ in }, feedback: "Picked") }
            try await wait("new frequency recorded") { (try? store.historyCount()) == 6 }
            check(section(candidate, "utility:frequent").glyphs.first?.id == heart.id, "No reshuffle while picking")
            candidate.refreshConfiguration()
            try await wait("explicit refresh applies new frequency") { section(candidate, "utility:frequent").glyphs.first?.id == dash.id }
            for id in ["utility:frequent", "utility:recents"] {
                candidate.selectCategory(id: id)
                try await wait("utility window loaded") { !section(candidate, id).items.isEmpty && section(candidate, id).load == .complete }
                let expected = section(candidate, id).items.count + 1
                candidate.refreshConfiguration()
                candidate.picked(.search(id == "utility:frequent" ? engine.glyph(id: "00A9")! : heart), destination: { _ in }, feedback: "Picked")
                try await wait("pick during window refresh") { section(candidate, id).items.count == expected }
                check(section(candidate, id).totalCount == .known(expected), "First utility page pairs current count with current contents")
            }
        }

        for host in [HistoryHost.nativeApp, .nativeKeyboard] {
            for prior in [false, true] {
                let directory = root.appendingPathComponent("legacy-once-" + host.rawValue + String(prior))
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let usage: [[String: Any]] = prior ? [["hexseq":"2014", "count":9, "lastUsed":100, "symbol":"—"]] : []
                let file = directory.appendingPathComponent("learning-v1.json")
                try JSONSerialization.data(withJSONObject: ["version":1, "learned":[], "usage":usage]).write(to: file)
                func create() -> PickerModel { PickerModel(environment: PickerEnvironment(databaseURL: database, directory: directory, seedURL: nil), historyHost: host, visibility: .local) }
                let initial = create()
                try await wait("legacy baseline initialized") { initial.categories.count == 354 && !initial.isLoading }
                let store = try NativePersonalizationStore(location: .local(NativePersonalizationPaths.localDirectory(inApplicationSupport: directory)), catalogueRevision: initial.preferences.catalogueRevision)
                check(try store.historyCount() == (prior ? 1 : 0), "Only honest initial legacy imported")
                check(try store.rows("SELECT import_id FROM history_imports WHERE import_id=?", [.text("legacy-native-learning-v1:" + host.rawValue)]).count == 1, "Empty and nonempty legacy baselines both seal")
                initial.picked(.search(heart), symbol: "❤︎", destination: { _ in }, feedback: "Picked")
                try await wait("actual new pick recorded") { (try? store.historyCount()) == (prior ? 2 : 1) }
                let events = try store.readHistoryPage(limit: 100).events, saved = try Data(contentsOf: file)
                for _ in 0..<2 {
                    let restarted = create()
                    try await wait("legacy restart ready") { restarted.categories.count == 354 && !restarted.isLoading }
                    check(try store.readHistoryPage(limit: 100).events == events, "Restart never manufactures legacy from new usage")
                    check(try Data(contentsOf: file) == saved, "Restart leaves evolving learning file unchanged")
                }
                let legacyEvents = events.filter { if case .legacyAggregate = $0.provenance { return true }; return false }
                check(legacyEvents.count == (prior ? 1 : 0), "Honest legacy retained without new aggregates")
                if prior { check(legacyEvents[0].provenance == .legacyAggregate(source: "Native learning-v1", count: 9) && legacyEvents[0].occurredAt == 100_000, "Honest legacy count/date preserved") }
                check(events.filter { if case .pick(let source, _) = $0.provenance { return source == host }; return false }.count == 1, "One real action remains one real event")
                check(events.first!.symbol.utf8.elementsEqual("❤︎".utf8), "Actual pick presentation survives restart")
            }
        }

        let future = root.appendingPathComponent("future.json"), futureBytes = Data(#"{"schemaVersion":2,"categoryVisibility":{"keep":false},"future":true}"#.utf8)
        try futureBytes.write(to: future)
        do { try publishVisibility(BrowsePreferences(catalogueRevision: "new"), access: .appPublisher(future)); fatalError("Future visibility overwritten") } catch {}
        check(try Data(contentsOf: future) == futureBytes, "Future visibility preserved byte-for-byte")
        try Data(#"{"schemaVersion":1,"catalogueRevision":"old","categoryVisibility":{},"future":{"keep":true}}"#.utf8).write(to: future)
        try publishVisibility(BrowsePreferences(catalogueRevision: "new"), access: .appPublisher(future))
        let known = try JSONSerialization.jsonObject(with: Data(contentsOf: future)) as! [String: Any]
        check((known["future"] as? [String: Bool])?["keep"] == true, "Unknown v1 visibility fields preserved")
        let malformed = Data(#"{"schemaVersion":1,"future":true}"#.utf8)
        try malformed.write(to: future)
        do { try publishVisibility(BrowsePreferences(catalogueRevision: "new"), access: .appPublisher(future)); fatalError("Malformed visibility overwritten") } catch {}
        check(try Data(contentsOf: future) == malformed, "Malformed visibility preserved byte-for-byte")
        for (name, bytes) in [("malformed", malformed), ("future", futureBytes)] {
            for reader in [true, false] {
                let fixture = root.appendingPathComponent("visibility-\(name)-\(reader)"), mirror = fixture.appendingPathComponent("visibility.json")
                try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
                try bytes.write(to: mirror)
                let store = try NativePersonalizationStore(location: .local(NativePersonalizationPaths.localDirectory(inApplicationSupport: fixture)), catalogueRevision: app.preferences.catalogueRevision)
                _ = try store.setCategoryExemplar("set:Emojis", exemplar: .unicode("X"))
                _ = try store.setCategoryEnabled("block:Runic", enabled: false)
                try store.appendHistoryEvent(PickHistoryEvent(eventID: "local-real", glyphID: heart.id, symbol: "❤︎", occurredAt: 1_000, provenance: .pick(host: .nativeKeyboard, action: .insert)))
                let candidate = PickerModel(environment: PickerEnvironment(databaseURL: database, directory: fixture, seedURL: nil), historyHost: reader ? .nativeKeyboard : .nativeApp,
                                            visibility: reader ? .keyboardReader(mirror) : .appPublisher(mirror))
                try await wait("visibility failure fallback") { candidate.categories.count == 354 && !candidate.isLoading }
                check(candidate.preferences.exemplarOverrides["set:Emojis"] == .unicode("X"), "Bad shared visibility cannot hide local exemplar")
                check(candidate.preferences.categoryVisibility["block:Runic"] == false, "Bad shared visibility preserves local defaults")
                check(section(candidate, "utility:recents").totalCount == .known(1), "Bad shared visibility cannot hide known history count")
                check(!candidate.message.isEmpty, "Visibility failure remains visible")
                candidate.setCategoryExemplar("set:Emojis", exemplar: .unicode("Y"))
                try await wait("local preference writes survive bad mirror") { candidate.preferences.exemplarOverrides["set:Emojis"] == .unicode("Y") }
                check(section(candidate, "utility:recents").totalCount == .known(1), "Preference refresh keeps valid count")
                check(try Data(contentsOf: mirror) == bytes, "Rejected visibility remains byte-identical")
            }
        }
        let futureRoot = root.appendingPathComponent("future-learning")
        try FileManager.default.createDirectory(at: futureRoot, withIntermediateDirectories: true)
        let futureLearning = Data(#"{"version":2,"learned":[],"usage":[{"hexseq":"2014","count":50}]}"#.utf8)
        try futureLearning.write(to: futureRoot.appendingPathComponent("learning-v1.json"))
        let guarded = PickerModel(environment: PickerEnvironment(databaseURL: database, directory: futureRoot, seedURL: nil))
        try await wait("search works with unavailable legacy learning") { guarded.categories.count == 354 && !guarded.isLoading }
        guarded.picked(.search(dash), destination: { _ in }, feedback: "Copied")
        let guardedStore = try NativePersonalizationStore(location: .local(NativePersonalizationPaths.localDirectory(inApplicationSupport: futureRoot)), catalogueRevision: guarded.preferences.catalogueRevision)
        try await wait("new actual history survives unavailable legacy learning") { (try? guardedStore.historyCount()) == 1 }
        check(try Data(contentsOf: futureRoot.appendingPathComponent("learning-v1.json")) == futureLearning, "Future learning preserved")
        print("Model: lazy pages/bounded caches, all28 seed cells/idempotency, local histories/exemplars + readonly visibility, dirty Recents return/refresh, continuous Frequent freshness with stable current windows, one-time empty/nonempty legacy migration across restarts, evicted anchors, search selection return, forward-version preservation and visibility-error isolation pass")
    }
}
