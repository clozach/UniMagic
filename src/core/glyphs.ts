/**
 * Unimagic core — pure glyph derivations shared by every host: escape labels,
 * sequence-component names, whitespace demos, and skin-tone variants.
 * Isomorphic: no Node built-ins, no DOM.
 */
import type { CorpusRecord } from "./schema";
import type { IndexBundle } from "./search";
import type { escapes } from "./encodings";

/** Detail-card escape rows, in display order. */
export const ESCAPE_LABELS: Array<[keyof ReturnType<typeof escapes>, string]> = [
  ["js", "JS"],
  ["css", "CSS"],
  ["htmlHex", "HTML"],
  ["htmlDec", "HTML#"],
  ["json", "JSON"],
  ["pythonName", "Py"],
  ["pythonU", "Py\\u"],
  ["swift", "Swift"],
  ["url", "URL"],
];

/** Name a sequence component: ZWJ/VS selectors, else the code point's glyph name. */
export function componentName(cp: number, index: IndexBundle): string {
  if (cp === 0x200d) return "ZWJ";
  if (cp === 0xfe0f) return "VS16";
  if (cp === 0xfe0e) return "VS15";
  const hex = cp.toString(16).toUpperCase().padStart(4, "0");
  return index.byId.get(hex)?.name ?? "";
}

/**
 * Reveal a whitespace glyph "in its negative space": flank the real space char
 * with reference glyphs so its width (or zero-width) reads as the gap between
 * them. A consistent flank (`H`), except a few whose actual use is clearer with
 * a different pair — FIGURE SPACE sits between digits, PUNCTUATION SPACE between
 * periods. Zero-width spaces naturally show their flanks touching.
 */
const SPACE_FLANK: Record<string, string> = {
  "2007": "0", // FIGURE SPACE — as wide as a digit (aligns columns of numbers)
  "2008": ".", // PUNCTUATION SPACE — as wide as a period
};

export function spaceDemo(r: CorpusRecord): string {
  const f = SPACE_FLANK[r.hexseq] ?? "H";
  return `${f}${r.symbol}${f}`;
}

/** Skin-tone variants of a base emoji, derived at render time (design.md field 9). */
export function skinVariants(base: CorpusRecord): string[] {
  if (!base.skinModifiable) return [base.symbol];
  const TONES = [0x1f3fb, 0x1f3fc, 0x1f3fd, 0x1f3fe, 0x1f3ff];
  const cps = [...base.symbol].map((c) => c.codePointAt(0)!);
  const out = [base.symbol];
  for (const tone of TONES) out.push(String.fromCodePoint(cps[0], tone, ...cps.slice(1)));
  return out;
}

const TONE_NAMES: Record<string, string> = {
  "1F3FB": "light skin tone",
  "1F3FC": "medium-light skin tone",
  "1F3FD": "medium skin tone",
  "1F3FE": "medium-dark skin tone",
  "1F3FF": "dark skin tone",
};

/**
 * The record for a hexseq: a corpus row, or — since the corpus collapses skin tones to their
 * base — a toned variant rebuilt from its base, so a word can be taught to 🧘🏻‍♀️ itself.
 * The variant carries its own hexseq (learning identity) and no further tones.
 */
export function recordFor(index: IndexBundle, hexseq: string): CorpusRecord | undefined {
  const row = index.byId.get(hexseq);
  if (row) return row;
  const parts = hexseq.split(" ");
  const tone = parts[1];
  if (!TONE_NAMES[tone]) return undefined;
  const base = index.byId.get([parts[0], ...parts.slice(2)].join(" "));
  if (!base?.skinModifiable) return undefined;
  return tonedRecord(base, tone);
}

/** Every toned variant of a tone-capable base, as records with their own hexseqs. */
export function tonedRecords(base: CorpusRecord): CorpusRecord[] {
  if (!base.skinModifiable) return [];
  return Object.keys(TONE_NAMES).map((tone) => tonedRecord(base, tone));
}

/** The record a pick of `symbol` teaches: the toned variant it names, else `base` itself. */
export function pickedRecord(base: CorpusRecord, symbol: string): CorpusRecord {
  const plain = (s: string) => s.replace(/[\uFE0E\uFE0F]/gu, "");
  return tonedRecords(base).find((r) => plain(r.symbol) === plain(symbol)) ?? base;
}

function tonedRecord(base: CorpusRecord, tone: string): CorpusRecord {
  const [first, ...rest] = base.hexseq.split(" ");
  const cps = [...base.symbol].map((c) => c.codePointAt(0)!);
  return {
    ...base,
    hexseq: [first, tone, ...rest].join(" "),
    symbol: String.fromCodePoint(cps[0], parseInt(tone, 16), ...cps.slice(1)),
    name: `${base.name}: ${TONE_NAMES[tone]}`,
    skinModifiable: false,
  };
}
