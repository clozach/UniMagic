import Foundation
import SQLite3

/// Read-only SQLite queries keep the 39,626-record corpus outside keyboard memory.
/// FTS5 BM25 differs from MiniSearch scoring and omits fuzzy recall; all exact
/// signal weights and field boosts come from canonical TS generator metadata.
/// Use from one serial executor; this class deliberately is not Sendable.
public final class GlyphSearch {
    private var database: OpaquePointer?
    private let decoder = JSONDecoder()
    private var weights: [String: Double] = [:]
    private var boosts: [String: Double] = [:]
    public private(set) var count: Int = 0
    public private(set) var curatedSets: [String] = []
    public private(set) var categories: [BrowseCategory] = []
    public private(set) var catalogueRevision = ""
    private struct BrowseMetadata: Decodable { let schemaVersion: Int; let revision: String; let canonical: Int; let supplements: Int; let collections: Int; let blocks: Int }

    public init(databaseURL: URL) throws {
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open corpus"
            if let database { sqlite3_close(database) }
            database = nil
            throw NSError(domain: "UnimagicCorpus", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
        }
        sqlite3_exec(database, "PRAGMA cache_size=-512; PRAGMA mmap_size=0;", nil, nil, nil)
        let metadata = rows("SELECT key,value FROM metadata")
        var browseMetadata: BrowseMetadata?
        for row in metadata {
            guard row.count == 2, let bytes = row[1].data(using: .utf8) else { continue }
            switch row[0] {
            case "weights": weights = (try? decoder.decode([String: Double].self, from: bytes)) ?? [:]
            case "fieldBoosts": boosts = (try? decoder.decode([String: Double].self, from: bytes)) ?? [:]
            case "count": count = Int(row[1]) ?? 0
            case "sets": curatedSets = (try? decoder.decode([String].self, from: bytes)) ?? []
            case "nativeBrowse": browseMetadata = try? decoder.decode(BrowseMetadata.self, from: bytes)
            default: break
            }
        }
        // Refuse an incomplete/stale database at the boundary rather than
        // presenting an apparently valid empty picker after a schema error.
        let requiredSchema = [
            "SELECT id,symbol,name,setname,firstcp,canonical,ord,payload FROM glyphs LIMIT 0",
            "SELECT sign,id FROM signs LIMIT 0",
            "SELECT id,name,tags,entities,category FROM words LIMIT 0",
            "SELECT position,category,title,symbol,definition FROM browse_categories LIMIT 0",
            "SELECT category,position,occurrence_id,glyph_id,symbol,name FROM browse_entries LIMIT 0",
            "SELECT category,position,occurrence_id,glyph_id,symbol,name FROM browse_samples LIMIT 0"
        ]
        for sql in requiredSchema {
            var statement: OpaquePointer?
            let result = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
            sqlite3_finalize(statement)
            guard result == SQLITE_OK else {
                throw NSError(domain: "UnimagicCorpus", code: 3, userInfo: [NSLocalizedDescriptionKey: "Incomplete corpus database"])
            }
        }
        categories = try rows("SELECT category,definition FROM browse_categories ORDER BY position").map { row in
            guard let data = row[1].data(using: .utf8) else { throw NativeStoreError.invalidDocument("Invalid category definition") }
            let category = try decoder.decode(BrowseCategory.self, from: data)
            guard category.id == row[0], !category.id.isEmpty, category.memberCount >= 0 else { throw NativeStoreError.invalidDocument("Invalid category identity/count") }
            return category
        }
        guard let metadata = browseMetadata, metadata.schemaVersion == 2,
              count == metadata.canonical + metadata.supplements,
              categories.count == metadata.collections + metadata.blocks + 2,
              weights["canonical"] != nil else {
            throw NSError(domain: "UnimagicCorpus", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid corpus/catalogue metadata"])
        }
        catalogueRevision = metadata.revision
    }
    deinit { if let database { sqlite3_close(database) } }

    public func glyph(id: String) -> Glyph? {
        if let row = rows("SELECT payload FROM glyphs WHERE id=?", [id]).first { return decode(row[0]) }
        // The corpus folds skin tones into their base; a learned toned id is rebuilt from it.
        guard let (base, tone) = skinToneBase(of: id) else { return nil }
        return rows("SELECT payload FROM glyphs WHERE id=?", [base]).first.flatMap { decode($0[0]) }?.toned(tone)
    }

    public func browse(set: String? = nil, usage: [UsageEntry] = [], limit: Int = 100) -> [Glyph] {
        let maximum = max(0, min(limit, 500))
        guard maximum > 0 else { return [] }
        var output: [Glyph] = []
        var seen: Set<String> = []
        if set == nil || set == "Frequently used" {
            for entry in usage.sorted(by: { $0.count > $1.count }) where entry.count > 0 {
                guard output.count < maximum else { break }
                if let value = glyph(id: entry.hexseq), seen.insert(value.id).inserted { output.append(value) }
            }
            if set == "Frequently used" { return output }
        }
        let sql = "SELECT payload FROM glyphs" + (set == nil ? "" : " WHERE setname=?") + " ORDER BY ord LIMIT ?"
        for row in rows(sql, (set.map { [$0] } ?? []) + [String(maximum)]) {
            if let value = decode(row[0]), seen.insert(value.id).inserted { output.append(value) }
            if output.count == maximum { break }
        }
        return output
    }

    public func search(query: String, learned: [LearnedAlias] = [], usage: [UsageEntry] = [], limit: Int = 100) -> [Glyph] {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = raw.lowercased()
        guard !normalized.isEmpty, limit > 0 else { return [] }
        var scores: [String: Double] = [:]
        func add(_ ids: [[String]], _ score: Double) {
            for row in ids { scores[row[0], default: 0] += score }
        }
        let codepoints = codepointMatches(normalized)
        if !codepoints.isEmpty && (normalized.hasPrefix("u+") || normalized.hasPrefix("0x")) {
            return codepoints.prefix(min(limit, 500)).compactMap { glyph(id: $0[0]) }
        }
        for (index, row) in codepoints.enumerated() { scores[row[0], default: 0] += weights["codepoint", default: 1000] - Double(index) }
        let pasted = rows("SELECT id FROM glyphs WHERE symbol=?", [raw])
        add(pasted, weights["paste", default: 1000])
        if pasted.isEmpty, raw.unicodeScalars.contains(where: { $0.properties.isEmoji || $0.value == 0xFE0E || $0.value == 0xFE0F }) {
            let neutral = String(String.UnicodeScalarView(raw.unicodeScalars.filter { $0.value != 0xFE0E && $0.value != 0xFE0F }))
            add(rows("SELECT id FROM glyphs WHERE replace(replace(symbol,char(65038),''),char(65039),'')=? LIMIT 100", [neutral]), weights["paste", default: 1000])
        }
        add(rows("SELECT id FROM signs WHERE sign=?", [normalized]), weights["sign", default: 60])
        add(rows("SELECT id FROM glyphs WHERE canonical=?", [normalizedSearchText(normalized)]), weights["canonical", default: 500])
        let completion = normalizedSearchText(normalized)
        if (2...64).contains(completion.count) {
            // An unfinished short name should suggest its close completion:
            // “hea” → heart, ahead of long names that merely start with heavy.
            let sql = "SELECT id,length(canonical)-length(?) FROM glyphs WHERE substr(canonical,1,length(?))=? ORDER BY length(canonical),ord LIMIT 100"
            for row in rows(sql, [completion, completion, completion]) {
                let remaining = max(0, Double(row[1]) ?? 0)
                scores[row[0], default: 0] += weights["canonical", default: 500] * 0.5 / (remaining + 1)
            }
        }
        let tokens = searchWords(normalized)
        if !tokens.isEmpty {
            let match = tokens.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }.joined(separator: " AND ")
            let fieldWeights = ["name", "tags", "entities", "category"].map { String(boosts[$0, default: 1]) }.joined(separator: ",")
            // Keep candidate allocation bounded even for a single-letter query.
            let prior = weights["curation", default: 50]
            let sql = "SELECT words.id,bm25(words,0,\(fieldWeights)) FROM words JOIN glyphs ON glyphs.id=words.id WHERE words MATCH ? ORDER BY (-bm25(words,0,\(fieldWeights)) + \(prior) * (1.0 - CAST(glyphs.ord AS REAL) / \(max(count, 1)))) DESC,glyphs.ord LIMIT 500"
            for row in rows(sql, [match]) {
                scores[row[0], default: 0] += max(0, -(Double(row[1]) ?? 0)) * weights["text", default: 1]
            }
        }
        let aliasQuery = normalizedSearchText(normalized)
        var aliasScores: [String: Int] = [:]
        for alias in learned where normalizedSearchText(alias.term).hasPrefix(aliasQuery) {
            aliasScores[alias.hexseq, default: 0] += alias.score
        }
        for (id, score) in aliasScores { scores[id, default: 0] += weights["learned", default: 40] * Double(score + 1) }
        var ranked: [(String, Double, Int)] = []
        for (id, score) in scores {
            let rowID = rows("SELECT 1 FROM glyphs WHERE id=?", [id]).isEmpty ? (skinToneBase(of: id)?.base ?? id) : id
            guard let row = rows("SELECT ord FROM glyphs WHERE id=?", [rowID]).first, let order = Int(row[0]) else { continue }
            ranked.append((id, score + weights["curation", default: 50] * (1 - Double(order) / Double(max(count, 1))), order))
        }
        ranked.sort { $0.1 == $1.1 ? $0.2 < $1.2 : $0.1 > $1.1 }
        return ranked.prefix(min(limit, 500)).compactMap { glyph(id: $0.0) }
    }

