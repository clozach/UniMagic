/** Desktop projection: exact source occurrences, preferences and independent history. */
import rawCatalogue from "../../../ios/Resources/BrowseInventory.json";
import { compareCategories, defaultBrowsePreferences, resolveCategoryEntries } from "../../core/browse-catalogue";
import type { BrowseCatalogue, BrowseCategoryDefinition, BrowseOrigin, BrowsePreferences, CategoryExemplar } from "../../core/browse-schema";
import type { Corpus, CorpusRecord, UsageEntry } from "../../core/schema";
import type { IndexBundle } from "../../core/search";
import { recordFor } from "../../core/glyphs";
import type { HistoryEvent, HistoryHost, HistoryPage } from "../../core/history-schema";
import { createPersonalizationStore, type PersonalizationProvider, type PersonalizationStore } from "../../core/personalization-store";

export const catalogue = rawCatalogue as unknown as BrowseCatalogue;
export const categoryByID = new Map(catalogue.categories.map(c => [c.id, c]));
const titleCounts = new Map<string, number>();
for (const category of catalogue.categories) titleCounts.set(category.title, (titleCounts.get(category.title) ?? 0) + 1);
/** Canonical titles remain unchanged; overlapping lenses get a human source cue. */
export function categorySourceLabel(category: BrowseCategoryDefinition): string | undefined {
  if ((titleCounts.get(category.title) ?? 0) < 2) return;
  switch (category.source.kind) {
    case "unichar-observed": return "UniChar collection";
    case "unicode-block": return "Unicode block";
    case "legacy-ranges": return "Restored collection";
    case "curated-set": return "Curated set";
    case "utility": return undefined;
  }
}
export function categoryDisplayTitle(category: BrowseCategoryDefinition): string {
  const source = categorySourceLabel(category); return source ? `${category.title} — ${source}` : category.title;
}
export const HISTORY_PAGE_SIZE = 100;
/** View identity is independent of the corpus key: repeats and VS are retained. */
export interface DesktopRecord extends CorpusRecord {
  browse?: { key: string; origin?: BrowseOrigin; exact: boolean; history?: HistoryEvent };
}
export const viewKey = (r: DesktopRecord): string => r.browse?.key ?? r.hexseq;
export function historyDescription(record: DesktopRecord): string | undefined {
  const event = record.browse?.history; if (!event) return;
  if (event.provenance.kind === "legacy-aggregate") return `Earlier usage: ${event.provenance.count} picks; individual dates and sequence unavailable`;
  if (event.provenance.kind === "snapshot-import") return `Screenshot snapshot, position ${event.provenance.position + 1}; date/order unknown`;
  return event.occurredAt === null ? "Date unknown" : new Date(event.occurredAt).toLocaleString();
}

/** Supplements are appended at runtime; canonical records/primary set stay untouched. */
export function desktopCorpus(corpus: Corpus): Corpus {
  const known = new Set(corpus.records.map(r => r.hexseq));
  const additions = catalogue.supplements.filter(s => !known.has(s.glyphID));
  return { ...corpus, records: [...corpus.records, ...additions.map((s, i): CorpusRecord => ({
    hexseq: s.glyphID, symbol: s.symbol, name: s.name, order: corpus.records.length + i,
    entities: [], keywords: [], signs: [], twins: [], related: [],
  }))] };
}

export function historyRecord(event: HistoryEvent, index: IndexBundle): DesktopRecord {
  const base = recordFor(index, event.glyphID) ?? {
    hexseq: event.glyphID, symbol: event.symbol, name: event.symbol, order: -1,
    entities: [], keywords: [], signs: [], twins: [], related: [],
  };
  return { ...base, symbol: event.symbol, browse: { key: event.eventID, origin: event.origin, exact: true, history: event } };
}

