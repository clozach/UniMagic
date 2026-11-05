import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ description: String) {
    if !condition() { fatalError(description) }
}
let url = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/unimagic-build/resources/corpus.sqlite")
let engine = try GlyphSearch(databaseURL: url)
expect(engine.count == 39694, "complete corpus plus 68 observed native supplements")
let emDash = engine.search(query: "U+2014").first!
expect(emDash.symbol == "—", "explicit codepoint")
expect(!engine.search(query: "U+8212").contains { $0.id == "2014" }, "explicit U+ does not fall back to decimal")
expect(!engine.search(query: "0x8212").contains { $0.id == "2014" }, "explicit 0x does not fall back to decimal")
expect(engine.search(query: "8212").first?.id == "2014", "bare digits retain decimal fallback")
expect(engine.search(query: "—").first?.id == emDash.id, "paste")
for (symbol, id) in [("©", "00A9"), ("♥", "2665"), ("❤", "2764"), ("❤︎", "2764"), ("❤️", "2764")] {
    expect(engine.search(query: symbol).first?.id == id, "pasted presentation variant \(symbol)")
}
expect(engine.search(query: "->").contains { $0.symbol == "→" }, "sign")
expect(engine.search(query: "heart").first?.id == "2764", "canonical shortcode")
expect(engine.search(query: "hea", limit: 3).contains { $0.id == "2764" }, "autosuggest favors heart completion over distant heavy-name matches")
for query in ["x", "x-", "xr", "x-r"] {
    expect(engine.search(query: query).contains { $0.name.lowercased().contains("x-ray") }, "prefix normalization: \(query)")
}
expect(engine.search(query: "é").contains { $0.symbol == "é" }, "accent paste retained")
expect(engine.search(query: "\" OR *", limit: 7).count <= 7, "FTS escaped")
let initial = LearningStore()
let taught = initial.teach(term: "squiggle", hexseq: emDash.id)
expect(initial.learned.isEmpty, "pure teach")
expect(taught.learned.first?.type == .provisional, "provisional teach")
expect(engine.search(query: "squig", learned: taught.learned).first?.id == emDash.id, "zero-score alias recall")
let picked = taught.pick(query: "squiggle", hexseq: emDash.id)
expect(picked.learned.first?.type == .learned && picked.learned.first?.score == 1, "graduation")
expect(picked.usage.first?.count == 1, "pick usage")
expect(engine.browse(usage: picked.usage).first?.id == emDash.id, "frequent browse")
expect(picked.unlearn(term: "squiggle", hexseq: emDash.id).learned.isEmpty, "unlearn")
let dual = initial.pick(query: "red heart", hexseq: "2764")
expect(dual.learned.contains { $0.term == "red" && $0.type == .provisional && $0.score == 0 }, "dual voting")
let roundTrip = try JSONDecoder().decode(LearningStore.self, from: JSONEncoder().encode(dual))
expect(roundTrip == dual, "Codable learning")
let thumb = engine.glyph(id: "1F44D")!
expect(thumb.skinVariant(tone: 1) == "👍🏻\u{FE0F}", "canonical skin variant")
let lotus = engine.glyph(id: "1F9D8 200D 2640")!
let lightID = "1F9D8 1F3FB 200D 2640"
expect(lotus.picked(symbol: lotus.skinVariant(tone: 1)).id == lightID, "a toned pick learns under the toned id")
expect(lotus.picked(symbol: lotus.symbol).id == lotus.id, "an untoned pick keeps the base id")
expect(engine.glyph(id: lightID)?.symbol == lotus.skinVariant(tone: 1), "toned id rebuilt from its base")
expect(engine.glyph(id: "1F9D8 1F3FB 200D 2640 FFFF") == nil, "unknown toned id stays unknown")
let kk = LearningStore().pick(query: "kk", hexseq: lightID).pick(query: "kk", hexseq: lightID)
expect(engine.search(query: "kk", learned: kk.learned).first?.id == lightID, "KK → 🧘🏻‍♀️ after two picks")
expect(engine.search(query: "yoga").contains { $0.id == lotus.id }, "base keeps its own words")
expect(engine.browse(usage: kk.usage).first?.id == lightID, "toned glyph in Frequently used")
expect(engine.browse(set: "Dashes").allSatisfy { $0.set == "Dashes" }, "set filter")
expect(engine.search(query: "heart", limit: 3).count == 3, "bounded results")
print("Engine: full corpus, direct/word/prefix/alias search, learning, skin variants and browse passed")


let inventoryURL = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "ios/Resources/BrowseInventory.json")
let corpusURL = URL(fileURLWithPath: CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "unimagic-corpus.json")
try runBrowseEngineTests(engine: engine, inventoryURL: inventoryURL, corpusURL: corpusURL)