    private func codepointMatches(_ query: String) -> [[String]] {
        guard query.range(of: "^(?:(?:u\\+|0x)?[0-9a-f]{2,6}|[0-9]{1,7})$", options: .regularExpression) != nil else { return [] }
        let digits = query.hasPrefix("u+") || query.hasPrefix("0x") ? String(query.dropFirst(2)) : query
        func lookup(_ number: UInt32?) -> [[String]] {
            guard let number, number <= 0x10FFFF else { return [] }
            return rows("SELECT id FROM glyphs WHERE firstcp=? ORDER BY length(id),ord LIMIT 500", [String(number, radix: 16).uppercased()])
        }
        let hex = lookup(UInt32(digits, radix: 16))
        // Explicit prefixes declare hexadecimal intent; decimal fallback belongs
        // only to an ambiguous bare all-digit query.
        if !hex.isEmpty || query.hasPrefix("u+") || query.hasPrefix("0x") { return hex }
        guard query.allSatisfy({ $0.isASCII && $0.isNumber }) else { return [] }
        return lookup(UInt32(digits, radix: 10))
    }

    func decode(_ text: String) -> Glyph? {
        text.data(using: .utf8).flatMap { try? decoder.decode(Glyph.self, from: $0) }
    }

    enum QueryValue { case text(String), integer(Int) }
    func rows(_ sql: String, _ parameters: [String] = []) -> [[String]] { boundRows(sql, parameters.map(QueryValue.text)) }
    func boundRows(_ sql: String, _ parameters: [QueryValue]) -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        for (index, parameter) in parameters.enumerated() {
            switch parameter {
            case .integer(let value): sqlite3_bind_int64(statement, Int32(index + 1), Int64(value))
            case .text(let value): _ = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, Int32(value.utf8.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            }
        }
        var output: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            output.append((0..<sqlite3_column_count(statement)).map { column in
                sqlite3_column_text(statement, column).map {
                    String(decoding: UnsafeBufferPointer(start: $0, count: Int(sqlite3_column_bytes(statement, column))), as: UTF8.self)
                } ?? ""
            })
        }
        return output
    }
}
