import SwiftUI
import UIKit

/// UITableView owns vertical geometry; model windows are keyed by exact occurrence IDs.
@MainActor final class AppBrowseCoordinator: NSObject, UITableViewDataSource, UITableViewDelegate, UIPopoverPresentationControllerDelegate {
    var owner: IndexedGlyphBrowser
    var sections: [PickerBrowseSection] = []
    var results: [Glyph] = []
    var query = ""
    private var sectionsRevision = -1, searchRevision = -1
    private var geometry: [SectionGeometry] = []
    var visibleWorkPending = false
    private struct SectionGeometry: Equatable {
        let id: String
        let count: Int
        let exemplar: CategoryExemplar
    }
    var columns = 6
    var contentSizeCategory: UIContentSizeCategory?
    var restoring = false
    weak var container: IndexedBrowserContainer?
    private var chooser: UIViewController?
    var highlight: UIView?
    struct Anchor { let categoryID: String; let occurrenceID: String?; let position: Int; let rowOffset: CGFloat }
    init(_ owner: IndexedGlyphBrowser) { self.owner = owner }
    var searching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    func glyphRows(_ section: PickerBrowseSection) -> Int { max(1, (section.displayCount + columns - 1) / columns) }

    func update(_ next: IndexedGlyphBrowser, container: IndexedBrowserContainer) {
        self.container = container
        let table = container.table
        owner = next; container.update(category: next.model.selectedCategory)
        let model = next.model, oldQuery = query
        let changed = query != model.query || sectionsRevision != model.data.sectionsRevision || searchRevision != model.data.searchRevision
        if changed {
            let anchor = visibleAnchor(table)
            sectionsRevision = model.data.sectionsRevision; searchRevision = model.data.searchRevision
            query = model.query; sections = model.sections; results = searching ? model.results : []
            let nextGeometry = sections.map { SectionGeometry(id: $0.id, count: $0.displayCount, exemplar: $0.category.exemplar) }
            if searching || oldQuery != query || nextGeometry != geometry {
                restoring = true; table.reloadData(); table.layoutIfNeeded()
                if oldQuery != query { table.setContentOffset(CGPoint(x: 0, y: -table.adjustedContentInset.top), animated: false) }
                else if let anchor { restore(anchor, table: table) }
                restoring = false
            } else {
                // Page arrival updates glyphs inside existing cells. The table keeps
                // its content size and its native deceleration trajectory.
                for cell in table.visibleCells {
                    guard let path = table.indexPath(for: cell) else { continue }
                    if let row = cell as? BrowseGlyphRowCell { configure(row, at: path) }
                    else { configureStatus(cell, at: path) }
                }
            }
            geometry = nextGeometry
        }
        applyNavigation(table)
        scheduleVisibleWork(table)
    }
    func resize(_ table: UITableView) {
        let next = max(1, Int((table.bounds.width - 16) / 56))
        guard next != columns || contentSizeCategory != table.traitCollection.preferredContentSizeCategory else {
            reconcileVisibleSelection(table); return
        }
        contentSizeCategory = table.traitCollection.preferredContentSizeCategory
        let anchor = visibleAnchor(table); columns = next
        restoring = true; table.reloadData(); table.layoutIfNeeded()
        if let anchor { restore(anchor, table: table) }; restoring = false
        reconcileVisibleSelection(table)
    }
    func openChooser(_ container: IndexedBrowserContainer) {
        guard chooser == nil else { return }
        var responder: UIResponder? = container
        while responder != nil && !(responder is UIViewController) { responder = responder?.next }
        guard let presenter = responder as? UIViewController else { return }
        let popup = UIHostingController(rootView: BrowseCategoryChooser(model: owner.model, choose: { [weak self] id in
            guard let self else { return }
            self.container?.window?.endEditing(true)
            self.chooser?.view.endEditing(true)
            self.chooser?.dismiss(animated: !UIAccessibility.isReduceMotionEnabled) { [weak self] in
                self?.chooser = nil; self?.owner.model.selectCategory(id: id)
            }
        }, openSettings: { [weak self] in
            self?.chooser?.dismiss(animated: !UIAccessibility.isReduceMotionEnabled) { [weak self] in
                self?.chooser = nil; self?.owner.model.settings = true
            }
        }))
        popup.modalPresentationStyle = .popover
        popup.preferredContentSize = CGSize(width: min(360, max(280, container.bounds.width - 24)), height: min(460, max(220, container.bounds.height - 80)))
        if let popover = popup.popoverPresentationController {
            popover.sourceView = container.chooser; popover.sourceRect = container.chooser.bounds
            popover.permittedArrowDirections = .down; popover.delegate = self
        }
        chooser = popup; presenter.present(popup, animated: !UIAccessibility.isReduceMotionEnabled)
    }
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle { .none }
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { chooser = nil }
    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) { chooser = nil }
    func numberOfSections(in tableView: UITableView) -> Int { searching ? 1 : sections.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if searching { return max(1, (results.count + columns - 1) / columns) }
        return glyphRows(sections[section])
    }
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { searching ? max(36, UIFont.preferredFont(forTextStyle: .subheadline).lineHeight + 8) : BrowseSectionHeader.height }
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: "browse-header") as! BrowseSectionHeader
        let title = owner.model.isLoading ? "Searching…" : "\(results.count == 100 ? "Top 100" : String(results.count)) matches"
        header.configure(category: searching ? nil : sections[section].category, searchTitle: searching ? title : nil)
        return header
    }
    func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        if searching ? !results.isEmpty : sections[path.section].displayCount > 0 {
            let row = tableView.dequeueReusableCell(withIdentifier: "glyph-row") as? BrowseGlyphRowCell ?? BrowseGlyphRowCell(style: .default, reuseIdentifier: "glyph-row")
            row.selectionStyle = .none; row.backgroundColor = .systemBackground
            configure(row, at: path)
            return row
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "browse-status") ?? UITableViewCell(style: .default, reuseIdentifier: "browse-status")
        cell.selectionStyle = .none
        configureStatus(cell, at: path)
        return cell
    }

    private func configure(_ row: BrowseGlyphRowCell, at path: IndexPath) {
        let first = path.row * columns
        let items: [PickerGlyphItem?] = (first..<(first + columns)).map { position in
            if searching { return results.indices.contains(position) ? .search(results[position]) : nil }
            return sections[path.section].item(at: position).map(PickerGlyphItem.browse)
        }
        row.configure(items: items, columns: columns, inserts: owner.host.inserts, enabled: !searching || !owner.model.isLoading)
        row.pick = { [weak self] item in
            guard let self else { return }
            self.owner.model.picked(item, destination: self.owner.destination, feedback: self.owner.host.inserts ? "Inserted" : "Copied")
        }
        row.details = { [weak self] in self?.owner.model.openDetails($0) }
        row.accessoryView = nil
        if !searching, items.allSatisfy({ $0 == nil }) {
            let section = sections[path.section]
            let before = first < (section.items.first?.position ?? 0)
            if case .failed = before ? section.leadingLoad : section.load {
                let button = UIButton(type: .system)
                button.setTitle("Retry loading characters", for: .normal)
                button.sizeToFit()
                button.addAction(UIAction { [weak self] _ in
                    if before { self?.owner.model.loadPreviousPage(section.id) } else { self?.owner.model.loadNextPage(section.id) }
                }, for: .touchUpInside)
                row.accessoryView = button
            }
        }
    }

    private func configureStatus(_ cell: UITableViewCell, at path: IndexPath) {
        let section = searching ? nil : sections[path.section]
        cell.contentConfiguration = UIHostingConfiguration {
            if let section { self.status(section, before: false) }
            else if self.owner.model.isLoading { ProgressView("Searching") }
            else { Text("No matches").foregroundStyle(.secondary) }
        }.margins(.all, 0)
    }
    @ViewBuilder private func status(_ section: PickerBrowseSection, before: Bool) -> some View {
        switch before ? section.leadingLoad : section.load {
        case .more: Color.clear.accessibilityHidden(true)
        case .loading: ProgressView().accessibilityLabel(before ? "Loading earlier characters" : "Loading characters")
        case .failed:
            Button("Retry loading characters") {
                if before { self.owner.model.loadPreviousPage(section.id) } else { self.owner.model.loadNextPage(section.id) }
            }.accessibilityIdentifier("browse-retry-" + section.id)
        case .complete: Text(section.category.isUtility ? "Pick a character to add it here" : "No characters in this category").font(.caption).foregroundStyle(.secondary)
        }
    }
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt path: IndexPath) { scheduleVisibleWork(tableView) }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !restoring, let table = scrollView as? UITableView else { return }
        scheduleVisibleWork(table)
    }
}
