/** Pure catalogue operations. Storage and rendering belong to each host. */
import type { CorpusRecord } from "./schema";
import type { BrowseCatalogue, BrowseCategoryDefinition, BrowseOccurrence, BrowsePreferences } from "./browse-schema";

export const unicodeScalars = (symbol: string): number[] => Array.from(symbol, c => c.codePointAt(0)!);

export function compareScalarSequences(a: readonly number[], b: readonly number[]): number {
  for (let i = 0; i < Math.min(a.length, b.length); i++) {
    if (a[i] !== b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}

export function compareCategories(a: BrowseCategoryDefinition, b: BrowseCategoryDefinition): number {
  if (a.id === "set:Emojis") return b.id === a.id ? 0 : -1;
  if (b.id === "set:Emojis") return 1;
  return compareScalarSequences(a.orderKey, b.orderKey) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
}

export function recordBelongsToCategory(record: CorpusRecord, category: BrowseCategoryDefinition): boolean {
  if (category.membership.kind === "explicit") return category.membership.entries.some(e => e.glyphID === record.hexseq);
  switch (category.source.kind) {
    case "curated-set": return record.set === category.source.set;
    case "unicode-block": return record.set === "Other Glyphs" && record.block === category.source.block;
    case "legacy-ranges": return category.source.ranges.some(([lo, hi]) => {
      const cp = record.symbol.codePointAt(0)!;
      return cp >= lo && cp <= hi;
    });
    default: return false;
  }
}

/** Corpus order is retained; explicit source samples/duplicate strings are untouched. */
export function resolveCategoryEntries(category: BrowseCategoryDefinition, records: readonly CorpusRecord[]): BrowseOccurrence[] {
  if (category.membership.kind === "explicit") return category.membership.entries;
  if (category.source.kind === "utility") return [];
  const members = records.filter(record => recordBelongsToCategory(record, category));
  // Preserve the former Music landing order: common notes, modern notation, rest.
  if (category.id === "legacy:Music") {
    const rank = (r: CorpusRecord) => { const cp = r.symbol.codePointAt(0)!; return cp >= 0x2669 && cp <= 0x266F ? 0 : cp >= 0x1D100 && cp <= 0x1D1FF ? 1 : 2; };
    members.sort((a, b) => rank(a) - rank(b) || a.order - b.order);
  }
  return members.map(r => ({ occurrenceID: `${category.id}:full:${r.hexseq}`, glyphID: r.hexseq, symbol: r.symbol, name: r.name }));
}

export function enabledCategories(catalogue: BrowseCatalogue, preferences: BrowsePreferences): BrowseCategoryDefinition[] {
  return catalogue.categories.filter(category => preferences.categoryVisibility[category.id] ?? category.defaultEnabled);
}

export function defaultBrowsePreferences(catalogue: BrowseCatalogue): BrowsePreferences {
  return { schemaVersion: 1, catalogueRevision: catalogue.revision, categoryVisibility: {}, exemplarOverrides: {}, appliedMigrations: [] };
}
