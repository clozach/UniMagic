import SwiftUI

enum GlyphCategoryRoute: Identifiable {
    case context([BrowseContextTarget]), symbol
    var id: String { if case .context = self { return "context" }; return "symbol" }
}

struct GlyphCategoryActions: View {
    @ObservedObject var model: PickerModel
    let item: PickerGlyphItem
    let targets: [BrowseContextTarget]
    let chosenSymbolCategoryID: String?
    @Binding var route: GlyphCategoryRoute?
    let assignSymbol: (BrowseCategory) -> Void
    @ScaledMetric(relativeTo: .body) private var resetRowHeight: CGFloat = 44
    private var originCategory: BrowseCategory? {
        guard case .browse(let occurrence) = item,
              let category = model.categories.first(where: { $0.id == occurrence.categoryID }), !category.isUtility else { return nil }
        return category
    }
    private var symbolCategory: BrowseCategory? {
        model.categories.first { $0.id == (chosenSymbolCategoryID ?? originCategory?.id) }
    }
    private var originTarget: BrowseContextTarget? { targets.first { $0.categoryID == originCategory?.id } }
    private var contextCategories: [BrowseCategory] {
        let ids = Set(targets.map(\.categoryID))
        return model.categories.filter { ids.contains($0.id) }
    }
    var body: some View {
        Section("Category") {
            Button {
                if let target = originTarget ?? (targets.count == 1 ? targets.first : nil) { model.showInCategory(target) }
                else { route = .context(targets) }
            } label: {
                actionLabel("Show in category", image: "square.grid.2x2", category: originCategory)
            }.disabled(targets.isEmpty).accessibilityIdentifier("glyph-show-in-category")
            if originTarget != nil && contextCategories.count > 1 {
                Button("Other categories…") { route = .context(targets) }.accessibilityIdentifier("glyph-other-contexts")
            }
            Button {
                if let category = originCategory { assignSymbol(category) } else { route = .symbol }
            } label: {
                actionLabel("Use as category symbol", image: "bookmark", category: originCategory)
            }.accessibilityIdentifier("glyph-use-category-symbol")
            if originCategory != nil {
                Button("Choose another category…") { route = .symbol }.accessibilityIdentifier("glyph-other-symbol-category")
            }
            Group {
                if let category = symbolCategory {
                    CategoryResetDefaultButton(category: category) { model.setCategoryExemplar(category.id, exemplar: nil) }
                        .disabled(category.exemplarOverride == nil)
                } else {
                    Text("Choose a category to change its symbol.").font(.caption).foregroundStyle(.secondary)
                }
            }.frame(height: resetRowHeight, alignment: .leading)
        }
    }
    private func actionLabel(_ title: String, image: String, category: BrowseCategory?) -> some View {
        HStack(spacing: 10) {
            if let category { CategoryExemplarView(exemplar: category.exemplar) }
            else { Image(systemName: image).frame(width: 52, height: 36).accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                if let category {
                    Text(category.title + " · " + category.sourceLabel).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
