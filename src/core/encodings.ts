/**
 * Unimagic core — encodings + escapes generators for the Tier 2 detail card.
 * Pure math over a glyph STRING; zero corpus lookup, zero licensing surface
 * (design.md § "GENERATE": "UTF-8/16 bytes, all escape syntaxes … pure math at
 * render time"). Isomorphic: no Node built-ins, no DOM — `TextEncoder` is a Web
 * global present in both the Obsidian renderer and any PWA host.
 *
 * Feeds detail-card field rows 1–3 (design.md § Tier 2):
 *   1. Codepoints — `codePoints` / `hexList`
 *   2. Encodings  — `utf8Bytes` / `utf16Units`
 *   3. Escapes    — `escapes`
 *
 * The input `g` is a whole glyph and may be many code points (a ZWJ emoji such
 * as "👩‍⚕️", or a VS16 pair like "❤️"). Everything here iterates by code point
 * (`[...g]`) or by UTF-16 unit (`charCodeAt`) — never assuming 1 char = 1 code
 * point — and every escape form covers the ENTIRE sequence, concatenated.
 */

// ─────────────────────────────────────────────────────────────────────────
// Hex helpers (private) — uppercase throughout, per house convention.
// ─────────────────────────────────────────────────────────────────────────

/** Uppercase hex, no leading zeros (brace/CSS/HTML forms self-delimit). */
const hex = (n: number): string => n.toString(16).toUpperCase();
/** Uppercase hex zero-padded to `width` (fixed-width `\uXXXX` / `\U000XXXXX`). */
const hexPad = (n: number, width: number): string =>
  n.toString(16).toUpperCase().padStart(width, "0");

/** UTF-16 code units of `g` as numbers; astral chars yield a surrogate pair. */
function utf16CodeUnits(g: string): number[] {
  const units: number[] = [];
  for (let i = 0; i < g.length; i++) units.push(g.charCodeAt(i));
  return units;
}

/** UTF-8 bytes of `g` as numbers (shared by `utf8Bytes` and `escapes.url`). */
function utf8ByteValues(g: string): Uint8Array {
  return new TextEncoder().encode(g);
}

// ─────────────────────────────────────────────────────────────────────────
// Field 1 — Codepoints (design.md § Tier 2, row 1)
// ─────────────────────────────────────────────────────────────────────────

/** The code points of `g`, in order (a ZWJ sequence yields several). */
export function codePoints(g: string): number[] {
  return [...g].map((ch) => ch.codePointAt(0) as number);
}

/**
 * `U+`-prefixed code points, uppercase, min 4 hex digits — e.g.
 * `["U+2764", "U+FE0F"]` for "❤️". The chip form of field 1.
 */
export function hexList(g: string): string[] {
  return codePoints(g).map((cp) => "U+" + hexPad(cp, 4));
}

// ─────────────────────────────────────────────────────────────────────────
// Field 2 — Encodings (design.md § Tier 2, row 2 — "pure math")
// ─────────────────────────────────────────────────────────────────────────

/**
 * Space-separated uppercase hex of `g`'s UTF-8 bytes — e.g. `"E2 80 94"` for
 * "—". Each byte is two hex digits.
 */
export function utf8Bytes(g: string): string {
  return Array.from(utf8ByteValues(g), (b) => hexPad(b, 2)).join(" ");
}

/**
 * Space-separated uppercase 4-hex UTF-16 code units. Astral code points appear
 * as their surrogate PAIR (two units) — e.g. "😀" → `"D83D DE00"`.
 */
export function utf16Units(g: string): string {
  return utf16CodeUnits(g)
    .map((u) => hexPad(u, 4))
    .join(" ");
}

// ─────────────────────────────────────────────────────────────────────────
// Field 3 — Escapes (design.md § Tier 2, row 3 — "pure math")
// ─────────────────────────────────────────────────────────────────────────

/**
 * The source-escape syntaxes for `g`, one per language/context. Keys match the
 * design.md field-3 list (JS, CSS, HTML numeric, JSON, Python, Swift, URL).
 * Every value covers the WHOLE glyph string, concatenated.
 */
export interface Escapes {
  /** ES2015 code-point escape: `\u{2764}\u{FE0F}` (per code point). */
  js: string;
  /** Pre-ES6 escape: `\uXXXX` per UTF-16 unit (surrogate pairs → two units). */
  jsLegacy: string;
  /** CSS escape: `\2764 \FE0F ` — hex per code point, each space-terminated. */
  css: string;
  /** HTML hex numeric char refs: `&#x2764;&#xFE0F;` (per code point). */
  htmlHex: string;
  /** HTML decimal numeric char refs: `&#10084;&#65039;` (per code point). */
  htmlDec: string;
  /** JSON string escape: `\uXXXX` per UTF-16 unit (no `\u{}` form in JSON). */
  json: string;
  /** Python named escape `\N{NAME}`, or the `\u`/`\U` form when not applicable. */
  pythonName: string;
  /** Python numeric escape: `\uXXXX` (BMP) / `\U000XXXXX` (astral) per code point. */
  pythonU: string;
  /** Swift unicode scalar escape: `\u{2764}\u{FE0F}` (per code point). */
  swift: string;
  /** Percent-encoding of `g`'s UTF-8 bytes: `%E2%80%94`. */
  url: string;
}

/**
 * Build every escape syntax for `g` (design.md § Tier 2, row 3).
 *
 * `name` is the primary Unicode name of the glyph, used only for `pythonName`'s
 * `\N{…}` form. Python's `\N{…}` names a single code point, so it is emitted
 * ONLY when `g` is exactly one code point and a `name` is supplied; otherwise
 * `pythonName` falls back to the numeric `pythonU` form (a defensible,
 * always-valid escape for multi-code-point or unnamed glyphs).
 */
export function escapes(g: string, name?: string): Escapes {
  const cps = codePoints(g);
  const units = utf16CodeUnits(g);

  const perUnit = units.map((u) => `\\u${hexPad(u, 4)}`).join("");
  const pythonU = cps
    .map((cp) => (cp > 0xffff ? `\\U${hexPad(cp, 8)}` : `\\u${hexPad(cp, 4)}`))
    .join("");

  const pythonName =
    cps.length === 1 && name ? `\\N{${name.toUpperCase()}}` : pythonU;

  return {
    js: cps.map((cp) => `\\u{${hex(cp)}}`).join(""),
    jsLegacy: perUnit,
    css: cps.map((cp) => `\\${hex(cp)} `).join(""),
    htmlHex: cps.map((cp) => `&#x${hex(cp)};`).join(""),
    htmlDec: cps.map((cp) => `&#${cp};`).join(""),
    json: perUnit,
    pythonName,
    pythonU,
    swift: cps.map((cp) => `\\u{${hex(cp)}}`).join(""),
    url: Array.from(utf8ByteValues(g), (b) => `%${hexPad(b, 2)}`).join(""),
  };
}
