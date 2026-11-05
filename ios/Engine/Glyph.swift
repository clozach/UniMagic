import Foundation

public struct Glyph: Identifiable, Codable, Sendable {
    public let id: String
    public var symbol: String
    public let name: String
    public let set: String?
    public let skinModifiable: Bool
    public let entities: [String]
    public let twins: [String]
    public let related: [String]
    public let block: String?
    public let script: String?
    public let age: String?
    public let annotations: [String]?
    public let genderVariants: [String]?
    public let textPresentation: Bool?

    public let skinVariants: [String]

    /// Precomputed by the canonical TypeScript skinVariants helper.
    public func skinVariant(tone: Int) -> String {
        guard skinModifiable, skinVariants.indices.contains(tone) else { return symbol }
        return skinVariants[tone]
    }

    /// A toned variant as its own glyph, so learning can name 🧘🏻‍♀️ rather than 🧘‍♀️.
    /// Mirrors `tonedRecords` in core/glyphs.ts: the modifier follows the first code point.
    public func toned(_ tone: Int) -> Glyph? {
        guard skinModifiable, (1...5).contains(tone), skinVariants.indices.contains(tone) else { return nil }
        var parts = id.split(separator: " ").map(String.init)
        parts.insert(skinToneModifiers[tone - 1], at: 1)
        return Glyph(id: parts.joined(separator: " "), symbol: skinVariants[tone], name: name + ": " + skinToneNames[tone - 1],
                     set: set, skinModifiable: false, entities: entities, twins: twins, related: related, block: block,
                     script: script, age: age, annotations: annotations, genderVariants: genderVariants,
                     textPresentation: textPresentation, skinVariants: [])
    }

    /// The glyph a pick of `symbol` teaches: the toned variant it names, else this glyph.
    public func picked(symbol: String) -> Glyph {
        func plain(_ s: String) -> String { String(String.UnicodeScalarView(s.unicodeScalars.filter { $0.value != 0xFE0E && $0.value != 0xFE0F })) }
        return (1...5).lazy.compactMap { self.toned($0) }.first { plain($0.symbol) == plain(symbol) } ?? self
    }

}

let skinToneModifiers = ["1F3FB", "1F3FC", "1F3FD", "1F3FE", "1F3FF"]
let skinToneNames = ["light skin tone", "medium-light skin tone", "medium skin tone", "medium-dark skin tone", "dark skin tone"]

/// A toned id's base id and tone (1–5), when `id` carries a skin-tone modifier after its first code point.
func skinToneBase(of id: String) -> (base: String, tone: Int)? {
    var parts = id.split(separator: " ").map(String.init)
    guard parts.count >= 2, let index = skinToneModifiers.firstIndex(of: parts[1]) else { return nil }
    parts.remove(at: 1)
    return (parts.joined(separator: " "), index + 1)
}

public func normalizedSearchText(_ text: String) -> String {
    text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "(?<=[\\p{L}\\p{N}_])[-‐‑]+", with: "", options: .regularExpression)
}

func searchWords(_ text: String) -> [String] {
    let value = normalizedSearchText(text)
    let regex = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}_]+")
    return regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
        .compactMap { Range($0.range, in: value).map { String(value[$0]) } }
}
