/** Build compact browse definitions without editing the canonical corpus. */
import { createHash } from "node:crypto";
import type { Corpus, CorpusRecord } from "../core/schema";
import { CURATED_SETS } from "../core/schema";
import type { BrowseCatalogue, BrowseCategoryDefinition, BrowseOccurrence, CategoryExemplar } from "../core/browse-schema";
import { compareCategories, compareScalarSequences, resolveCategoryEntries, unicodeScalars } from "../core/browse-catalogue";

interface ReferenceCategory {
  id: string; name: string;
  index_icon: { font_character: string };
  observed: { glyph: string; accessibility_name: string | null }[];
  source_positions: { glyph: string }[];
}
export interface BrowseReference { font_sha256: string; categories: ReferenceCategory[] }
export interface BrowseSeed {
  emojiExemplar: string;
  legacyRanges: { id: string; title: string; symbol: string; ranges: [number, number][] }[];
  setExemplars: Record<string, string>;
}
const neutral = (symbol: string) => symbol.replace(/[\uFE0E\uFE0F]/gu, "");
const glyphID = (symbol: string) => unicodeScalars(symbol).map(cp => cp.toString(16).toUpperCase().padStart(4, "0")).join(" ");
const lowest = (entries: BrowseOccurrence[]) => entries.map(e => unicodeScalars(e.symbol)).sort(compareScalarSequences)[0] ?? [];

export function buildBrowseCatalogue(corpus: Corpus, reference: BrowseReference, seed: BrowseSeed, sourceSHA256: string, blockStarts: Record<string, number>): BrowseCatalogue {
  const exact = new Map(corpus.records.map(r => [r.symbol, r]));
  const presentation = new Map<string, CorpusRecord>();
  for (const r of corpus.records) if (!presentation.has(neutral(r.symbol))) presentation.set(neutral(r.symbol), r);
  const supplements = new Map<string, { glyphID: string; symbol: string; name: string }>();
  for (const c of reference.categories) for (const e of c.observed) {
    if (!exact.has(e.glyph) && !presentation.has(neutral(e.glyph))) {
      const id = glyphID(e.glyph);
      if (corpus.records.some(r => r.hexseq === id)) throw Error(`Supplement would overwrite ${id}`);
      const name = e.accessibility_name ?? Array.from(e.glyph, scalar => exact.get(scalar)?.name ?? `U+${glyphID(scalar)}`).join(" + ");
      supplements.set(id, { glyphID: id, symbol: e.glyph, name });
    }
  }
  const supplementBySymbol = new Map([...supplements.values()].map(s => [s.symbol, s]));
  const resolve = (symbol: string) => exact.get(symbol)?.hexseq ?? presentation.get(neutral(symbol))?.hexseq ?? supplementBySymbol.get(symbol)?.glyphID;
  const categories: BrowseCategoryDefinition[] = [];
  const rule = (id: string, title: string, source: BrowseCategoryDefinition["source"], exemplar: CategoryExemplar, defaultEnabled = true) => {
    const c: BrowseCategoryDefinition = { id, title, source, defaultEnabled, defaultExemplar: exemplar, orderKey: [], sample: [], membership: { kind: "source-rule" }, memberCount: 0 };
    const entries = resolveCategoryEntries(c, corpus.records);
    c.sample = entries.slice(0, 28);
    c.memberCount = entries.length;
    c.orderKey = source.kind === "unicode-block" ? [source.startScalar] : lowest(entries);
    categories.push(c);
  };
  rule("utility:recents", "Recents", { kind: "utility", utility: "recents" }, { kind: "unicode", symbol: "◷" });
  rule("utility:frequent", "Frequently used", { kind: "utility", utility: "frequent" }, { kind: "unicode", symbol: "◴" });
  for (const set of CURATED_SETS) rule(`set:${set}`, set === "Arrows" ? "Arrows — curated" : set,
    { kind: "curated-set", set }, { kind: set === "Emojis" ? "emoji" : "unicode", symbol: set === "Emojis" ? seed.emojiExemplar : seed.setExemplars[set] });
  for (const c of seed.legacyRanges) rule(c.id, c.title, { kind: "legacy-ranges", ranges: c.ranges }, { kind: "unicode", symbol: c.symbol });
  for (const c of reference.categories) {
    const id = `unichar:${c.id}`;
    const sample: BrowseOccurrence[] = c.observed.map((e, position) => ({ occurrenceID: `${id}:sample:${position}`, glyphID: resolve(e.glyph)!, symbol: e.glyph,
      ...(e.accessibility_name ? { name: e.accessibility_name } : {}) }));
    const entries: BrowseOccurrence[] = [...sample];
    const seen = new Set(entries.map(e => e.symbol));
    const unresolved = new Set<string>();
    const additions: BrowseOccurrence[] = [];
    c.source_positions.forEach((e, position) => {
      if (!e.glyph || seen.has(e.glyph)) return;
      const recordID = resolve(e.glyph);
      if (!recordID) { unresolved.add(e.glyph); return; }
      seen.add(e.glyph);
      additions.push({ occurrenceID: `${id}:source:${position}`, glyphID: recordID, symbol: e.glyph });
    });
    additions.sort((a, b) => compareScalarSequences(unicodeScalars(a.symbol), unicodeScalars(b.symbol)));
    entries.push(...additions);
    categories.push({ id, title: c.name === "Arrows" ? "Arrows — UniChar" : c.name,
      source: { kind: "unichar-observed", referenceID: c.id }, defaultEnabled: true,
      defaultExemplar: { kind: "custom-font", symbol: c.index_icon.font_character, font: "UniCharCategories" },
      orderKey: lowest(entries), sample, membership: { kind: "explicit", entries }, memberCount: entries.length,
      ...(unresolved.size ? { unresolvedSourceSymbols: [...unresolved] } : {}) });
  }
  const blocks = [...new Set(corpus.records.filter(r => r.set === "Other Glyphs").map(r => r.block).filter((b): b is string => !!b))];
  for (const block of blocks) {
    if (blockStarts[block] === undefined) throw Error(`Missing Unicode block start: ${block}`);
    const representative = corpus.records.find(r => r.set === "Other Glyphs" && r.block === block)!;
    rule(`block:${block}`, block, { kind: "unicode-block", block, startScalar: blockStarts[block] }, { kind: "unicode", symbol: representative.symbol }, false);
  }
  const utilities = categories.filter(c => c.source.kind === "utility");
  const ordinary = categories.filter(c => c.source.kind !== "utility").sort(compareCategories);
  const counts = { canonical: corpus.records.length, supplements: supplements.size, collections: ordinary.length - blocks.length,
    blocks: blocks.length, observedSampleOccurrences: reference.categories.reduce((n, c) => n + c.observed.length, 0) };
  const content = { corpusBuild: corpus.build, sourceSHA256, categories: [...utilities, ...ordinary], supplements: [...supplements.values()], counts };
  return { schemaVersion: 2, revision: createHash("sha256").update(JSON.stringify(content)).digest("hex"),
    font: { file: "UniCharCategories.ttf", sha256: reference.font_sha256 }, ...content };
}
