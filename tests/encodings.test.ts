import { describe, test, expect } from "vitest";
import {
  codePoints,
  hexList,
  utf8Bytes,
  utf16Units,
  escapes,
} from "../src/core/encodings";

// Goldens for detail-card fields 1–3 (design.md § Tier 2). Expected escape
// strings use DOUBLED backslashes so the literal `\u…` text is asserted, not a
// JS escape sequence. Values hand-verified with a Node TextEncoder one-liner.

describe("encodings — em dash '—' (U+2014, single BMP code point)", () => {
  const g = "—";

  test("codepoints / hex list", () => {
    expect(codePoints(g)).toEqual([0x2014]); // 8212
    expect(hexList(g)).toEqual(["U+2014"]);
  });

  test("UTF-8 bytes and UTF-16 units", () => {
    expect(utf8Bytes(g)).toBe("E2 80 94");
    expect(utf16Units(g)).toBe("2014");
  });

  test("escapes cover the whole glyph", () => {
    const e = escapes(g, "em dash");
    expect(e.js).toBe("\\u{2014}");
    expect(e.jsLegacy).toBe("\\u2014");
    expect(e.css).toBe("\\2014 "); // trailing space is the CSS delimiter
    expect(e.htmlHex).toBe("&#x2014;");
    expect(e.htmlDec).toBe("&#8212;");
    expect(e.json).toBe("\\u2014");
    expect(e.swift).toBe("\\u{2014}");
    expect(e.url).toBe("%E2%80%94");
  });

  test("pythonName uses \\N{NAME} (uppercased) for a single named code point", () => {
    expect(escapes(g, "em dash").pythonName).toBe("\\N{EM DASH}");
    expect(escapes(g, "em dash").pythonU).toBe("\\u2014");
  });

  test("pythonName falls back to \\u form when no name is supplied", () => {
    const e = escapes(g);
    expect(e.pythonName).toBe(e.pythonU);
    expect(e.pythonName).toBe("\\u2014");
  });
});

describe("encodings — red heart '❤️' (U+2764 U+FE0F, two code points)", () => {
  const g = "❤️";

  test("two code points, hex list keeps both", () => {
    expect(codePoints(g)).toEqual([0x2764, 0xfe0f]); // 10084, 65039
    expect(hexList(g)).toEqual(["U+2764", "U+FE0F"]);
  });

  test("UTF-8 is the full 6-byte sequence; UTF-16 is two units", () => {
    expect(utf8Bytes(g)).toBe("E2 9D A4 EF B8 8F");
    expect(utf16Units(g)).toBe("2764 FE0F");
  });

  test("escapes span both code points, in order", () => {
    const e = escapes(g);
    expect(e.js).toBe("\\u{2764}\\u{FE0F}");
    expect(e.jsLegacy).toBe("\\u2764\\uFE0F");
    expect(e.css).toBe("\\2764 \\FE0F ");
    expect(e.htmlHex).toBe("&#x2764;&#xFE0F;");
    expect(e.htmlDec).toBe("&#10084;&#65039;");
    expect(e.json).toBe("\\u2764\\uFE0F");
    expect(e.pythonU).toBe("\\u2764\\uFE0F");
    expect(e.swift).toBe("\\u{2764}\\u{FE0F}");
    expect(e.url).toBe("%E2%9D%A4%EF%B8%8F");
  });

  test("pythonName falls back to the numeric form for a multi-code-point glyph even with a name", () => {
    const e = escapes(g, "heavy black heart");
    expect(e.pythonName).toBe(e.pythonU); // \N{…} names one code point only
    expect(e.pythonName).toBe("\\u2764\\uFE0F");
  });
});

describe("encodings — grinning face '😀' (U+1F600, astral / surrogate pair)", () => {
  const g = "😀";

  test("one code point despite two UTF-16 units", () => {
    expect(codePoints(g)).toEqual([0x1f600]); // 128512
    expect(hexList(g)).toEqual(["U+1F600"]);
  });

  test("UTF-16 shows the surrogate pair; UTF-8 is four bytes", () => {
    expect(utf16Units(g)).toBe("D83D DE00");
    expect(utf8Bytes(g)).toBe("F0 9F 98 80");
  });

  test("legacy/JSON escapes emit the surrogate pair; python uses \\U + 8 hex", () => {
    const e = escapes(g);
    expect(e.jsLegacy).toBe("\\uD83D\\uDE00");
    expect(e.json).toBe("\\uD83D\\uDE00");
    expect(e.js).toBe("\\u{1F600}");
    expect(e.swift).toBe("\\u{1F600}");
    expect(e.pythonU).toBe("\\U0001F600");
    expect(e.url).toBe("%F0%9F%98%80");
  });

  test("pythonName falls back to \\U form for a single unnamed astral glyph", () => {
    const e = escapes(g);
    expect(e.pythonName).toBe(e.pythonU);
    expect(e.pythonName).toBe("\\U0001F600");
  });
});

describe("encodings — ZWJ emoji '👩‍⚕️' woman health worker (1F469 200D 2695 FE0F)", () => {
  const g = "👩‍⚕️";

  test("four code points in order", () => {
    expect(codePoints(g)).toEqual([0x1f469, 0x200d, 0x2695, 0xfe0f]);
    expect(codePoints(g)).toHaveLength(4);
    expect(hexList(g)).toEqual(["U+1F469", "U+200D", "U+2695", "U+FE0F"]);
  });

  test("escapes cover all four code points in order", () => {
    const e = escapes(g, "woman health worker");
    expect(e.js).toBe("\\u{1F469}\\u{200D}\\u{2695}\\u{FE0F}");
    expect(e.swift).toBe("\\u{1F469}\\u{200D}\\u{2695}\\u{FE0F}");
    // astral first scalar → \U + 8 hex; the BMP scalars → \u + 4 hex
    expect(e.pythonU).toBe("\\U0001F469\\u200D\\u2695\\uFE0F");
    // multi-code-point → pythonName falls back to the numeric form
    expect(e.pythonName).toBe(e.pythonU);
    expect(e.htmlDec).toBe("&#128105;&#8205;&#9877;&#65039;");
  });
});
