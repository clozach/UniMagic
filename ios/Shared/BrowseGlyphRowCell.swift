import UIKit

/// UIKit recycles one button for each column instead of creating a SwiftUI host
/// for every row that crosses the viewport during a fling.
final class BrowseGlyphRowCell: UITableViewCell {
    private var tiles: [UIButton] = []
    private var items: [PickerGlyphItem?] = []
    var pick: ((PickerGlyphItem) -> Void)?
    var details: ((PickerGlyphItem) -> Void)?

    func configure(items: [PickerGlyphItem?], columns: Int, inserts: Bool, enabled: Bool) {
        self.items = items
        if tiles.count != columns {
            for tile in tiles { tile.removeFromSuperview() }
            tiles = (0..<columns).map { index in
                let tile = UIButton(type: .custom)
                tile.tag = index
                tile.titleLabel?.adjustsFontSizeToFitWidth = true
                tile.titleLabel?.minimumScaleFactor = 0.15
                tile.setTitleColor(.label, for: .normal)
                tile.addTarget(self, action: #selector(picked(_:)), for: .touchUpInside)
                tile.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(held(_:))))
                tile.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Details") { [weak self] _ in
                    guard let self, let item = self.item(index) else { return false }
                    self.details?(item); return true
                }]
                contentView.addSubview(tile)
                return tile
            }
            setNeedsLayout()
        }
        for (index, tile) in tiles.enumerated() {
            guard let item = item(index) else { tile.isHidden = true; continue }
            tile.isHidden = false; tile.isEnabled = enabled
            let glyph = item.glyph, label = GlyphDisplay.label(glyph)
            tile.setTitle(label, for: .normal)
            tile.titleLabel?.font = label == glyph.symbol || label.hasPrefix("◌") ? .systemFont(ofSize: 30) : .preferredFont(forTextStyle: .caption1)
            tile.accessibilityLabel = glyph.name
            tile.accessibilityHint = inserts ? "Inserts character" : "Copies character"
            tile.accessibilityIdentifier = "glyph-" + glyph.id
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard !tiles.isEmpty else { return }
        let width = (contentView.bounds.width - 16 - CGFloat(tiles.count - 1) * 4) / CGFloat(tiles.count)
        for (index, tile) in tiles.enumerated() {
            tile.frame = CGRect(x: 8 + CGFloat(index) * (width + 4), y: 0, width: max(0, width), height: contentView.bounds.height)
        }
    }
    private func item(_ index: Int) -> PickerGlyphItem? { items.indices.contains(index) ? items[index] : nil }
    @objc private func picked(_ tile: UIButton) { if let item = item(tile.tag) { pick?(item) } }
    @objc private func held(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began, let tile = recognizer.view as? UIButton, let item = item(tile.tag) else { return }
        details?(item)
    }
}
