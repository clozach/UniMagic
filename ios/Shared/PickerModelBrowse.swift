import Foundation

extension PickerModel {
    func apply(_ snapshot: PickerWorkerSnapshot) {
        let categories = snapshot.categories.map { category -> BrowseCategory in
            var next = category; next.exemplarOverride = snapshot.preferences.exemplarOverrides[category.id]; return next
        }
        let enabled = categories.filter { snapshot.preferences.categoryVisibility[$0.id] ?? $0.defaultEnabled }
        let displayed = categories.filter { candidate in enabled.contains { $0.id == candidate.id } || candidate.id == contextTarget?.categoryID }
        let old = Dictionary(uniqueKeysWithValues: sections.map { ($0.id, $0) })
        let next = displayed.map { category -> PickerBrowseSection in
            if var existing = old[category.id] { existing.category = category; return existing }
            return PickerBrowseSection(category: category, totalCount: snapshot.utilityCounts[category.id])
        }
        for id in old.keys where !next.contains(where: { $0.id == id }) { pageGenerations[id, default: 0] += 1 }
        change {
            $0.categories = categories; $0.enabled = enabled; $0.sections = next
            $0.preferences = snapshot.preferences; $0.canEditVisibility = snapshot.canEditVisibility
            if let warning = snapshot.warning { $0.message = warning }
        }
        if !next.contains(where: { $0.id == selectedCategoryID }) {
            change { $0.selectedCategoryID = enabled.first(where: { !$0.isUtility })?.id ?? enabled.first?.id ?? "" }
        }
    }

    func ensureSectionLoaded(_ categoryID: String) {
        guard let section = sections.first(where: { $0.id == categoryID }), section.items.isEmpty,
              case .more = section.load else { return }
        loadNextPage(categoryID)
    }
    func loadNextPage(_ categoryID: String) { requestPage(categoryID, leading: false) }
    func loadPreviousPage(_ categoryID: String) { requestPage(categoryID, leading: true) }
    func loadMore(_ titleOrID: String) { if let id = resolveCategory(titleOrID)?.id { loadNextPage(id) } }

    private func requestPage(_ categoryID: String, leading: Bool) {
        guard let worker, let section = sections.first(where: { $0.id == categoryID }) else { return }
        let cursor: BrowseCursor
        switch leading ? section.leadingLoad : section.load {
        case .more(let next), .failed(_, let next): cursor = next
        case .loading, .complete: return
        }
        if section.category.isRecent {
            switch cursor {
            case .history(_, let position): historyCursors[categoryID, default: [:]][position] = cursor
            case .offset(0): historyCursors[categoryID, default: [:]][0] = .history(cursor: nil, position: 0)
            default: break
            }
        }
        if section.category.isRecent, let first = historyFirstPages[categoryID], cursor == .offset(0) || cursor == .history(cursor: nil, position: 0) {
            install(first, categoryID: categoryID, leading: leading); return
        }
        let generation = pageGenerations[categoryID, default: 0]
        change { state in
            guard let index = state.sections.firstIndex(where: { $0.id == categoryID }) else { return }
            if leading { state.sections[index].leadingLoad = .loading } else { state.sections[index].load = .loading }
        }
        worker.page(category: section.category, cursor: cursor, usage: browsingUsage) { [weak self] result in
            Task { @MainActor in
                guard let self, self.pageGenerations[categoryID, default: 0] == generation else { return }
                switch result {
                case .success(let page): self.install(page, categoryID: categoryID, leading: leading)
                case .failure(let error):
                    self.change { state in
                        guard let index = state.sections.firstIndex(where: { $0.id == categoryID }) else { return }
                        let failed = PickerBrowseSection.Load.failed(String(describing: error), cursor)
                        if leading { state.sections[index].leadingLoad = failed } else { state.sections[index].load = failed }
                        state.message = String(describing: error)
                    }
                }
            }
        }
    }

