import UIKit

/// Stable viewport anchors survive paging, prepending, trimming and context returns.
extension AppBrowseCoordinator {
    func reconcileVisibleSelection(_ table: UITableView) {
        scheduleVisibleWork(table)
    }
    func scheduleVisibleWork(_ table: UITableView) {
        guard !searching, !restoring, !visibleWorkPending else { return }
        visibleWorkPending = true
        DispatchQueue.main.async { [weak self, weak table] in
            guard let self, let table else { return }
            self.visibleWorkPending = false
            guard !self.searching, !self.restoring, self.owner.model.navigationTarget == nil else { return }
            let paths = table.indexPathsForVisibleRows ?? []
            if let anchor = self.visibleAnchor(table) {
                self.owner.model.visibleSectionChanged(anchor.categoryID, leadingOccurrenceID: anchor.occurrenceID)
            }
            let grouped = Dictionary(grouping: paths, by: { $0.section })
            self.owner.model.visibleCategoryIDs = Set(grouped.keys.compactMap { self.sections.indices.contains($0) ? self.sections[$0].id : nil })
            for (index, rows) in grouped {
                guard self.sections.indices.contains(index), let first = rows.map({ $0.row }).min(),
                      let last = rows.map({ $0.row }).max() else { continue }
                self.owner.model.demandVisible(self.sections[index].id, positions: (first * self.columns)...((last + 1) * self.columns - 1))
            }
        }
    }
    func visibleAnchor(_ table: UITableView) -> Anchor? {
        guard !searching, let path = table.indexPathsForVisibleRows?.sorted().first, sections.indices.contains(path.section) else { return nil }
        let section = sections[path.section]
        let index = path.row * columns
        let id = section.item(at: index)?.id
        return Anchor(categoryID: section.id, occurrenceID: id, position: index, rowOffset: table.rectForRow(at: path).minY - table.contentOffset.y)
    }
    func restore(_ anchor: Anchor, table: UITableView) {
        guard let section = sections.firstIndex(where: { $0.id == anchor.categoryID }) else { return }
        let items = sections[section].items
        let position = anchor.occurrenceID.flatMap { id in items.first(where: { $0.id == id })?.position } ?? anchor.position
        let row = min(glyphRows(sections[section]) - 1, position / columns)
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
                guard let index = sections[section].items.first(where: { $0.id == target.occurrenceID })?.position else { restoring = false; return }
                let path = IndexPath(row: index / columns, section: section)
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
