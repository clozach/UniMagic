/**
 * What the Tinycast grid shows: browse sections, the scope dropdown, and each tile's text.
 * Pure — no React, no Node — so the vitest suite drives it directly.
 */
import {
  CURATED_SETS,
  frequentlyUsed,
  type CorpusRecord,
  type CuratedSet,
  type IndexBundle,
  type SearchHit,
  type UnimagicData,
} from "../../core";
import { recordFor, spaceDemo } from "../../core/glyphs";
import { toned, type ToneId } from "./tones";

export const FREQUENTLY_USED_N = 25;
/** Tiles one screen renders; the bridge to Swift re-sends every tile on each commit. */
export const TILE_CAP = 4000;

/** Practical sets first, as in Glyphfinder; the 37k "Other Glyphs" are browsed by block. */
const BROWSABLE_SETS: readonly CuratedSet[] = CURATED_SETS.filter((set) => set !== "Other Glyphs");

export type Scope =
  | { kind: "browse" }
  | { kind: "set"; set: CuratedSet }
  | { kind: "block"; block: string };

export interface ScopeChoice {
  id: string;
  title: string;
}

/** Hexseqs this Mac cannot draw (coverage.ts); empty until the first scan finishes. */
export type Missing = ReadonlySet<string>;

/** Spaces draw nothing by design, so they stay even when a font scan flags them. */
export function drawable(record: CorpusRecord, missing: Missing): boolean {
  return record.set === "Spaces" || !missing.has(record.hexseq);
}

export interface GlyphSection {
  title: string;
  records: CorpusRecord[];
}

export function scopeId(scope: Scope): string {
  switch (scope.kind) {
    case "browse":
      return "browse";
    case "set":
      return `set:${scope.set}`;
    case "block":
      return `block:${scope.block}`;
  }
}

export function parseScope(id: string): Scope {
  if (id.startsWith("set:")) {
    const set = id.slice(4) as CuratedSet;
    if (BROWSABLE_SETS.includes(set)) return { kind: "set", set };
  }
  if (id.startsWith("block:")) return { kind: "block", block: id.slice(6) };
  return { kind: "browse" };
}

function count(n: number): string {
  return n.toLocaleString("en-US");
}

/** Every set and every block of the long tail, so each glyph is reachable without typing. */
export function scopeChoices(
  index: IndexBundle,
  missing: Missing,
): { sets: ScopeChoice[]; blocks: ScopeChoice[] } {
  const perSet = new Map<string, number>();
  const perBlock = new Map<string, number>();
  for (const r of index.byId.values()) {
    if (!drawable(r, missing)) continue;
    if (r.set) perSet.set(r.set, (perSet.get(r.set) ?? 0) + 1);
    if (r.set === "Other Glyphs" && r.block) perBlock.set(r.block, (perBlock.get(r.block) ?? 0) + 1);
  }
  const sets = BROWSABLE_SETS.map((set) => ({
    id: scopeId({ kind: "set", set }),
    title: `${set} (${count(perSet.get(set) ?? 0)})`,
  }));
  const blocks = [...perBlock.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([block, n]) => ({ id: scopeId({ kind: "block", block }), title: `${block} (${count(n)})` }));
  return { sets, blocks };
}

export function inScope(record: CorpusRecord, scope: Scope): boolean {
  switch (scope.kind) {
    case "browse":
      return true;
    case "set":
      return record.set === scope.set;
    case "block":
      return record.set === "Other Glyphs" && record.block === scope.block;
  }
}

function byOrder(records: Iterable<CorpusRecord>): CorpusRecord[] {
  return [...records].sort((a, b) => a.order - b.order);
}

/** The empty-query grid. `usage` is the launch snapshot, so it never reshuffles mid-session. */
export function browseSections(
  index: IndexBundle,
  usage: UnimagicData,
  scope: Scope,
  missing: Missing,
): GlyphSection[] {
  const all = [...index.byId.values()].filter((r) => drawable(r, missing));
  switch (scope.kind) {
    case "browse": {
      const frequent = frequentlyUsed(usage, FREQUENTLY_USED_N)
        .map((hexseq) => recordFor(index, hexseq))
        .filter((r): r is CorpusRecord => !!r && drawable(r, missing));
      const sections: GlyphSection[] = [{ title: "Frequently used", records: frequent }];
      for (const set of BROWSABLE_SETS) {
        sections.push({ title: set, records: byOrder(all.filter((r) => r.set === set)) });
      }
      return sections.filter((section) => section.records.length > 0);
    }
    case "set":
    case "block": {
      const title = scope.kind === "set" ? scope.set : scope.block;
      return [{ title, records: byOrder(all.filter((r) => inScope(r, scope))) }];
    }
  }
}

export function resultSections(hits: SearchHit[], scope: Scope, missing: Missing): GlyphSection[] {
  const records = hits
    .map((hit) => hit.record)
    .filter((r) => inScope(r, scope) && drawable(r, missing));
  const where = scope.kind === "browse" ? "" : ` in ${scope.kind === "set" ? scope.set : scope.block}`;
  const noun = records.length === 1 ? "match" : "matches";
  return [{ title: `${count(records.length)} ${noun}${where}`, records }];
}

/** Trim sections to the tile cap, saying how much was left out rather than dropping it silently. */
export function capSections(sections: GlyphSection[], cap = TILE_CAP): GlyphSection[] {
  let left = cap;
  const out: GlyphSection[] = [];
  for (const section of sections) {
    if (left <= 0) break;
    const shown = section.records.slice(0, left);
    left -= shown.length;
    const hidden = section.records.length - shown.length;
    out.push({
      title: hidden > 0 ? `${section.title} — first ${count(shown.length)}; type to narrow` : section.title,
      records: shown,
    });
  }
  return out;
}

const DOTTED_CIRCLE = "◌";

/** History is already fetched in bounded pages; render every fetched event. */
export function windowSections(sections: GlyphSection[], paging: { kind: "history" } | { kind: "browse"; limit: number }): GlyphSection[] {
  if (paging.kind === "history") return sections;
  let remaining = paging.limit;
  return sections.map(section => {
    const records = section.records.slice(0, Math.max(0, remaining));
    remaining -= records.length;
    return { ...section, records };
  });
}

/** A tile draws spaces between flanks, marks on a dotted circle, and emoji in the default tone. */
export function tileText(record: CorpusRecord & { browse?: { exact: boolean } }, tone: ToneId = "none"): string {
  if (record.set === "Spaces") return spaceDemo(record);
  if (/^\p{M}/u.test(record.symbol)) return DOTTED_CIRCLE + record.symbol;
  return record.browse?.exact ? record.symbol : toned(record, tone);
}
