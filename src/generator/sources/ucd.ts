/**
 * UCD 17.0 loader: UnicodeData, Blocks, Scripts, DerivedAge, NamesList.
 *
 * Exclusion policy (design.md § Union dataset spec — explicit, no accidental
 * `<...>` drops):
 *  - Unnamed / range-marker entries (`<control>`, `<CJK Ideograph, First>`,
 *    `<Hangul Syllable, …>`, `<… Private Use …>`, surrogate ranges, and every
 *    range-defined ideographic script — Tangut/Nushu/Khitan — which are all
 *    `<…>`-named). Skipping every `<…>` name covers CJK-unified, Hangul
 *    syllables, PUA, and surrogates in one policy line.
 *  - Individually-named CJK unified/compatibility ideographs (the ~1k
 *    `CJK COMPATIBILITY IDEOGRAPH-*` that carry real names) — ideographs need
 *    radical/reading search, out of scope v1.
 *  - General categories Cs (surrogate) and Co (private use) — redundant safety.
 *  - The Variation Selectors, Variation Selectors Supplement, and Tags blocks.
 * Everything else with a name stays.
 */
import { getCached } from "../fetch.js";
import manifest from "../../../source-manifest.json";

type SourceName = keyof typeof manifest.files;
const source = (name: SourceName) => manifest.files[name];

export interface UcdRecord {
  cp: number;
  /** UnicodeData field 1 (the formal name). */
  name: string;
  /** General category, e.g. "Lu", "Sm", "Po". */
  gc: string;
}

interface Range {
  start: number;
  end: number;
  value: string;
}

const EXCLUDED_BLOCKS = new Set([
  "Variation Selectors",
  "Variation Selectors Supplement",
  "Tags",
]);

const CJK_IDEOGRAPH_NAME = /^CJK (UNIFIED|COMPATIBILITY) IDEOGRAPH/;

// ── range file parsing ─────────────────────────────────────────────────────

/** Parse a `START..END ; VALUE` / `CP ; VALUE` UCD range file into ranges. */
function parseRanges(text: string): Range[] {
  const ranges: Range[] = [];
  for (const line of text.split("\n")) {
    const hash = line.indexOf("#");
    const body = (hash >= 0 ? line.slice(0, hash) : line).trim();
    if (body.length === 0) continue;
    const semi = body.indexOf(";");
    if (semi < 0) continue;
    const cps = body.slice(0, semi).trim();
    const value = body.slice(semi + 1).trim();
    if (value.length === 0) continue;
    const dots = cps.indexOf("..");
    if (dots >= 0) {
      const start = parseInt(cps.slice(0, dots), 16);
      const end = parseInt(cps.slice(dots + 2), 16);
      ranges.push({ start, end, value });
    } else {
      const cp = parseInt(cps, 16);
      ranges.push({ start: cp, end: cp, value });
    }
  }
  ranges.sort((a, b) => a.start - b.start);
  return ranges;
}

function makeLookup(ranges: Range[]): (cp: number) => string | undefined {
  return (cp: number) => {
    let lo = 0;
    let hi = ranges.length - 1;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      const r = ranges[mid];
      if (cp < r.start) hi = mid - 1;
      else if (cp > r.end) lo = mid + 1;
      else return r.value;
    }
    return undefined;
  };
}

// ── NamesList annotations ──────────────────────────────────────────────────

export interface NamesListAnnotation {
  aliases: string[];
  notes: string[];
}

function parseNamesList(text: string): Map<number, NamesListAnnotation> {
  const map = new Map<number, NamesListAnnotation>();
  let cur: number | null = null;
  for (const line of text.split("\n")) {
    if (line.length === 0) continue;
    // Block headers / comments (@, @@, @+) — reset so their notes never attach
    // to a preceding character.
    if (line[0] === "@") {
      cur = null;
      continue;
    }
    const charEntry = /^([0-9A-F]{4,6})\t(.+)$/.exec(line);
    if (charEntry) {
      cur = parseInt(charEntry[1], 16);
      continue;
    }
    if (cur === null || line[0] !== "\t") continue;
    const marker = line[1];
    const rest = line.slice(2).trim();
    if (rest.length === 0) continue;
    if (marker === "=" || marker === "*") {
      let ann = map.get(cur);
      if (!ann) {
        ann = { aliases: [], notes: [] };
        map.set(cur, ann);
      }
      if (marker === "=") ann.aliases.push(rest);
      else ann.notes.push(rest);
    }
    // markers x (cross-ref), : (decomposition), # (variation), % skipped
  }
  return map;
}

// ── loader ─────────────────────────────────────────────────────────────────

export interface UcdData {
  records: UcdRecord[];
  blockOf: (cp: number) => string | undefined;
  scriptOf: (cp: number) => string | undefined;
  ageOf: (cp: number) => string | undefined;
  annotationsOf: (cp: number) => NamesListAnnotation | undefined;
  /** Excluded-count breakdown for the build log. */
  excluded: Record<string, number>;
}

export async function loadUcd(): Promise<UcdData> {
  const [unicodeData, blocksTxt, scriptsTxt, ageTxt] = await Promise.all([
    getCached("UnicodeData.txt", source("UnicodeData.txt")),
    getCached("Blocks.txt", source("Blocks.txt")),
    getCached("Scripts.txt", source("Scripts.txt")),
    getCached("DerivedAge.txt", source("DerivedAge.txt")),
  ]);
  const namesList = parseNamesList(
    await getCached("NamesList.txt", source("NamesList.txt")),
  );

  const blockOf = makeLookup(parseRanges(blocksTxt));
  const scriptOf = makeLookup(parseRanges(scriptsTxt));
  const ageOf = makeLookup(parseRanges(ageTxt));

  const records: UcdRecord[] = [];
  const excluded: Record<string, number> = {
    unnamedOrRange: 0,
    cjkIdeograph: 0,
    surrogateOrPua: 0,
    excludedBlock: 0,
  };

  for (const line of unicodeData.split("\n")) {
    if (line.length === 0) continue;
    const f = line.split(";");
    if (f.length < 3) continue;
    const cp = parseInt(f[0], 16);
    const name = f[1];
    const gc = f[2];
    if (name.startsWith("<")) {
      excluded.unnamedOrRange++;
      continue;
    }
    if (CJK_IDEOGRAPH_NAME.test(name)) {
      excluded.cjkIdeograph++;
      continue;
    }
    if (gc === "Cs" || gc === "Co") {
      excluded.surrogateOrPua++;
      continue;
    }
    const block = blockOf(cp);
    if (block && EXCLUDED_BLOCKS.has(block)) {
      excluded.excludedBlock++;
      continue;
    }
    records.push({ cp, name, gc });
  }

  return {
    records,
    blockOf,
    scriptOf,
    ageOf,
    annotationsOf: (cp) => namesList.get(cp),
    excluded,
  };
}
