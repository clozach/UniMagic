import CoreText
import SwiftUI

/// Never present a missing-font box as if it were the requested character.
struct GlyphSymbol: View {
  let glyph: Glyph
  private var supported: Bool {
    let font = CTFontCreateUIFontForLanguage(.system, 30, nil)!
    let line = CTLineCreateWithAttributedString(
      NSAttributedString(
        string: glyph.display,
        attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
    let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
    for run in runs {
      let attributes = CTRunGetAttributes(run) as NSDictionary
      if let runFont = attributes[kCTFontAttributeName] as! CTFont?,
        CTFontCopyPostScriptName(runFont) as String == "LastResort"
      {
        return false
      }
      let count = CTRunGetGlyphCount(run)
      var glyphs = [CGGlyph](repeating: 0, count: count)
      CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
      if glyphs.contains(0) { return false }
    }
    return !runs.isEmpty
  }
  var body: some View {
    Group {
      if supported {
        Text(glyph.display).font(.system(size: 30))
      } else {
        Text("U+" + glyph.hexseq.replacingOccurrences(of: " ", with: "\n")).font(
          .system(size: 10, design: .monospaced)
        ).foregroundStyle(.secondary).multilineTextAlignment(.center)
      }
    }.accessibilityLabel(glyph.name)
  }
}
