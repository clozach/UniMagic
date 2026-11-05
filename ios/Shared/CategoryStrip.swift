import SwiftUI

/// Icon-only navigation uses enabled stable IDs; selection never recenters an
/// already visible button underneath the user's finger.
struct CategoryStrip: View {
    @ObservedObject var model: PickerModel
    var onSelection: () -> Void = {}
    @State private var frames: [String: CGRect] = [:]
    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 2) {
                        ForEach(model.enabledCategories) { category in
                            Button { model.selectCategory(id: category.id); onSelection() } label: {
                                CategoryExemplarView(exemplar: category.exemplar, size: 25, width: 44)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                                    .background(model.query.isEmpty && model.selectedCategoryID == category.id ? Color.primary.opacity(0.10) : Color(uiColor: .systemBackground), in: Circle())
                            }
                            .buttonStyle(.plain).id(category.id)
                            .accessibilityLabel(category.title).accessibilityIdentifier("category-" + category.id)
                            .accessibilityAddTraits(model.query.isEmpty && model.selectedCategoryID == category.id ? .isSelected : [])
                            .background(GeometryReader { bounds in
                                Color.clear.preference(key: CategoryStripFrames.self, value: [category.id: bounds.frame(in: .named("category-strip-viewport"))])
                            })
                        }
                    }.padding(.horizontal, 4)
                }
                .coordinateSpace(name: "category-strip-viewport").modifier(KeyboardScrollEdges())
                .onPreferenceChange(CategoryStripFrames.self) { frames = $0 }
                .onChange(of: model.selectedCategoryID) { _, id in reveal(id, proxy: proxy, width: geometry.size.width) }
                .onAppear { proxy.scrollTo(model.selectedCategoryID, anchor: .leading) }
            }
        }.frame(height: 44).accessibilityIdentifier("category-strip")
    }
    private func reveal(_ id: String, proxy: ScrollViewProxy, width: CGFloat) {
        if let frame = frames[id] {
            if frame.minX >= 0 && frame.maxX <= width { return }
            proxy.scrollTo(id, anchor: frame.minX < 0 ? .leading : .trailing)
        } else {
            let target = model.enabledCategories.firstIndex { $0.id == id } ?? 0
            let first = model.enabledCategories.firstIndex { frames[$0.id]?.maxX ?? 0 > 0 } ?? 0
            proxy.scrollTo(id, anchor: target < first ? .leading : .trailing)
        }
    }
}

private struct CategoryStripFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
