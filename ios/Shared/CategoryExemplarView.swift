import SwiftUI

/// Keep legacy identity and user overrides while using OS artwork for old font IDs.
struct CategoryExemplarView: View {
    let exemplar: CategoryExemplar
    var size: CGFloat = 28
    var width: CGFloat = 52
    private var label: String {
        if case .customFont = exemplar { return exemplar.symbol }
        return GlyphDisplay.label(symbol: exemplar.symbol)
    }
    var body: some View {
        Group {
            if case .customFont(let symbol) = exemplar {
                Image(systemName: CategoryIcon.systemName(for: symbol)).font(.system(size: size))
            } else { Text(label).font(font) }
        }.lineLimit(label.hasPrefix("U+") ? 2 : 1).minimumScaleFactor(0.2)
            .frame(width: width, height: max(36, size + 4))
            .accessibilityHidden(true)
    }
    private var font: Font {
        if label.hasPrefix("U+") || label != exemplar.symbol && label.count > exemplar.symbol.count + 1 { return .system(size: 12) }
        return .system(size: size)
    }
}

struct CategoryLabelView: View {
    let category: BrowseCategory
    var showsCount = true
    var body: some View {
        HStack(spacing: 10) {
            CategoryExemplarView(exemplar: category.exemplar)
            VStack(alignment: .leading, spacing: 3) {
                Text(category.title).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                Text(category.sourceLabel + (showsCount && !category.isUtility ? " · \(category.memberCount) characters" : ""))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CategoryResetDefaultButton: View {
    let category: BrowseCategory
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                CategoryExemplarView(exemplar: category.defaultExemplar, size: 24)
                Text("Reset default").frame(maxWidth: .infinity, alignment: .leading)
            }
        }.accessibilityLabel("Reset default for \(category.title)")
            .accessibilityIdentifier("category-reset-" + category.id)
    }
}

extension BrowseCategory {
    var sourceLabel: String {
        switch source {
        case .curatedSet: return "Restored collection"
        case .legacyRanges: return "Restored collection"
        case .unichar: return "UniChar sample"
        case .block: return "Unicode block"
        case .utility(.recents): return "Pick history"
        case .utility(.frequent): return "Learning frequency"
        }
    }
}