export class DesktopBrowse {
  readonly store: PersonalizationStore;
  preferences: BrowsePreferences = defaultBrowsePreferences(catalogue);
  private listeners = new Set<() => void>();
  private entries = new Map<string, DesktopRecord[]>();
  private contextIndex: Map<string, { category: BrowseCategoryDefinition; record: DesktopRecord }[]> | null = null;
  private canonical: CorpusRecord[];
  constructor(readonly index: IndexBundle, provider: PersonalizationProvider) {
    this.store = createPersonalizationStore(provider, catalogue.revision);
    this.canonical = [...index.byId.values()].filter(r => r.order < catalogue.counts.canonical);
  }
  subscribe = (f: () => void): (() => void) => { this.listeners.add(f); return () => this.listeners.delete(f); };
  private emit(): void { for (const f of this.listeners) f(); }
  async refresh(): Promise<void> { this.preferences = await this.store.readPreferences(); this.emit(); }
  /** New libraries start empty; private snapshot imports are not product defaults. */
  async initialize(): Promise<void> { await this.refresh(); }
  async importLegacyUsage(usage: UsageEntry[]): Promise<void> {
    const importID = "desktop-shared-legacy-usage-v1";
    if (this.preferences.appliedMigrations.includes(importID)) return;
    const events = usage.flatMap((entry): HistoryEvent[] => {
      const record = this.index.byId.get(entry.hexseq);
      return record ? [{ eventID: `${importID}:${entry.hexseq}`, glyphID: entry.hexseq, symbol: record.symbol, occurredAt: null,
        provenance: { kind: "legacy-aggregate", source: "Desktop shared data.json usage before full history; individual picks and dates unavailable", count: entry.count } }] : [];
    });
    await this.store.importHistory({ importID, events });
    this.preferences = await this.store.applyCategoryDefaults(importID, []); this.emit();
  }
  categories(enabledOnly = false): BrowseCategoryDefinition[] {
    return catalogue.categories.filter(c => !enabledOnly || (this.preferences.categoryVisibility[c.id] ?? c.defaultEnabled))
      .sort((a, b) => {
        const utility = (c: BrowseCategoryDefinition) => c.source.kind === "utility";
        return Number(utility(b)) - Number(utility(a)) || compareCategories(a, b);
      });
  }
  enabled(id: string): boolean { return this.preferences.categoryVisibility[id] ?? categoryByID.get(id)?.defaultEnabled ?? false; }
  exemplar(id: string): CategoryExemplar { return this.preferences.exemplarOverrides[id] ?? categoryByID.get(id)!.defaultExemplar; }
  async setEnabled(id: string, enabled: boolean): Promise<void> { this.preferences = await this.store.setCategoryEnabled(id, enabled); this.emit(); }
  async setExemplar(id: string, symbol: string | null): Promise<void> {
    this.preferences = await this.store.setCategoryExemplar(id, symbol === null ? null : { kind: "unicode", symbol }); this.emit();
  }
  members(id: string): DesktopRecord[] {
    const cached = this.entries.get(id); if (cached) return cached;
    const category = categoryByID.get(id); if (!category) return [];
    const entries = resolveCategoryEntries(category, this.canonical).flatMap(occurrence => {
      const base = this.index.byId.get(occurrence.glyphID);
      return base ? [{ ...base, symbol: occurrence.symbol, browse: { key: occurrence.occurrenceID, origin: { categoryID: id, occurrenceID: occurrence.occurrenceID }, exact: true } }] : [];
    });
    this.entries.set(id, entries); return entries;
  }
  contexts(record: DesktopRecord): { category: BrowseCategoryDefinition; record: DesktopRecord }[] {
    if (!this.contextIndex) {
      this.contextIndex = new Map();
      for (const category of this.categories()) for (const member of this.members(category.id)) {
        const entries = this.contextIndex.get(member.hexseq) ?? [];
        entries.push({ category, record: member }); this.contextIndex.set(member.hexseq, entries);
      }
    }
    const groups = new Map<string, { category: BrowseCategoryDefinition; record: DesktopRecord }[]>();
    for (const context of this.contextIndex.get(record.hexseq) ?? []) {
      const group = groups.get(context.category.id) ?? []; group.push(context); groups.set(context.category.id, group);
    }
    return [...groups.values()].map(group => group.find(c => c.record.browse?.origin?.occurrenceID === record.browse?.origin?.occurrenceID)
      ?? group.find(c => c.record.symbol === record.symbol) ?? group[0]);
  }
  history(cursor?: string): Promise<HistoryPage> { return this.store.readHistoryPage({ cursor, limit: HISTORY_PAGE_SIZE }); }
  async picked(record: DesktopRecord, symbol: string, host: HistoryHost, action: "copy" | "insert"): Promise<void> {
    await this.store.appendHistoryEvent({ eventID: `${host}:${Date.now().toString(36)}:${Math.random().toString(36).slice(2)}`,
      glyphID: record.hexseq, symbol, occurredAt: Date.now(), provenance: { kind: "pick", host, action }, origin: record.browse?.origin });
    this.emit();
  }
}
