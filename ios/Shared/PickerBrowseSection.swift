import Foundation

struct PickerBrowseSection: Identifiable {
    enum Load: Equatable { case more(BrowseCursor), loading, complete, failed(String, BrowseCursor) }
    var category: BrowseCategory
    var items: [BrowseOccurrence] = []
    var load: Load = .more(.offset(0))
    var leadingLoad: Load = .complete
    var totalCount: BrowseItemCount
    var id: String { category.id }
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
