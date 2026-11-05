// Records every glyph this Mac's fonts cannot draw. A glyph is missing when typesetting it falls
// back to LastResort or to glyph 0 — the box Obsidian's canvas scan compares against.
// Usage: unimagic-coverage <glyphs.tsv> <coverage.json>. The TSV's first line is "#build<TAB>…",
// then "hexseq<TAB>symbol" rows. The cache is keyed to the corpus build and this macOS version,
// matching coverage.ts, and is written here rather than by JavaScript so that closing the
// palette mid-scan still leaves an answer behind.
import CoreText
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: unimagic-coverage <glyphs.tsv> <coverage.json>\n".utf8))
    exit(64)
}
let rows = try String(contentsOfFile: arguments[1], encoding: .utf8).split(separator: "\n")
let font = CTFontCreateUIFontForLanguage(.system, 22, nil)!
let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]

func isMissing(_ text: String) -> Bool {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
    if runs.isEmpty { return true }
    for run in runs {
        let runAttributes = CTRunGetAttributes(run) as NSDictionary
        if let runFont = runAttributes[kCTFontAttributeName] as! CTFont?,
            CTFontCopyPostScriptName(runFont) as String == "LastResort"
        {
            return true
        }
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        if glyphs.contains(0) { return true }
    }
    return false
}

var build = ""
var missing: [String] = []
for row in rows {
    let fields = row.split(separator: "\t", maxSplits: 1).map(String.init)
    guard fields.count == 2 else { continue }
    if fields[0] == "#build" {
        build = fields[1]
    } else if isMissing(fields[1]) {
        missing.append(fields[0])
    }
}
let key = "\(build) | \(ProcessInfo.processInfo.operatingSystemVersionString)"
let json = try JSONSerialization.data(withJSONObject: ["key": key, "missing": missing])
try json.write(to: URL(fileURLWithPath: arguments[2]), options: .atomic)
print("\(missing.count) of \(rows.count - 1) glyphs cannot be drawn on this Mac")