    func install(_ page: BrowsePage, categoryID: String, leading: Bool, replacing: Bool = false) {
        if case .history(_, let position) = page.nextCursor { historyCursors[categoryID, default: [:]][position] = page.nextCursor }
        if let category = categories.first(where: { $0.id == categoryID }), category.isRecent, page.startOffset == 0, historyFirstPages[categoryID] == nil { historyFirstPages[categoryID] = page }
        touchClock += 1; sectionTouches[categoryID] = touchClock
        change { state in
            guard let index = state.sections.firstIndex(where: { $0.id == categoryID }) else { return }
            var section = state.sections[index]
            let startsWindow = section.items.isEmpty
            var items = Dictionary(uniqueKeysWithValues: (replacing ? [] : section.items).map { ($0.id, $0) })
            for item in page.items { items[item.id] = item }
            section.items = items.values.sorted { $0.position < $1.position }
            if let target = contextTarget {
                section.items = section.items.map { item in
                    guard item.id == target.occurrenceID else { return item }
                    return BrowseOccurrence(id: item.id, categoryID: item.categoryID, position: item.position, glyph: target.glyph, provenance: item.provenance)
                }
            }
            if replacing || startsWindow || section.totalCount == .unknown { section.totalCount = page.totalCount }
            if leading {
                section.leadingLoad = page.startOffset > 0 ? .more(previousCursor(categoryID, start: page.startOffset, history: section.category.isRecent)) : .complete
            } else { section.load = page.nextCursor.map(PickerBrowseSection.Load.more) ?? .complete }
            if replacing { section.leadingLoad = page.startOffset > 0 ? .more(.offset(max(0, page.startOffset - 100))) : .complete }
            if section.items.count > 300 {
                if leading {
                    section.items = Array(section.items.prefix(300))
                    let next = (section.items.last?.position ?? 0) + 1
                    section.load = .more(section.category.isRecent ? (historyCursors[categoryID]?[next] ?? .history(cursor: nil, position: 0)) : .offset(next))
                } else {
                    section.items = Array(section.items.suffix(300))
                    section.leadingLoad = .more(previousCursor(categoryID, start: section.items.first?.position ?? 0, history: section.category.isRecent))
                }
            }
            state.sections[index] = section
        }
        cache(page.glyphs)
        trimSections(keeping: categoryID)
    }
    private func previousCursor(_ id: String, start: Int, history: Bool) -> BrowseCursor {
        let position = max(0, start - 100)
        if history { return historyCursors[id]?[position] ?? .history(cursor: nil, position: 0) }
        return .offset(position)
    }
    private func trimSections(keeping id: String) {
        let loaded = sections.filter { !$0.items.isEmpty && $0.id != id && $0.id != selectedCategoryID }.sorted { sectionTouches[$0.id, default: 0] > sectionTouches[$1.id, default: 0] }
        let evicted = Set(loaded.dropFirst(3).map(\.id))
        for id in evicted { pageGenerations[id, default: 0] += 1 }
        change { state in
            for index in state.sections.indices where evicted.contains(state.sections[index].id) {
                state.sections[index].items = []; state.sections[index].load = .more(.offset(0)); state.sections[index].leadingLoad = .complete
            }
        }
    }

    func selectCategory(id: String, requestScroll: Bool = true) {
        guard enabledCategories.contains(where: { $0.id == id }) else { return }
        contextGeneration += 1; contextTarget = nil; returnLocations = []
        apply(PickerWorkerSnapshot(categories: categories, preferences: preferences, utilityCounts: [:], canEditVisibility: canEditCategoryVisibility, warning: nil))
        browsingUsage = data.learning.usage
        change { $0.selectedCategoryID = id; $0.searchNavigation = nil }
        query = ""
        if let section = sections.first(where: { $0.id == id }), section.category.isUtility {
            resetUtility(id, count: .unknown)
        }
        if requestScroll { change { $0.navigation = .section(UUID(), categoryID: id) } }
        ensureSectionLoaded(id)
    }
    func selectCategory(_ titleOrID: String, requestScroll: Bool = true) { if let id = resolveCategory(titleOrID)?.id { selectCategory(id: id, requestScroll: requestScroll) } }
    func resolveCategory(_ titleOrID: String) -> BrowseCategory? { categories.first { $0.id == titleOrID } ?? categories.first { $0.title == titleOrID } }
    func visibleSectionChanged(_ categoryID: String, leadingOccurrenceID: String? = nil) {
        guard sections.contains(where: { $0.id == categoryID }) else { return }
        if let leadingOccurrenceID { anchors[categoryID] = leadingOccurrenceID }
        let returningToUtility = selectedCategoryID != categoryID && categories.first(where: { $0.id == categoryID })?.isUtility == true
        change { $0.selectedCategoryID = categoryID }
        if returningToUtility { refreshConfiguration() } else { ensureSectionLoaded(categoryID) }
    }
    func cycleCategory(forward: Bool) {
        guard !enabledCategories.isEmpty else { return }
        let index = enabledCategories.firstIndex { $0.id == selectedCategoryID } ?? 0
        selectCategory(id: enabledCategories[(index + (forward ? 1 : enabledCategories.count - 1)) % enabledCategories.count].id)
    }

    func resetUtility(_ id: String, count: BrowseItemCount) {
        if sections.first(where: { $0.id == id })?.category.source == .utility(.frequent) {
            browsingUsage = data.learning.usage
        }
        pageGenerations[id, default: 0] += 1
        historyCursors[id] = nil; historyFirstPages[id] = nil
        utilityRevisions[id] = pickRevision
        change { state in if let index = state.sections.firstIndex(where: { $0.id == id }) { state.sections[index] = PickerBrowseSection(category: state.sections[index].category, totalCount: count) } }
    }
}
