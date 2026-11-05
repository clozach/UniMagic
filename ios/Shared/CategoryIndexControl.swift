import SwiftUI
import UIKit

/// The closed control has one reserved footprint for every exemplar and state.
final class IndexedBrowserContainer: UIView {
    let table = GlyphIndexTableView(frame: .zero, style: .plain)
    let chooser = UIButton(type: .system)
    var openChooser: (() -> Void)?
    private var exemplar: CategoryExemplar?
    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(table); addSubview(chooser)
        chooser.accessibilityIdentifier = "browse-category"
        chooser.accessibilityHint = "Opens the category chooser"
        chooser.backgroundColor = .secondarySystemBackground
        chooser.layer.cornerRadius = 26
        chooser.layer.shadowColor = UIColor.black.cgColor
        chooser.layer.shadowOpacity = 0.18; chooser.layer.shadowRadius = 8
        chooser.layer.shadowOffset = CGSize(width: 0, height: 2)
        chooser.titleLabel?.numberOfLines = 1
        chooser.titleLabel?.adjustsFontSizeToFitWidth = true
        chooser.titleLabel?.minimumScaleFactor = 0.2
        chooser.addTarget(self, action: #selector(pressed), for: .touchUpInside)
        table.contentInset.bottom = 80
        table.verticalScrollIndicatorInsets.bottom = 80
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func pressed() { window?.endEditing(true); openChooser?() }
    func update(category: BrowseCategory?) {
        chooser.accessibilityLabel = category.map { "Category: " + $0.title } ?? "Choose category"
        let next = category?.exemplar
        guard exemplar != next else { return }
        exemplar = next
        let font: UIFont, display: String
        if case .customFont = next { font = .systemFont(ofSize: 28); display = "" }
        else {
            display = GlyphDisplay.label(symbol: next?.symbol ?? "")
            font = display.hasPrefix("U+") ? .monospacedSystemFont(ofSize: 12, weight: .medium) : .systemFont(ofSize: 28)
        }
        chooser.accessibilityValue = display != next?.symbol ? display : nil
        if case .customFont(let symbol) = next {
            chooser.setImage(UIImage(systemName: CategoryIcon.systemName(for: symbol), withConfiguration: UIImage.SymbolConfiguration(pointSize: 28)), for: .normal)
        } else { chooser.setImage(next == nil ? UIImage(systemName: "line.3.horizontal.decrease") : nil, for: .normal) }
        let title = NSAttributedString(string: display, attributes: [.font: font, .foregroundColor: UIColor.label])
        let update = { self.chooser.setAttributedTitle(title, for: .normal) }
        if window != nil && !UIAccessibility.isReduceMotionEnabled {
            UIView.transition(with: chooser, duration: 0.18, options: [.transitionCrossDissolve, .allowUserInteraction], animations: update)
        } else { update() }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        table.frame = bounds
        chooser.frame = CGRect(x: (bounds.width - 64) / 2, y: max(0, bounds.height - safeAreaInsets.bottom - 64), width: 64, height: 52)
    }
}

/// Dedicated content paints readable glyphs and labels in ordinary and pinned states.
final class BrowseSectionHeader: UITableViewHeaderFooterView {
    static var height: CGFloat { max(46, UIFont.preferredFont(forTextStyle: .subheadline).lineHeight + UIFont.preferredFont(forTextStyle: .caption2).lineHeight + 8) }
    let symbol = UILabel(), title = UILabel(), source = UILabel()
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        backgroundView = UIView()
        backgroundView?.backgroundColor = .secondarySystemBackground
        contentView.backgroundColor = .secondarySystemBackground
        symbol.textAlignment = .center; symbol.adjustsFontSizeToFitWidth = true; symbol.minimumScaleFactor = 0.2
        title.font = .preferredFont(forTextStyle: .subheadline)
        source.font = .preferredFont(forTextStyle: .caption2)
        title.adjustsFontForContentSizeCategory = true; source.adjustsFontForContentSizeCategory = true
        title.textColor = .label; symbol.textColor = .label; source.textColor = .secondaryLabel
        [symbol, title, source].forEach { contentView.addSubview($0) }
        isAccessibilityElement = true; accessibilityTraits = .header
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(category: BrowseCategory?, searchTitle: String?) {
        if let category {
            if case .customFont(let legacy) = category.exemplar {
                let attachment = NSTextAttachment()
                attachment.image = UIImage(systemName: CategoryIcon.systemName(for: legacy), withConfiguration: UIImage.SymbolConfiguration(pointSize: 22))?.withTintColor(.label)
                attachment.bounds = CGRect(x: 0, y: -3, width: 26, height: 26)
                symbol.attributedText = NSAttributedString(attachment: attachment)
            }
            else {
                symbol.attributedText = nil
                let display = GlyphDisplay.label(symbol: category.symbol)
                symbol.text = display
                symbol.font = display.hasPrefix("U+") ? .monospacedSystemFont(ofSize: 11, weight: .medium) : .systemFont(ofSize: 22)
            }
            title.text = category.title; source.text = category.sourceLabel
            accessibilityLabel = category.title + ", " + category.sourceLabel
            accessibilityIdentifier = "browse-header-" + category.id
        } else {
            symbol.text = nil; title.text = searchTitle; source.text = nil
            accessibilityLabel = searchTitle; accessibilityIdentifier = "browse-search-header"
        }
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        symbol.frame = CGRect(x: 8, y: 0, width: 52, height: bounds.height)
        let x: CGFloat = symbol.text == nil && symbol.attributedText == nil ? 12 : 70
        let titleHeight = title.font.lineHeight
        title.frame = CGRect(x: x, y: source.text == nil ? (bounds.height - titleHeight) / 2 : 4, width: max(0, bounds.width - x - 12), height: titleHeight)
        source.frame = CGRect(x: x, y: titleHeight + 4, width: max(0, bounds.width - x - 12), height: source.font.lineHeight)
    }
}
