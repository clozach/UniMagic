import SwiftUI

/// Search keeps a compact vertical result row; browsing uses a horizontal collection.
struct KeyboardGlyphGrid: View {
    @ObservedObject var model: PickerModel
    let host: PickerHost
    let destination: (String) -> Void
    @Environment(\.keyboardSearchMode) private var searchMode
    @State private var browseAnchor: KeyboardBrowseAnchor?
    var body: some View {
        if !model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            GeometryReader { geometry in
                let columns = max(1, Int((geometry.size.width - 16) / 56))
                ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(stride(from: 0, to: model.results.count, by: columns).map { $0 }, id: \.self) { start in
                            GlyphRow(model: model, items: model.results[start..<min(start + columns, model.results.count)].map(PickerGlyphItem.search), columns: columns, host: host, destination: destination)
                                .id("search-row-" + String(start))
                        }
                        if model.isLoading { ProgressView("Searching") }
                        else if model.results.isEmpty { Text("No matches").foregroundStyle(.secondary) }
                    }.padding(.horizontal, 8)
                }.modifier(KeyboardScrollEdges()).accessibilityIdentifier("glyph-results")
                    .onChange(of: model.searchNavigationTarget?.id) { _, _ in restoreSearch(proxy, columns: columns) }
                    .onChange(of: model.results.map(\.id)) { _, _ in restoreSearch(proxy, columns: columns) }
                    .onAppear { restoreSearch(proxy, columns: columns) }
                }
            }
        } else {
            VStack(spacing: 0) {
                if !searchMode {
                    HStack(spacing: 8) {
                        if let category = model.selectedCategory {
                            CategoryExemplarView(exemplar: category.exemplar, size: 18, width: 52).frame(height: 28).clipped()
                        } else { Color.clear.frame(width: 52, height: 28) }
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(model.selectedCategory?.title ?? "Characters").font(.caption).fixedSize().frame(minHeight: 28)
                        }.modifier(KeyboardScrollEdges()).id(model.selectedCategoryID)
                    }.frame(height: 28).accessibilityAddTraits(.isHeader).accessibilityIdentifier("keyboard-section-label")
                }
                if model.sections.isEmpty {
                    if model.isLoading { ProgressView("Loading characters").frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else { Text("No categories enabled. Use Search to find a character.").font(.caption).frame(maxWidth: .infinity, maxHeight: .infinity) }
                } else { KeyboardBrowseSections(model: model, host: host, destination: destination, anchor: $browseAnchor) }
            }
        }
    }
    private func restoreSearch(_ proxy: ScrollViewProxy, columns: Int) {
        guard !model.isLoading, let target = model.searchNavigationTarget,
              let position = model.results.firstIndex(where: { $0.id == target.glyphID }) else { return }
        DispatchQueue.main.async {
            proxy.scrollTo("search-row-" + String((position / columns) * columns), anchor: .top)
            model.acknowledgeSearchNavigation(target.id)
        }
    }
}

/// Keyboard text and symbols remain sharp at the viewport edges.
struct KeyboardScrollEdges: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.scrollEdgeEffectHidden(true, for: .all) }
        else { content }
    }
}
