import UIKit

/// Stable viewport anchors survive paging, prepending, trimming and context returns.
extension AppBrowseCoordinator {
    func reconcileVisibleSelection(_ table: UITableView) {
        guard !restoring, !searching, owner.model.navigationTarget == nil,
              let anchor = visibleAnchor(table), owner.model.selectedCategoryID != anchor.categoryID else { return }
        updateVisibleSection(table)
    }
    func requestVisiblePages(_ table: UITableView) {
        guard !searching, !restoring else { return }
        let paths = table.indexPathsForVisibleRows ?? []
        let requests = paths.compactMap { path -> (String, Bool)? in
            guard sections.indices.contains(path.section) else { return nil }
            let section = sections[path.section]
            let row = path.row - leading(section)
            if row <= 1, case .more = section.leadingLoad { return (section.id, true) }
            if row >= glyphRows(section) - 2, case .more = section.load { return (section.id, false) }
            return nil
        }
        guard !requests.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.searching else { return }
            for (id, before) in requests {
                if before { self.owner.model.loadPreviousPage(id) } else { self.owner.model.loadNextPage(id) }
            }
        }
    }
    func updateVisibleSection(_ table: UITableView) {
        guard let anchor = visibleAnchor(table), !searching else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.owner.model.navigationTarget == nil, !self.searching,
                  self.visibleAnchor(table)?.categoryID == anchor.categoryID else { return }
            self.owner.model.visibleSectionChanged(anchor.categoryID, leadingOccurrenceID: anchor.occurrenceID)
        }
    }
    func visibleAnchor(_ table: UITableView) -> Anchor? {
        guard !searching, let path = table.indexPathsForVisibleRows?.sorted().first, sections.indices.contains(path.section) else { return nil }
        let section = sections[path.section]
        let index = max(0, path.row - leading(section)) * columns
        let id = section.items.indices.contains(index) ? section.items[index].id : nil
        return Anchor(categoryID: section.id, occurrenceID: id, rowOffset: table.rectForRow(at: path).minY - table.contentOffset.y)
    }
    func restore(_ anchor: Anchor, table: UITableView) {
        guard let section = sections.firstIndex(where: { $0.id == anchor.categoryID }) else { return }
        let items = sections[section].items
        let row = anchor.occurrenceID.flatMap { id in items.firstIndex(where: { $0.id == id }) }.map { $0 / columns + leading(sections[section]) } ?? 0
        setOffset(table.rectForRow(at: IndexPath(row: row, section: section)).minY - anchor.rowOffset, table: table)
    }
    func setOffset(_ value: CGFloat, table: UITableView) {
        let bottom = max(-table.adjustedContentInset.top, table.contentSize.height - table.bounds.height + table.adjustedContentInset.bottom)
        table.setContentOffset(CGPoint(x: 0, y: min(bottom, max(-table.adjustedContentInset.top, value))), animated: false)
    }
    func applyNavigation(_ table: UITableView) {
        if searching, let target = owner.model.searchNavigationTarget, let index = results.firstIndex(where: { $0.id == target.glyphID }) {
            let path = IndexPath(row: index / columns, section: 0)
            table.scrollToRow(at: path, at: .middle, animated: false)
            flash(path: path, column: index % columns, table: table)
            DispatchQueue.main.async { [weak self] in self?.owner.model.acknowledgeSearchNavigation(target.id) }
        } else if !searching, let request = owner.model.navigationTarget, let section = sections.firstIndex(where: { $0.id == request.categoryID }) {
            restoring = true
            switch request {
            case .section:
                setOffset(table.rectForHeader(inSection: section).minY - table.adjustedContentInset.top, table: table)
            case .occurrence(_, let target):
                guard let index = sections[section].items.firstIndex(where: { $0.id == target.occurrenceID }) else { restoring = false; return }
                let path = IndexPath(row: index / columns + leading(sections[section]), section: section)
                table.scrollToRow(at: path, at: .middle, animated: false)
                flash(path: path, column: index % columns, table: table)
            }
            restoring = false
            DispatchQueue.main.async { [weak self] in self?.owner.model.acknowledgeNavigation(request.id) }
        }
    }
    func flash(path: IndexPath, column: Int, table: UITableView) {
        highlight?.removeFromSuperview()
        let row = table.rectForRow(at: path), width = (row.width - 16 - CGFloat(columns - 1) * 4) / CGFloat(columns)
        let view = UIView(frame: CGRect(x: 8 + CGFloat(column) * (width + 4), y: row.minY + 2, width: width, height: row.height - 4))
        view.isUserInteractionEnabled = false; view.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
        view.layer.borderColor = UIColor.systemBlue.cgColor; view.layer.borderWidth = 2; view.layer.cornerRadius = 8
        table.addSubview(view); highlight = view
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.3, delay: 1, options: []) { view.alpha = 0 } completion: { _ in view.removeFromSuperview() }
    }
}
