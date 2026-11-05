import SwiftUI

struct KeyboardSectionLayout {
    struct Section: Identifiable { let id: String; let frame: CGRect; let count: Int }
    let sections: [Section]
    let rows: Int
    let size: CGSize
    let width: CGFloat
    var signature: String { sections.map { $0.id + ":" + String($0.count) }.joined(separator: "|") }
    init(sections: [PickerBrowseSection], size: CGSize) {
        let rowCount = max(1, Int((size.height + 4) / 52))
        self.size = size; rows = rowCount
        var x: CGFloat = 8
        self.sections = sections.map { section in
            let count = section.totalCount.value ?? ((section.items.last?.position ?? -1) + 1)
            let columns = max(1, (count + rowCount - 1) / rowCount)
            let width = count == 0 ? max(180, size.width - 16) : CGFloat(columns) * 56
            let frame = CGRect(x: x, y: 0, width: width, height: size.height)
            x += width + 16; return Section(id: section.id, frame: frame, count: count)
        }
        width = max(size.width, x - 8, (self.sections.last?.frame.minX ?? 8) + size.width - 8)
    }
    func visible(at offset: CGFloat) -> [Section] {
        let viewport = CGRect(x: offset - 56, y: 0, width: size.width + 112, height: size.height)
        return sections.filter { $0.frame.intersects(viewport) }
    }
    func positions(_ section: Section, offset: CGFloat) -> [Int] {
        guard section.count > 0 else { return [0] }
        let first = max(0, Int(floor((offset - 56 - section.frame.minX) / 56))) * rows
        let last = min(section.count, (max(0, Int(ceil((offset + size.width + 56 - section.frame.minX) / 56))) + 1) * rows)
        return first < last ? Array(first..<min(last, first + 300)) : []
    }
    func leading(at offset: CGFloat) -> KeyboardBrowseAnchor? {
        guard let section = sections.first(where: { $0.frame.maxX > offset + 8 }) ?? sections.last else { return nil }
        let column = max(0, Int(floor((offset + 8 - section.frame.minX) / 56)))
        return KeyboardBrowseAnchor(categoryID: section.id, position: min(max(0, section.count - 1), column * rows))
    }
    func offset(for anchor: KeyboardBrowseAnchor) -> CGFloat {
        guard let section = sections.first(where: { $0.id == anchor.categoryID }) else { return 0 }
        return min(max(0, width - size.width), max(0, section.frame.minX + CGFloat(anchor.position / rows) * 56))
    }
}
