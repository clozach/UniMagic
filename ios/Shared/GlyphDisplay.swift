import UIKit
import CoreText

/// Missing native font coverage gets an actionable codepoint label; no entries disappear.
@MainActor enum GlyphDisplay {
    private static var coverage: [String: Bool] = [:]
    static func label(_ glyph: Glyph) -> String {
        label(symbol: glyph.symbol)
    }
    /// Presentation only: symbols in storage and insertion keep their exact scalar sequence.
    static func label(symbol: String) -> String {
        if let label = invisibleLabel(symbol) { return label }
        let first = symbol.unicodeScalars.first?.properties.generalCategory
        let display = first == .nonspacingMark || first == .spacingMark || first == .enclosingMark ? "◌" + symbol : symbol
        return supports(symbol: display) ? display : codepoints(symbol)
    }
    private static func codepoints(_ symbol: String) -> String {
        symbol.unicodeScalars.map { "U+" + String(format: "%04X", $0.value) }.joined(separator: " ")
    }
    private static func invisibleLabel(_ symbol: String) -> String? {
        let scalars = symbol.unicodeScalars
        if scalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) {
            switch scalars.first?.value {
            case 0x20: return "SP"
            case 0xA0: return "NBSP"
            case 0x202F: return "NNBSP"
            case 0x200B: return "ZWSP"
            default: return codepoints(symbol)
            }
        }
        return nil
    }
    static func supports(_ glyph: Glyph) -> Bool {
        supports(symbol: glyph.symbol)
    }
    private static func supports(symbol: String) -> Bool {
        if invisibleLabel(symbol) != nil { return true }
        if let cached = coverage[symbol] { return cached }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: symbol, attributes: [.font: UIFont.systemFont(ofSize: 30)]))
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        let supported = !runs.isEmpty && runs.allSatisfy { run in
            let attributes = CTRunGetAttributes(run) as NSDictionary
            if let font = attributes[kCTFontAttributeName] {
                let name = CTFontCopyPostScriptName(font as! CTFont) as String
                if name.localizedCaseInsensitiveContains("LastResort") { return false }
            }
            var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            return !glyphs.contains(0)
        }
        coverage[symbol] = supported
        return supported
    }
}
