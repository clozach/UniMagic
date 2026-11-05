import SwiftUI

struct KeyboardBrowseAnchor: Equatable { let categoryID: String; let position: Int }
private struct KeyboardColumnID: Hashable { let categoryID: String; let column: Int }
private struct KeyboardLayoutKey: Equatable { let size: CGSize; let signature: String }
private enum KeyboardViewport {
    case starting
    case tracking(KeyboardLayoutKey, CGFloat)
    case restoring(KeyboardLayoutKey, CGFloat, UUID?)
    var offset: CGFloat { switch self { case .starting: return 0; case .tracking(_, let x), .restoring(_, let x, _): return x } }
    var key: KeyboardLayoutKey? { switch self { case .starting: return nil; case .tracking(let key, _), .restoring(let key, _, _): return key } }
}
private struct KeyboardOffsetPreference: PreferenceKey {
    static var defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = nextValue() ?? value }
}

struct KeyboardBrowseSections: View {
    @ObservedObject var model: PickerModel
    let host: PickerHost
    let destination: (String) -> Void
    @Binding var anchor: KeyboardBrowseAnchor?
    @State private var viewport = KeyboardViewport.starting
    @State private var observedOffset: CGFloat = 0
    @State private var highlight: String?
    var body: some View {
        GeometryReader { geometry in
            let layout = KeyboardSectionLayout(sections: model.sections, size: geometry.size)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    let visible = Set(layout.visible(at: viewport.offset).map(\.id))
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(layout.sections) { section in
                            if visible.contains(section.id), let data = model.sections.first(where: { $0.id == section.id }) {
                                sectionContent(data, section: section, layout: layout)
                            } else { Color.clear.frame(width: section.frame.width, height: geometry.size.height).accessibilityHidden(true) }
                        }
                    }.padding(.horizontal, 8).frame(width: layout.width, height: geometry.size.height, alignment: .topLeading)
                        .background(GeometryReader { bounds in
                            Color.clear.preference(key: KeyboardOffsetPreference.self, value: -bounds.frame(in: .named("keyboard-browse-viewport")).minX)
                        })
                }
                .coordinateSpace(name: "keyboard-browse-viewport").modifier(KeyboardScrollEdges())
                .accessibilityIdentifier("glyph-results").accessibilityLabel("Character browser").accessibilityValue(status(layout))
                .onPreferenceChange(KeyboardOffsetPreference.self) { if let value = $0 { observed(value, layout: layout) } }
                .onAppear { restore(layout, proxy: proxy) }
                .onChange(of: geometry.size) { _, _ in restore(layout, proxy: proxy) }
                .onChange(of: layout.signature) { _, _ in restore(layout, proxy: proxy) }
                .onChange(of: model.navigationTarget?.id) { _, _ in if model.navigationTarget != nil { restore(layout, proxy: proxy) } }
                .onChange(of: model.sections.map { $0.id + String(describing: $0.load) + String(describing: $0.leadingLoad) }) { _, _ in demand(layout) }
            }
        }
    }
    @ViewBuilder private func sectionContent(_ data: PickerBrowseSection, section: KeyboardSectionLayout.Section, layout: KeyboardSectionLayout) -> some View {
        if section.count == 0 {
            cell(data, item: nil, position: 0).frame(width: section.frame.width, height: layout.size.height)
                .id(KeyboardColumnID(categoryID: section.id, column: 0))
        } else {
            let columns = Array(Set(layout.positions(section, offset: viewport.offset).map { $0 / layout.rows })).sorted()
            let items = Dictionary(uniqueKeysWithValues: data.items.map { ($0.position, $0) })
            HStack(alignment: .top, spacing: 0) {
                Color.clear.frame(width: CGFloat(columns.first ?? 0) * 56).accessibilityHidden(true)
                ForEach(columns, id: \.self) { column in
                    VStack(spacing: 4) {
                        ForEach(0..<layout.rows, id: \.self) { row in
                            let position = column * layout.rows + row
                            if position < section.count { cell(data, item: items[position], position: position).frame(width: 52, height: 48) }
                            else { Color.clear.frame(width: 52, height: 48).accessibilityHidden(true) }
                        }
                    }.frame(width: 56, alignment: .leading).id(KeyboardColumnID(categoryID: section.id, column: column))
                }
                Color.clear.frame(width: max(0, section.frame.width - CGFloat((columns.last ?? -1) + 1) * 56)).accessibilityHidden(true)
            }.frame(width: section.frame.width, height: layout.size.height, alignment: .topLeading)
        }
    }
    @ViewBuilder private func cell(_ section: PickerBrowseSection, item: BrowseOccurrence?, position: Int) -> some View {
        if let item {
            GlyphRow(model: model, items: [.browse(item)], columns: 1, host: host, destination: destination)
                .background(item.id == highlight ? Color.accentColor.opacity(0.18) : Color(uiColor: .systemBackground))
        } else {
            let leading = position < (section.items.first?.position ?? 0)
            switch leading ? section.leadingLoad : section.load {
            case .loading: ProgressView()
            case .failed(let message, _):
                Button("Retry") { if leading { model.loadPreviousPage(section.id) } else { model.loadNextPage(section.id) } }
                    .font(.caption).accessibilityLabel("Couldn't load characters. Retry").accessibilityHint(message)
            case .complete:
                if section.items.isEmpty { Text(section.category.isRecent ? "Your picks appear here" : "No characters in this category").font(.caption).foregroundStyle(.secondary) }
                else { Color.clear.accessibilityHidden(true) }
            case .more: Color.clear.accessibilityHidden(true)
            }
        }
    }
    private func restore(_ layout: KeyboardSectionLayout, proxy: ScrollViewProxy) {
        guard layout.size.width > 0, layout.size.height > 0 else { return }
        let request = model.navigationTarget
        let desired: KeyboardBrowseAnchor
        if let request {
            switch request {
            case .section(_, let id): desired = KeyboardBrowseAnchor(categoryID: id, position: 0); highlight = nil
            case .occurrence(_, let item): desired = KeyboardBrowseAnchor(categoryID: item.categoryID, position: item.position); highlight = item.occurrenceID
            }
        } else if let anchor, layout.sections.contains(where: { $0.id == anchor.categoryID }) { desired = anchor }
        else { desired = KeyboardBrowseAnchor(categoryID: model.selectedCategoryID, position: 0) }
        guard let section = layout.sections.first(where: { $0.id == desired.categoryID }) else { return }
        let target = KeyboardBrowseAnchor(categoryID: desired.categoryID, position: min(max(0, section.count - 1), desired.position))
        let key = KeyboardLayoutKey(size: layout.size, signature: layout.signature), x = layout.offset(for: target)
        anchor = target; viewport = .restoring(key, x, request?.id)
        DispatchQueue.main.async {
            guard case .restoring(let current, let expected, let pending) = viewport, current == key, expected == x, pending == request?.id else { return }
            proxy.scrollTo(KeyboardColumnID(categoryID: target.categoryID, column: target.position / layout.rows), anchor: .leading)
            demand(layout)
            if abs(observedOffset - x) <= 1 { observed(observedOffset, layout: layout) }
        }
        if let selected = highlight { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if highlight == selected { highlight = nil } } }
    }
    private func observed(_ x: CGFloat, layout: KeyboardSectionLayout) {
        observedOffset = x
        let key = KeyboardLayoutKey(size: layout.size, signature: layout.signature)
        guard viewport.key == key else { return }
        if case .restoring(_, let expected, let request) = viewport {
            guard abs(x - expected) <= 1 else { return }
            viewport = .tracking(key, x)
            if let request { model.acknowledgeNavigation(request) }
        } else { viewport = .tracking(key, x) }
        report(layout); demand(layout)
    }
    private func report(_ layout: KeyboardSectionLayout) {
        guard let leading = layout.leading(at: viewport.offset), anchor != leading || model.selectedCategoryID != leading.categoryID else { return }
        anchor = leading
        let item = model.sections.first { $0.id == leading.categoryID }?.items.first { $0.position >= leading.position }
        model.visibleSectionChanged(leading.categoryID, leadingOccurrenceID: item?.id)
    }
    private func demand(_ layout: KeyboardSectionLayout) {
        for visible in layout.visible(at: viewport.offset) {
            guard let section = model.sections.first(where: { $0.id == visible.id }) else { continue }
            if section.items.isEmpty { if case .more = section.load { model.ensureSectionLoaded(section.id) }; continue }
            let positions = layout.positions(visible, offset: viewport.offset)
            if let first = positions.first, first <= (section.items.first?.position ?? 0) + layout.rows * 2, case .more = section.leadingLoad { model.loadPreviousPage(section.id) }
            if let last = positions.last, last >= (section.items.last?.position ?? 0) - layout.rows * 2, case .more = section.load { model.loadNextPage(section.id) }
        }
    }
    private func status(_ layout: KeyboardSectionLayout) -> String {
        guard let leading = layout.leading(at: viewport.offset), let section = model.sections.first(where: { $0.id == leading.categoryID }) else { return "" }
        if let count = section.totalCount.value, count > 0 { return "\(section.category.title), character \(leading.position + 1) of \(count)" }
        return section.category.title
    }
}
