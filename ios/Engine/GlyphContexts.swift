import Foundation

/// Exact source occurrences lead; canonical variants keep their selected copy string.
extension GlyphSearch {
    public func contexts(for glyph: Glyph, origin: BrowseOrigin? = nil) -> [BrowseContextTarget] {
        var byCategory: [String: BrowseContextTarget] = [:]
        let explicit = rows("SELECT category,occurrence_id,position,symbol FROM browse_entries WHERE glyph_id=? ORDER BY category,position", [glyph.id])
        for row in explicit {
            guard let position = Int(row[2]) else { continue }
            let exact = row[3].utf8.elementsEqual(glyph.symbol.utf8)
            let candidate = BrowseContextTarget(categoryID: row[0], occurrenceID: row[1], position: position, glyph: glyph,
                                                match: exact ? .exactOccurrence : .canonicalVariant)
            if let old = byCategory[row[0]] {
                let preferred = origin?.categoryID == candidate.categoryID && origin?.occurrenceID == candidate.occurrenceID
                let wasPreferred = origin?.categoryID == old.categoryID && origin?.occurrenceID == old.occurrenceID
                if preferred || (!wasPreferred && exact && !isExact(old)) { byCategory[row[0]] = candidate }
            } else { byCategory[row[0]] = candidate }
        }
        if let orderText = rows("SELECT ord FROM glyphs WHERE id=?", [glyph.id]).first?.first, let order = Int(orderText) {
            for category in categories where category.membership == .sourceRule && belongs(glyph, to: category) {
                let rule = browseRule(category)
                let before: String
                var parameters = rule.parameters
                if category.id == "legacy:Music" {
                    let scalar = glyph.symbol.unicodeScalars.first?.value ?? 0
                    let rank = (0x2669...0x266F).contains(scalar) ? 0 : ((0x1D100...0x1D1FF).contains(scalar) ? 1 : 2)
                    let expression = "CASE WHEN unicode(g.symbol) BETWEEN 9833 AND 9839 THEN 0 WHEN unicode(g.symbol) BETWEEN 119040 AND 119295 THEN 1 ELSE 2 END"
                    before = "(\(expression) < ? OR (\(expression)=? AND g.ord<?))"
                    parameters += [.integer(rank), .integer(rank), .integer(order)]
                } else { before = "g.ord<?"; parameters.append(.integer(order)) }
                let position = Int(boundRows("SELECT count(*) FROM glyphs g WHERE (\(rule.predicate)) AND \(before)", parameters).first?.first ?? "") ?? 0
                let original = self.glyph(id: glyph.id)
                let exact = original?.symbol.utf8.elementsEqual(glyph.symbol.utf8) == true
                byCategory[category.id] = BrowseContextTarget(categoryID: category.id, occurrenceID: category.id + ":full:" + glyph.id,
                                                              position: position, glyph: glyph, match: exact ? .exactOccurrence : .canonicalVariant)
            }
        }
        let positions = Dictionary(uniqueKeysWithValues: categories.enumerated().map { ($0.element.id, $0.offset) })
        return byCategory.values.sorted { left, right in
            func rank(_ target: BrowseContextTarget) -> Int {
                if target.categoryID == origin?.categoryID && target.occurrenceID == origin?.occurrenceID { return 0 }
                if target.categoryID == origin?.categoryID { return 1 }
                if isExact(target), target.categoryID.hasPrefix("block:") { return 2 }
                if isExact(target) { return 3 }
                return 4
            }
            return rank(left) == rank(right) ? positions[left.categoryID, default: Int.max] < positions[right.categoryID, default: Int.max] : rank(left) < rank(right)
        }
    }

    private func isExact(_ target: BrowseContextTarget) -> Bool { if case .exactOccurrence = target.match { return true }; return false }
    private func belongs(_ glyph: Glyph, to category: BrowseCategory) -> Bool {
        switch category.source {
        case .curatedSet(let set): return glyph.set == set
        case .block(let block, _): return glyph.set == "Other Glyphs" && glyph.block == block
        case .legacyRanges(let ranges):
            guard let scalar = glyph.symbol.unicodeScalars.first?.value else { return false }
            return ranges.contains { $0.contains(scalar) }
        case .unichar, .utility: return false
        }
    }
}
