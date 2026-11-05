import SwiftUI

/// Catalogue order stays fixed; only this thumb-oriented presentation is reversed.
struct BrowseCategoryChooser: View {
    @ObservedObject var model: PickerModel
    let choose: (String) -> Void
    let openSettings: () -> Void
    @State private var filter = ""
    private var categories: [BrowseCategory] {
        let enabled = model.enabledCategories
        let ordered = Array(enabled.filter(\.isUtility).reversed()) + Array(enabled.filter { !$0.isUtility }.reversed())
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty ? ordered : ordered.filter {
            $0.title.localizedStandardContains(query) || $0.sourceLabel.localizedStandardContains(query)
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(categories) { category in
                            Button { choose(category.id) } label: {
                                HStack(spacing: 4) {
                                    CategoryLabelView(category: category)
                                    Image(systemName: "checkmark").font(.caption.weight(.semibold))
                                        .opacity(category.id == model.selectedCategoryID ? 1 : 0).frame(width: 16).accessibilityHidden(true)
                                }.padding(.horizontal, 12).padding(.vertical, 8).contentShape(Rectangle())
                            }.buttonStyle(.plain).id(category.id)
                                .accessibilityIdentifier("browse-" + category.id)
                                .accessibilityAddTraits(category.id == model.selectedCategoryID ? .isSelected : [])
                        }
                        if categories.isEmpty {
                            Text("No enabled categories match").foregroundStyle(.secondary).padding()
                        }
                    }
                }.accessibilityIdentifier("browse-category-list")
                    .defaultScrollAnchor(filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .bottom : .top)
                    .onChange(of: filter) { _, _ in
                        if filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            if let last = categories.last { reader.scrollTo(last.id, anchor: .bottom) }
                        } else if let first = categories.first { reader.scrollTo(first.id, anchor: .top) }
                    }
            }
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find category", text: $filter).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("browse-category-search")
                Button { filter = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 32, height: 36) }
                    .opacity(filter.isEmpty ? 0 : 1).disabled(filter.isEmpty).accessibilityHidden(filter.isEmpty)
                    .accessibilityLabel("Clear category search")
            }.padding(.horizontal, 12).frame(minHeight: 48)
            if model.enabledCategories.isEmpty {
                Button("Category settings", action: openSettings).frame(minHeight: 44)
                    .accessibilityIdentifier("browse-empty-settings")
            }
        }.background(Color(uiColor: .secondarySystemBackground))
    }
}
