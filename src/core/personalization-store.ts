import type { BrowsePreferenceAdapter, BrowsePreferences, CategoryExemplar } from "./browse-schema";
import type { HistoryAdapter, HistoryDocument, HistoryEvent, HistoryImport, HistoryPage } from "./history-schema";

export type PersonalizationAccess = "shared-read-write" | "shared-read-only" | "local";
export interface PersonalizationProvider {
  readonly access: PersonalizationAccess;
  read(): Promise<unknown>;
  /** Cross-process exclusive transaction; re-read inside the lock, then replace. */
  transaction<T>(change: (current: unknown) => { document: unknown; result: T }): Promise<T>;
}
export class PersonalizationDataError extends Error {}
export class PersonalizationReadOnlyError extends Error {}
type Root = Record<string, unknown>;
type Document = { root: Root; preferences: BrowsePreferences; history: HistoryDocument };

const object = (x: unknown): x is Root => x !== null && typeof x === "object" && !Array.isArray(x);
const text = (x: unknown): x is string => typeof x === "string" && x.length > 0;
const strings = (x: unknown): x is string[] => Array.isArray(x) && x.every(text);
function fail(message: string): never { throw new PersonalizationDataError(message + "; existing data preserved"); }

export function validateExemplar(x: unknown): asserts x is CategoryExemplar {
  if (!object(x) || !text(x.symbol) || !["unicode", "emoji", "custom-font"].includes(String(x.kind)) ||
      (x.kind === "custom-font" && x.font !== "UniCharCategories")) fail("Invalid category exemplar");
}
export function validateHistoryEvent(x: unknown): asserts x is HistoryEvent {
  if (!object(x) || !text(x.eventID) || !text(x.glyphID) || !text(x.symbol) ||
      !(x.occurredAt === null || (typeof x.occurredAt === "number" && Number.isFinite(x.occurredAt))) || !object(x.provenance)) fail("Invalid history event");
  const p = x.provenance;
  if (p.kind === "pick") {
    if (!["native-app", "native-keyboard", "tinycast", "obsidian"].includes(String(p.host)) || !["copy", "insert"].includes(String(p.action))) fail("Invalid pick provenance");
  } else if (p.kind === "snapshot-import") {
    if (!text(p.importID) || !text(p.source) || !Number.isInteger(p.position) || Number(p.position) < 0) fail("Invalid snapshot provenance");
  } else if (p.kind === "legacy-aggregate") {
    if (!text(p.source) || !Number.isInteger(p.count) || Number(p.count) < 0) fail("Invalid aggregate provenance");
  } else fail("Unknown history provenance");
  if (x.origin !== undefined && (!object(x.origin) || !text(x.origin.categoryID) || !text(x.origin.occurrenceID))) fail("Invalid browse origin");
}

/** Learning/usage remain untouched; aggregates are not fabricated pick events. */
export function parsePersonalization(raw: unknown, revision: string): Document {
  if (!object(raw)) fail("Personalization root is not an object");
  if (raw.personalizationVersion !== undefined && raw.personalizationVersion !== 1) fail("Unsupported personalization version");
  const p = raw.browsePreferences ?? { schemaVersion: 1, catalogueRevision: revision, categoryVisibility: {}, exemplarOverrides: {}, appliedMigrations: [] };
  if (!object(p) || p.schemaVersion !== 1 || typeof p.catalogueRevision !== "string" || !object(p.categoryVisibility) ||
      !Object.values(p.categoryVisibility).every(x => typeof x === "boolean") || !object(p.exemplarOverrides) || !strings(p.appliedMigrations)) fail("Invalid or unsupported browse preferences");
  Object.values(p.exemplarOverrides).forEach(validateExemplar);
  const h = raw.history ?? { schemaVersion: 1, events: [], appliedImports: [] };
  if (!object(h) || h.schemaVersion !== 1 || !Array.isArray(h.events) || !strings(h.appliedImports)) fail("Invalid or unsupported history document");
  h.events.forEach(validateHistoryEvent);
  if (new Set(h.events.map(x => x.eventID)).size !== h.events.length) fail("Duplicate stored history event IDs");
  return { root: raw, preferences: p as unknown as BrowsePreferences, history: h as unknown as HistoryDocument };
}
function serialized(d: Document): Root { return { ...d.root, personalizationVersion: 1, browsePreferences: d.preferences, history: d.history }; }
function chronological(events: HistoryEvent[]): HistoryEvent[] {
  return events.sort((a, b) => a.occurredAt === null ? (b.occurredAt === null ? 0 : 1) : b.occurredAt === null ? -1 : b.occurredAt - a.occurredAt);
}
function mergeEvents(current: HistoryEvent[], additions: HistoryEvent[]): { events: HistoryEvent[]; imported: number } {
  const seen = new Set(current.map(x => x.eventID)); const missing: HistoryEvent[] = [];
  for (const event of additions) {
    validateHistoryEvent(event);
    if (!seen.has(event.eventID)) { seen.add(event.eventID); missing.push(event); }
  }
  return { events: chronological([...current, ...missing]), imported: missing.length };
}
function orderSnapshot(events: HistoryEvent[], importID: string): HistoryEvent[] {
  const isMember = (e: HistoryEvent) => e.occurredAt === null && e.provenance.kind === "snapshot-import" && e.provenance.importID === importID;
  const first = events.findIndex(isMember);
  if (first < 0) return events;
  const members = events.filter(isMember).sort((a, b) =>
    (a.provenance.kind === "snapshot-import" ? a.provenance.position : 0) - (b.provenance.kind === "snapshot-import" ? b.provenance.position : 0));
  const remaining = events.filter(e => !isMember(e));
  remaining.splice(first, 0, ...members);
  return remaining;
}

