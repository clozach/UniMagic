import Foundation

struct PickerBrowseSection: Identifiable {
    enum Load: Equatable { case more(BrowseCursor), loading, complete, failed(String, BrowseCursor) }
    var category: BrowseCategory
    var items: [BrowseOccurrence] = []
    var load: Load = .more(.offset(0))
    var leadingLoad: Load = .complete
    var totalCount: BrowseItemCount
    var id: String { category.id }
    var displayCount: Int { totalCount.value ?? ((items.last?.position ?? -1) + 1) }

    func item(at position: Int) -> BrowseOccurrence? {
        guard let first = items.first else { return nil }
        let index = position - first.position
        guard items.indices.contains(index), items[index].position == position else { return nil }
        return items[index]
    }

    var glyphs: [Glyph] { items.map(\.glyph) }
    init(category: BrowseCategory, totalCount: BrowseItemCount? = nil) {
        self.category = category
        self.totalCount = totalCount ?? .known(category.memberCount)
    }
}

enum PickerGlyphItem: Identifiable {
    case search(Glyph), browse(BrowseOccurrence)
    var glyph: Glyph { switch self { case .search(let g): return g; case .browse(let item): return item.glyph } }
    var origin: BrowseOrigin? { switch self { case .search: return nil; case .browse(let item): return item.sourceOrigin ?? item.origin } }
    var id: String { switch self { case .search(let g): return "search:" + g.id; case .browse(let item): return item.id } }
}

struct PickerSearchNavigationTarget: Identifiable { let id = UUID(); let glyphID: String }
