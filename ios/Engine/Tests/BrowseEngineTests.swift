import Foundation

struct BrowseTestInventory: Decodable {
    struct Category: Decodable {
        struct Entry: Decodable { let occurrenceID: String; let glyphID: String; let symbol: String; let name: String? }
        struct Membership: Decodable { let kind: String; let entries: [Entry]? }
        let id: String; let title: String; let sample: [Entry]; let membership: Membership; let memberCount: Int
    }
    struct Supplement: Decodable { let glyphID: String; let symbol: String }
    let categories: [Category]; let supplements: [Supplement]
}
struct BrowseTestCorpus: Decodable {
    struct Record: Decodable { let hexseq: String; let symbol: String; let set: String?; let block: String?; let order: Int }
    let records: [Record]
}

func runBrowseEngineTests(engine: GlyphSearch, inventoryURL: URL, corpusURL: URL) throws {
    let inventory = try JSONDecoder().decode(BrowseTestInventory.self, from: Data(contentsOf: inventoryURL))
    let corpus = try JSONDecoder().decode(BrowseTestCorpus.self, from: Data(contentsOf: corpusURL))
    expect(engine.categories.count == 354, "Complete 354-destination catalogue")
    expect(engine.categories.map(\.id) == inventory.categories.map(\.id), "Stable catalogue order/identity")
    expect(engine.categories.first(where: { !$0.isUtility })?.id == "set:Emojis", "Emoji leads ordinary categories")
    expect(engine.categories.first { $0.id == "set:Emojis" }?.symbol.utf8.elementsEqual("🐻‍❄️".utf8) == true, "Exact polar-bear exemplar")
    var reachable = Set<String>(), samples = 0, occurrences = 0
    for (category, expected) in zip(engine.categories, inventory.categories) where !category.isUtility {
        var offset = 0, actual: [BrowseOccurrence] = []
        repeat {
            let page = engine.browsePage(category: category, offset: offset, limit: 37)
            expect(page.items.count <= 37, "Bounded native page")
            actual += page.items
            if let cursor = page.nextCursor, case .offset(let next) = cursor { expect(next > offset, "Cursor progresses"); offset = next }
            else { break }
        } while true
        expect(actual.count == expected.memberCount, "Complete membership \(category.id): \(actual.count) vs \(expected.memberCount)")
        expect(Set(actual.map(\.id)).count == actual.count, "Distinct occurrence IDs \(category.id)")
        expect(actual.map(\.position) == Array(0..<actual.count), "Absolute occurrence positions \(category.id)")
        if let explicit = expected.membership.entries {
            expect(actual.map(\.id) == explicit.map(\.occurrenceID), "Explicit occurrence identities \(category.id)")
            for (item, entry) in zip(actual, explicit) {
                expect(item.glyph.id == entry.glyphID && item.glyph.symbol.utf8.elementsEqual(entry.symbol.utf8), "Exact explicit strings \(category.id)")
                if let name = entry.name { expect(item.glyph.name == name, "Observed name retained") }
            }
        } else {
            var matching = corpus.records.filter { record in
                switch category.source {
                case .curatedSet(let set): return record.set == set
                case .block(let block, _): return record.set == "Other Glyphs" && record.block == block
                case .legacyRanges(let ranges): return record.symbol.unicodeScalars.first.map { scalar in ranges.contains { $0.contains(scalar.value) } } ?? false
                case .utility, .unichar: return false
                }
            }
            if category.id == "legacy:Music" {
                func rank(_ r: BrowseTestCorpus.Record) -> Int { let cp = r.symbol.unicodeScalars.first!.value; return (0x2669...0x266F).contains(cp) ? 0 : ((0x1D100...0x1D1FF).contains(cp) ? 1 : 2) }
                matching.sort { rank($0) == rank($1) ? $0.order < $1.order : rank($0) < rank($1) }
            }
            expect(actual.map { $0.glyph.id } == matching.map(\.hexseq), "SQL matches independent scalar/set/block filter \(category.id)")
            if category.id == "legacy:Music", let last = actual.last {
                let context = engine.contexts(for: last.glyph, origin: last.origin).first!
                expect(context.position == last.position && context.occurrenceID == last.id, "Numeric range/rank context position")
            }
        }
        var sampleOffset = 0, actualSamples: [BrowseOccurrence] = []
        repeat {
            let page = engine.browseSamples(category: category, offset: sampleOffset, limit: 37)
            actualSamples += page.items
            if case .offset(let next) = page.nextCursor { sampleOffset = next } else { break }
        } while true
        expect(actualSamples.map(\.id) == expected.sample.map(\.occurrenceID), "Sample identity and order \(category.id)")
        for (item, entry) in zip(actualSamples, expected.sample) { expect(item.glyph.symbol.utf8.elementsEqual(entry.symbol.utf8), "Exact sample bytes") }
        if case .unichar = category.source { samples += actualSamples.count }
        reachable.formUnion(actual.map { $0.glyph.id }); occurrences += actual.count
    }
    expect(samples == 6825, "All observed samples retained")
    expect(reachable.count == 39694, "Every canonical/supplement record has a full context")
    for item in inventory.supplements {
        let glyph = engine.glyph(id: item.glyphID)!
        expect(!engine.contexts(for: glyph).isEmpty, "Supplement context \(item.glyphID)")
    }
    if let duplicated = inventory.categories.first(where: { category in
        guard let entries = category.membership.entries else { return false }
        return Dictionary(grouping: entries, by: { $0.glyphID + "|" + $0.symbol }).values.contains { $0.count > 1 }
    }), let entries = duplicated.membership.entries {
        let group = Dictionary(grouping: entries, by: { $0.glyphID + "|" + $0.symbol }).values.first { $0.count > 1 }!
        let second = group[1], position = entries.firstIndex { $0.occurrenceID == second.occurrenceID }!
        let category = engine.categories.first { $0.id == duplicated.id }!
        let occurrence = engine.browsePage(category: category, offset: position, limit: 1).items[0]
        let target = engine.contexts(for: occurrence.glyph, origin: occurrence.origin).first!
        expect(target.occurrenceID == second.occurrenceID && target.position == position, "Repeated occurrence origin survives context")
    }
    let textSun = engine.presentedGlyph(engine.glyph(id: "2600")!, symbol: "☀︎")
    expect(engine.contexts(for: textSun).contains { target in
        guard case .exactOccurrence = target.match else { return false }; return target.glyph.symbol.utf8.elementsEqual("☀︎".utf8)
    }, "Text-style presentation has exact occurrence context")
    print("Browse: \(occurrences) full occurrences across352 collections/blocks,6825 exact samples, all39694 records reachable; range/binding, duplicate/context and presentation checks pass")
}
