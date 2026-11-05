import SwiftUI
import UIKit

/// UITableView owns vertical geometry; model windows are keyed by exact occurrence IDs.
@MainActor final class AppBrowseCoordinator: NSObject, UITableViewDataSource, UITableViewDelegate, UIPopoverPresentationControllerDelegate {
    var owner: IndexedGlyphBrowser
    var sections: [PickerBrowseSection] = []
    var results: [Glyph] = []
    var query = "", content = ""
    var columns = 6
    var contentSizeCategory: UIContentSizeCategory?
    var restoring = false
    weak var container: IndexedBrowserContainer?
    private var chooser: UIViewController?
    var highlight: UIView?
    struct Anchor { let categoryID: String; let occurrenceID: String?; let rowOffset: CGFloat }
    init(_ owner: IndexedGlyphBrowser) { self.owner = owner }
    var searching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    func leading(_ section: PickerBrowseSection) -> Int {
        if case .complete = section.leadingLoad { return 0 }; return 1
    }
    func glyphRows(_ section: PickerBrowseSection) -> Int { (section.items.count + columns - 1) / columns }
    func update(_ next: IndexedGlyphBrowser, container: IndexedBrowserContainer) {
        self.container = container
        let table = container.table
        let anchor = visibleAnchor(table)
        let oldQuery = query
        owner = next; container.update(category: next.model.selectedCategory)
        let fingerprint = next.model.query + "|" + String(next.model.isLoading)
            + "|" + next.model.results.map { $0.id + $0.symbol }.joined(separator: ",")
            + "|" + next.model.sections.map { $0.id + String(describing: $0.category.exemplar) + $0.items.map(\.id).joined(separator: ",") + String(describing: $0.load) + String(describing: $0.leadingLoad) }.joined(separator: ";")
        if content != fingerprint {
            content = fingerprint; query = next.model.query; sections = next.model.sections; results = next.model.results
            restoring = true; table.reloadData(); table.layoutIfNeeded()
            if oldQuery != query { table.setContentOffset(CGPoint(x: 0, y: -table.adjustedContentInset.top), animated: false) }
            else if let anchor { restore(anchor, table: table) }
            restoring = false
        }
        applyNavigation(table)
        reconcileVisibleSelection(table)
        requestVisiblePages(table)
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
        let item = sections[section], rows = glyphRows(item)
        if case .complete = item.load { return leading(item) + max(1, rows) }
        return leading(item) + rows + 1
    }
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { searching ? max(36, UIFont.preferredFont(forTextStyle: .subheadline).lineHeight + 8) : BrowseSectionHeader.height }
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: "browse-header") as! BrowseSectionHeader
        let title = owner.model.isLoading ? "Searching…" : "\(results.count == 100 ? "Top 100" : String(results.count)) matches"
        header.configure(category: searching ? nil : sections[section].category, searchTitle: searching ? title : nil)
        return header
    }
    func tableView(_ tableView: UITableView, cellForRowAt path: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "glyph-row") ?? UITableViewCell(style: .default, reuseIdentifier: "glyph-row")
        cell.selectionStyle = .none; cell.backgroundColor = .systemBackground
        let offset = searching ? 0 : leading(sections[path.section])
        let start = (path.row - offset) * columns
        let count = searching ? results.count : sections[path.section].items.count
        if start >= 0 && start < count {
            let end = min(start + columns, count)
            let items = searching ? Array(results[start..<end]).map(PickerGlyphItem.search) : Array(sections[path.section].items[start..<end]).map(PickerGlyphItem.browse)
            cell.contentConfiguration = UIHostingConfiguration {
                GlyphRow(model: self.owner.model, items: items, columns: self.columns, host: self.owner.host, destination: self.owner.destination)
                    .padding(.horizontal, 8)
            }.margins(.all, 0)
        } else {
            cell.contentConfiguration = UIHostingConfiguration {
                if self.searching {
                    if self.owner.model.isLoading { ProgressView("Searching") } else { Text("No matches").foregroundStyle(.secondary) }
                } else {
                    let section = self.sections[path.section]
                    self.status(section, before: start < 0)
                }
            }.margins(.all, 0)
        }
        return cell
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
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt path: IndexPath) { requestVisiblePages(tableView) }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !restoring, let table = scrollView as? UITableView else { return }
        updateVisibleSection(table); requestVisiblePages(table)
    }
}
