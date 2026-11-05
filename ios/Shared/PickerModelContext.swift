import Foundation

extension PickerModel {
    func contexts(for glyph: Glyph, origin: BrowseOrigin? = nil) async -> [BrowseContextTarget] {
        guard let worker else { return [] }
        return await withCheckedContinuation { continuation in worker.contexts(glyph: glyph, origin: origin) { continuation.resume(returning: $0) } }
    }
    func showInCategory(_ target: BrowseContextTarget) {
        guard let worker, let category = categories.first(where: { $0.id == target.categoryID }) else { return }
        returnLocations.append(ReturnLocation(query: query, categoryID: selectedCategoryID, anchor: sections.first(where: { $0.id == selectedCategoryID })?.items.first(where: { $0.id == anchors[selectedCategoryID] }), context: contextTarget,
                                              searchGlyphID: query.isEmpty ? nil : detailSelection?.glyph.id))
        contextTarget = target
        query = ""
        contextGeneration += 1; let generation = contextGeneration
        let snapshot = PickerWorkerSnapshot(categories: categories, preferences: preferences, utilityCounts: [:], canEditVisibility: canEditCategoryVisibility, warning: nil)
        apply(snapshot)
        change { $0.selectedCategoryID = target.categoryID }
        pageGenerations[target.categoryID, default: 0] += 1
        let cursor = BrowseCursor.offset(max(0, target.position - 50))
        worker.page(category: category, cursor: cursor, usage: browsingUsage) { [weak self] result in
            Task { @MainActor in
                guard let self, self.contextGeneration == generation, self.query.isEmpty else { return }
                switch result {
                case .success(let page):
                    self.install(page, categoryID: target.categoryID, leading: false, replacing: true)
                    self.detailSelection = nil
                    self.change { $0.navigation = .occurrence(UUID(), target) }
                case .failure(let error): self.message = String(describing: error)
                }
            }
        }
    }
    func returnFromContext() {
        guard let location = returnLocations.popLast() else { return }
        contextGeneration += 1; contextTarget = location.context
        apply(PickerWorkerSnapshot(categories: categories, preferences: preferences, utilityCounts: [:], canEditVisibility: canEditCategoryVisibility, warning: nil))
        change { $0.selectedCategoryID = location.categoryID }
        query = location.query
        change { $0.searchNavigation = location.searchGlyphID.map { PickerSearchNavigationTarget(glyphID: $0) } }
        guard query.isEmpty else { return }
        guard let anchor = location.anchor else {
            ensureSectionLoaded(location.categoryID)
            change { $0.navigation = .section(UUID(), categoryID: location.categoryID) }; return
        }
        let target = BrowseContextTarget(categoryID: anchor.categoryID, occurrenceID: anchor.id, position: anchor.position, glyph: anchor.glyph, match: .exactOccurrence)
        if sections.first(where: { $0.id == location.categoryID })?.items.contains(where: { $0.id == anchor.id }) == true {
            change { $0.navigation = .occurrence(UUID(), target) }; return
        }
        guard let worker, let category = categories.first(where: { $0.id == location.categoryID }) else { return }
        let generation = contextGeneration
        let start = category.isRecent ? (anchor.position / 100) * 100 : max(0, anchor.position - 50)
        let cursor: BrowseCursor = category.isRecent ? (historyCursors[category.id]?[start] ?? .history(cursor: nil, position: 0)) : .offset(start)
        if category.isRecent, start == 0, let page = historyFirstPages[category.id] {
            install(page, categoryID: category.id, leading: false, replacing: true)
            change { $0.navigation = .occurrence(UUID(), target) }; return
        }
        worker.page(category: category, cursor: cursor, usage: browsingUsage) { [weak self] result in
            Task { @MainActor in
                guard let self, self.contextGeneration == generation, self.query.isEmpty else { return }
                switch result {
                case .success(let page): self.install(page, categoryID: category.id, leading: false, replacing: true); self.change { $0.navigation = .occurrence(UUID(), target) }
                case .failure(let error): self.message = String(describing: error)
                }
            }
        }
    }

}