export interface PersonalizationStore extends BrowsePreferenceAdapter, HistoryAdapter {
  readonly access: PersonalizationAccess;
  mergeHistoryEvents(events: HistoryEvent[]): Promise<number>;
}
export function createPersonalizationStore(provider: PersonalizationProvider, revision: string): PersonalizationStore {
  const read = async () => parsePersonalization(await provider.read(), revision);
  async function mutate<T>(change: (d: Document) => T): Promise<T> {
    if (provider.access === "shared-read-only") throw new PersonalizationReadOnlyError("Shared personalization is read-only; choose a writable store explicitly");
    return provider.transaction(raw => {
      const d = parsePersonalization(raw, revision);
      const result = change(d);
      return { document: serialized(d), result };
    });
  }
  async function preferences(change: (p: BrowsePreferences) => void): Promise<BrowsePreferences> {
    return mutate(d => { change(d.preferences); d.preferences.catalogueRevision = revision; return d.preferences; });
  }
  return {
    access: provider.access,
    async readPreferences() { return (await read()).preferences; },
    setCategoryEnabled(categoryID, enabled) {
      if (!text(categoryID) || typeof enabled !== "boolean") return Promise.reject(new PersonalizationDataError("Invalid category visibility"));
      return preferences(p => { p.categoryVisibility = { ...p.categoryVisibility, [categoryID]: enabled }; });
    },
    setCategoryExemplar(categoryID, exemplar) {
      if (!text(categoryID)) return Promise.reject(new PersonalizationDataError("Invalid category ID"));
      if (exemplar !== null) validateExemplar(exemplar);
      return preferences(p => { if (exemplar === null) delete p.exemplarOverrides[categoryID]; else p.exemplarOverrides = { ...p.exemplarOverrides, [categoryID]: exemplar }; });
    },
    applyCategoryDefaults(migrationID, categoryIDs) {
      if (!text(migrationID) || !categoryIDs.every(text)) return Promise.reject(new PersonalizationDataError("Invalid migration"));
      return preferences(p => {
        if (p.appliedMigrations.includes(migrationID)) return;
        for (const id of categoryIDs) if (!Object.prototype.hasOwnProperty.call(p.categoryVisibility, id)) p.categoryVisibility = { ...p.categoryVisibility, [id]: true };
        p.appliedMigrations.push(migrationID);
      });
    },
    async readHistoryPage({ cursor, limit }): Promise<HistoryPage> {
      if (!Number.isInteger(limit) || limit < 1 || limit > 500) fail("History page size must be 1–500");
      const events = (await read()).history.events;
      const index = cursor === undefined ? -1 : events.findIndex(x => x.eventID === cursor);
      if (cursor !== undefined && index < 0) fail("Invalid history cursor");
      const page = events.slice(index + 1, index + 1 + limit);
      return { events: page, nextCursor: index + 1 + limit < events.length ? page[page.length - 1].eventID : null };
    },
    async appendHistoryEvent(event) {
      validateHistoryEvent(event);
      await mutate(d => {
        if (!d.history.events.some(x => x.eventID === event.eventID)) d.history.events = chronological([event, ...d.history.events]);
      });
    },
    async importHistory(snapshot: HistoryImport) {
      if (!text(snapshot.importID)) fail("Invalid import ID");
      snapshot.events.forEach(validateHistoryEvent);
      return mutate(d => {
        const prior = d.history.appliedImports.includes(snapshot.importID);
        const merged = mergeEvents(d.history.events, snapshot.events); d.history.events = orderSnapshot(merged.events, snapshot.importID);
        if (!prior) d.history.appliedImports.push(snapshot.importID);
        return { imported: merged.imported, alreadyApplied: prior && merged.imported === 0 };
      });
    },
    mergeHistoryEvents(events) {
      return mutate(d => { const merged = mergeEvents(d.history.events, events); d.history.events = merged.events; return merged.imported; });
    },
  };
}
