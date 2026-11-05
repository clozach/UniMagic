import Foundation

extension PickerModel {
    func samples(for categoryID: String) async -> [BrowseOccurrence] {
        guard let worker, let category = categories.first(where: { $0.id == categoryID }) else { return [] }
        return await withCheckedContinuation { continuation in worker.samples(category: category) { continuation.resume(returning: $0) } }
    }
    func refreshConfiguration() {
        guard let worker else { return }
        worker.refresh(usage: data.learning.usage) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let snapshot):
                    self.apply(snapshot)
                    for section in self.sections where section.category.isUtility {
                        let count = snapshot.utilityCounts[section.id] ?? .unknown
                        if self.utilityRevisions[section.id, default: 0] < self.pickRevision || (count != .unknown && count != section.totalCount) { self.resetUtility(section.id, count: count) }
                    }
                    self.ensureSectionLoaded(self.selectedCategoryID)
                case .failure(let error): self.message = String(describing: error)
                }
            }
        }
    }
    func setCategoryEnabled(_ id: String, enabled: Bool) {
        guard categories.contains(where: { $0.id == id }), let worker else { return }
        guard canEditCategoryVisibility else { message = "Choose visible categories in the app."; return }
        worker.setCategoryEnabled(id, enabled: enabled, usage: data.learning.usage) { [weak self] result in
            Task { @MainActor in self?.applyPreferencesResult(result) }
        }
    }
    func setCategoryExemplar(_ id: String, exemplar: CategoryExemplar?) {
        guard categories.contains(where: { $0.id == id }), let worker else { return }
        worker.setCategoryExemplar(id, exemplar: exemplar, usage: data.learning.usage) { [weak self] result in
            Task { @MainActor in self?.applyPreferencesResult(result) }
        }
    }
    private func applyPreferencesResult(_ result: Result<PickerWorkerSnapshot, Error>) {
        switch result {
        case .success(let snapshot): apply(snapshot); ensureSectionLoaded(selectedCategoryID)
        case .failure(let error): message = String(describing: error)
        }
    }

    func picked(_ item: PickerGlyphItem, symbol: String? = nil, destination: (String) -> Void, feedback: String) {
        picked(item.glyph, symbol: symbol, origin: item.origin, destination: destination, feedback: feedback)
    }
    func picked(_ shown: Glyph, symbol: String? = nil, origin: BrowseOrigin? = nil, destination: (String) -> Void, feedback: String) {
        let exact = symbol ?? shown.symbol, now = Date().timeIntervalSince1970
        // A toned pick (🧘🏻‍♀️) learns under its own id, so a word can mean that tone.
        let glyph = shown.picked(symbol: exact)
        destination(exact)
        pickRevision += 1
        let next = data.learning.pick(query: query, hexseq: glyph.id, symbol: exact, at: now)
        change { if next.learned != $0.learning.learned { $0.undo = $0.learning }; $0.learning = next }
        persistLearning(success: feedback + " " + exact)
        let source = origin ?? (detailSelection?.glyph.id == shown.id ? detailSelection?.origin : nil)
        let event = PickHistoryEvent(glyphID: glyph.id, symbol: exact, occurredAt: now * 1_000,
                                     provenance: .pick(host: historyHost, action: historyHost == .nativeKeyboard ? .insert : .copy), origin: source)
        worker?.record(event) { [weak self] result in
            if case .failure(let error) = result { Task { @MainActor in self?.message = "History unavailable: " + String(describing: error) } }
        }
    }
    func teach(_ word: String, glyph: Glyph) {
        let term = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty, term.count <= 64, term.unicodeScalars.allSatisfy({ CharacterSet.letters.union(.whitespaces).contains($0) }) else {
            message = "Use a word or phrase of letters"; return
        }
        change { $0.undo = $0.learning; $0.learning = $0.learning.teach(term: term, hexseq: glyph.id) }
        persistLearning(success: "Learned “\(term)”")
    }
    func forget(_ term: String, glyph: Glyph) {
        change { $0.undo = $0.learning; $0.learning = $0.learning.unlearn(term: term, hexseq: glyph.id) }
        persistLearning(success: "Forgot “\(term)”")
    }
    func undo() {
        guard let old = data.undo else { return }
        change { $0.learning = old; $0.undo = nil }
        persistLearning(success: "Learning change undone")
    }
    var canUndo: Bool { data.undo != nil }
    func learnedWords(_ glyph: Glyph) -> [String] { data.learning.learned.filter { $0.hexseq == glyph.id }.map(\.term).sorted() }

    private func persistLearning(success: String) {
        guard persistenceError == nil else { message = persistenceError!; return }
        do {
            var raw: [String: Any] = [:]
            if FileManager.default.fileExists(atPath: storageURL.path) {
                let bytes = try Data(contentsOf: storageURL)
                let old = try JSONDecoder().decode(LearningStore.self, from: bytes)
                guard old.version == 1 else { throw NativeStoreError.unsupportedVersion(old.version) }
                guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw NativeStoreError.invalidDocument("Invalid learning file") }
                raw = object
            }
            let encoded = try JSONEncoder().encode(data.learning)
            let current = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            for (name, keys) in [("learned", ["term", "hexseq", "type", "score"]), ("usage", ["hexseq", "count", "lastUsed", "symbol"])] {
                let old = raw[name] as? [[String: Any]] ?? []
                let fresh = current[name] as? [[String: Any]] ?? []
                func identity(_ entry: [String: Any]) -> String { (entry["term"] as? String ?? "") + "\u{0}" + (entry["hexseq"] as? String ?? "") }
                raw[name] = fresh.map { entry -> [String: Any] in
                    var merged = old.first { identity($0) == identity(entry) } ?? [:]
                    for key in keys { merged.removeValue(forKey: key) }
                    return merged.merging(entry) { _, new in new }
                }
            }
            raw["version"] = 1
            try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]).write(to: storageURL, options: .atomic)
            message = success
        } catch { message = "Learning stays in this session; existing file preserved. " + String(describing: error) }
    }
    func cache(_ glyphs: [Glyph]) {
        let ids = Set(glyphs.map(\.id))
        cacheOrder.removeAll { ids.contains($0) }
        cacheOrder += glyphs.map(\.id)
        let removed = Array(cacheOrder.prefix(max(0, cacheOrder.count - 512)))
        if !removed.isEmpty { cacheOrder.removeFirst(removed.count) }
        change { state in
            for id in removed { state.glyphCache.removeValue(forKey: id) }
            for glyph in glyphs { state.glyphCache[glyph.id] = glyph }
        }
    }
}
