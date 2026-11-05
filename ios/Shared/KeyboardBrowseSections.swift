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
private enum KeyboardScrollSample: Equatable {
    case column(Int)
    case arrived(CGFloat)
    var offset: CGFloat { switch self { case .column(let column): return CGFloat(column) * 28; case .arrived(let x): return x } }
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
            let sections = model.sections
            let layout = KeyboardSectionLayout(sections: sections, size: geometry.size)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    let visible = layout.visible(at: viewport.offset)
                    HStack(alignment: .top, spacing: 0) {
                        Color.clear.frame(width: visible.first?.frame.minX ?? 0).accessibilityHidden(true)
                        ForEach(visible) { section in
                            sectionContent(sections[section.index], section: section, layout: layout)
                                .padding(.trailing, 16)
                        }
                    }.frame(width: layout.width, height: geometry.size.height, alignment: .topLeading)
                }
                .modifier(KeyboardScrollEdges())
                .onScrollGeometryChange(for: KeyboardScrollSample.self) { geometry in
                    let x = geometry.contentOffset.x + geometry.contentInsets.leading
                    if case .restoring(_, let expected, _) = viewport, abs(x - expected) <= 1 { return .arrived(x) }
                    return .column(Int(floor(x / 28)))
                } action: { _, sample in observed(sample.offset, layout: layout) }
                .accessibilityIdentifier("glyph-results").accessibilityLabel("Character browser").accessibilityValue(status(layout))
                .onAppear { restore(layout, proxy: proxy) }
                .onChange(of: geometry.size) { _, _ in restore(layout, proxy: proxy) }
                .onChange(of: layout.signature) { _, _ in restore(layout, proxy: proxy) }
                .onChange(of: model.navigationTarget?.id) { _, _ in if model.navigationTarget != nil { restore(layout, proxy: proxy) } }
                .onChange(of: model.data.sectionsRevision) { _, _ in demand(layout) }
            }
        }
    }
    @ViewBuilder private func sectionContent(_ data: PickerBrowseSection, section: KeyboardSectionLayout.Section, layout: KeyboardSectionLayout) -> some View {
        if section.count == 0 {
            cell(data, item: nil, position: 0).frame(width: section.frame.width, height: layout.size.height)
                .id(KeyboardColumnID(categoryID: section.id, column: 0))
        } else {
            let columns = Array(Set(layout.positions(section, offset: viewport.offset).map { $0 / layout.rows })).sorted()

            HStack(alignment: .top, spacing: 0) {
                Color.clear.frame(width: CGFloat(columns.first ?? 0) * 56).accessibilityHidden(true)
                ForEach(columns, id: \.self) { column in
                    VStack(spacing: 4) {
                        ForEach(0..<layout.rows, id: \.self) { row in
                            let position = column * layout.rows + row
                            if position < section.count { cell(data, item: data.item(at: position), position: position).frame(width: 52, height: 48) }
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
        } else if x != viewport.offset { viewport = .tracking(key, x) } else { return }
        report(layout); demand(layout)
    }
    private func report(_ layout: KeyboardSectionLayout) {
        guard let leading = layout.leading(at: viewport.offset), anchor != leading || model.selectedCategoryID != leading.categoryID else { return }
        anchor = leading
        let item = model.sections.first { $0.id == leading.categoryID }?.items.first { $0.position >= leading.position }
        model.visibleSectionChanged(leading.categoryID, leadingOccurrenceID: item?.id)
    }
    private func demand(_ layout: KeyboardSectionLayout) {
        let visibleSections = layout.visible(at: viewport.offset)
        model.visibleCategoryIDs = Set(visibleSections.map(\.id))
        for visible in visibleSections {
            let positions = layout.positions(visible, offset: viewport.offset)
            if let first = positions.first, let last = positions.last { model.demandVisible(visible.id, positions: first...last) }
        }
    }
    private func status(_ layout: KeyboardSectionLayout) -> String {
        guard let leading = layout.leading(at: viewport.offset), let section = model.sections.first(where: { $0.id == leading.categoryID }) else { return "" }
        if let count = section.totalCount.value, count > 0 { return "\(section.category.title), character \(leading.position + 1) of \(count)" }
        return section.category.title
    }
}
