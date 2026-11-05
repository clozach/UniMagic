import Foundation

/// Bounded, occurrence-preserving pages over normalized membership and corpus rules.
extension GlyphSearch {
    public func browsePage(category: BrowseCategory, usage: [UsageEntry] = [], offset: Int = 0, limit: Int = 100) -> BrowsePage {
        let size = max(1, min(limit, 100)), start = max(0, offset)
        if case .utility(let utility) = category.source {
            guard utility == .frequent else { return BrowsePage(items: [], nextCursor: nil, totalCount: .unknown) }
            let sorted = usage.filter { $0.count > 0 }.sorted { $0.count == $1.count ? $0.hexseq < $1.hexseq : $0.count > $1.count }
            let items = sorted.dropFirst(start).prefix(size).enumerated().map { position, entry in
                let value = historyGlyph(id: entry.hexseq, symbol: entry.symbol)
                return BrowseOccurrence(id: category.id + ":usage:" + String(start + position) + ":" + entry.hexseq, categoryID: category.id, position: start + position, glyph: value)
            }
            return BrowsePage(items: items, nextCursor: sorted.count > start + size ? .offset(start + size) : nil, startOffset: start, totalCount: .known(sorted.count))
        }
        if category.membership == .explicit { return normalizedPage(table: "browse_entries", category: category, start: start, size: size) }
        let rule = browseRule(category)
        let fetched = boundRows("SELECT g.id,g.payload FROM glyphs g WHERE \(rule.predicate) ORDER BY \(rule.order) LIMIT ? OFFSET ?", rule.parameters + [.integer(size + 1), .integer(start)])
        let items = fetched.prefix(size).enumerated().compactMap { position, row -> BrowseOccurrence? in
            guard let glyph = decode(row[1]) else { return nil }
            return BrowseOccurrence(id: category.id + ":full:" + glyph.id, categoryID: category.id, position: start + position, glyph: glyph)
        }
        return BrowsePage(items: items, nextCursor: fetched.count > size ? .offset(start + size) : nil, startOffset: start, totalCount: .known(category.memberCount))
    }

    public func browseSamples(category: BrowseCategory, offset: Int = 0, limit: Int = 6) -> BrowsePage {
        normalizedPage(table: "browse_samples", category: category, start: max(0, offset), size: max(1, min(limit, 100)))
    }

    private func normalizedPage(table: String, category: BrowseCategory, start: Int, size: Int) -> BrowsePage {
        let fetched = boundRows("SELECT e.position,e.occurrence_id,g.payload,e.symbol,e.name FROM \(table) e JOIN glyphs g ON g.id=e.glyph_id WHERE e.category=? ORDER BY e.position LIMIT ? OFFSET ?", [.text(category.id), .integer(size + 1), .integer(start)])
        let items = fetched.prefix(size).compactMap { row -> BrowseOccurrence? in
            guard let original = decode(row[2]), let position = Int(row[0]) else { return nil }
            let glyph = presentedGlyph(original, symbol: row[3], name: row[4].isEmpty ? nil : row[4])
            return BrowseOccurrence(id: row[1], categoryID: category.id, position: position, glyph: glyph)
        }
        return BrowsePage(items: items, nextCursor: fetched.count > size ? .offset(start + size) : nil, startOffset: start, totalCount: .known(category.memberCount))
    }

    func browseRule(_ category: BrowseCategory) -> (predicate: String, parameters: [QueryValue], order: String) {
        switch category.source {
        case .curatedSet(let set): return ("g.setname=?", [.text(set)], "g.ord")
        case .block(let block, _): return ("g.setname='Other Glyphs' AND json_extract(g.payload,'$.block')=?", [.text(block)], "g.ord")
        case .legacyRanges(let ranges):
            let predicate = ranges.map { _ in "unicode(g.symbol) BETWEEN ? AND ?" }.joined(separator: " OR ")
            let parameters: [QueryValue] = ranges.flatMap { [.integer(Int($0.lowerBound)), .integer(Int($0.upperBound))] }
            let order = category.id == "legacy:Music" ? "CASE WHEN unicode(g.symbol) BETWEEN 9833 AND 9839 THEN 0 WHEN unicode(g.symbol) BETWEEN 119040 AND 119295 THEN 1 ELSE 2 END,g.ord" : "g.ord"
            return ("(" + (predicate.isEmpty ? "0" : predicate) + ")", parameters, order)
        case .unichar, .utility: return ("0", [], "g.ord")
        }
    }

    func historyGlyph(id: String, symbol: String?) -> Glyph {
        if var value = glyph(id: id) { if let symbol { value.symbol = symbol }; return value }
        let fallback = symbol ?? id.split(separator: " ").compactMap { UInt32($0, radix: 16).flatMap(UnicodeScalar.init).map(String.init) }.joined()
        return Glyph(id: id, symbol: fallback.isEmpty ? "�" : fallback, name: "History character " + id, set: nil,
                     skinModifiable: false, entities: [], twins: [], related: [], block: nil, script: nil, age: nil,
                     annotations: nil, genderVariants: nil, textPresentation: nil, skinVariants: [])
    }

    func presentedGlyph(_ glyph: Glyph, symbol: String, name: String? = nil) -> Glyph {
        Glyph(id: glyph.id, symbol: symbol, name: name ?? glyph.name, set: glyph.set, skinModifiable: glyph.skinModifiable,
              entities: glyph.entities, twins: glyph.twins, related: glyph.related, block: glyph.block, script: glyph.script,
              age: glyph.age, annotations: glyph.annotations, genderVariants: glyph.genderVariants,
              textPresentation: glyph.textPresentation, skinVariants: glyph.skinVariants)
    }
}
