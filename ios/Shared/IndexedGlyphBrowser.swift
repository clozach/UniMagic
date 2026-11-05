import SwiftUI
import UIKit

struct IndexedGlyphBrowser: UIViewRepresentable {
    @ObservedObject var model: PickerModel
    let host: PickerHost
    let destination: (String) -> Void
    func makeCoordinator() -> AppBrowseCoordinator { AppBrowseCoordinator(self) }
    func makeUIView(context: Context) -> IndexedBrowserContainer {
        let container = IndexedBrowserContainer()
        let table = container.table
        table.dataSource = context.coordinator; table.delegate = context.coordinator
        table.separatorStyle = .none; table.sectionHeaderTopPadding = 0
        table.rowHeight = 52; table.estimatedRowHeight = 0
        table.estimatedSectionHeaderHeight = 0; table.estimatedSectionFooterHeight = 0
        table.keyboardDismissMode = .onDrag; table.accessibilityIdentifier = "glyph-results"
        table.register(BrowseSectionHeader.self, forHeaderFooterViewReuseIdentifier: "browse-header")
        if #available(iOS 26.0, *) { table.topEdgeEffect.isHidden = true; table.bottomEdgeEffect.isHidden = true }
        table.viewportChanged = { [weak coordinator = context.coordinator] in coordinator?.resize($0) }
        container.openChooser = { [weak coordinator = context.coordinator, weak container] in
            if let container { coordinator?.openChooser(container) }
        }
        return container
    }
    func updateUIView(_ container: IndexedBrowserContainer, context: Context) {
        context.coordinator.update(self, container: container)
    }
}

final class GlyphIndexTableView: UITableView {
    var viewportChanged: ((UITableView) -> Void)?
    private var lastSize: CGSize = .zero
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory { viewportChanged?(self) }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.size != lastSize { lastSize = bounds.size; viewportChanged?(self) }
    }
}
