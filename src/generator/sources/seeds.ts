/**
 * Glyphfinder seed layers (tracked, self-contained under ../seeds/, upstream
 * pinned c941077). All three are provenance inputs whose tokens are tagged on
 * merge (design.md merge recipe step 3):
 *  - gf-tag-delta.json  : human sheet-tag layer → keywords `glyphfinder-sheet`
 *  - gf-sets.json       : curated non-emoji `set` column
 *  - gf-entity-lookup.js: HTML entity names + hand-authored tags → `entity-lookup`
 */
import { createRequire } from "node:module";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { cpToHex, normalizeHexseq } from "../normalize.js";
import type { CuratedSet } from "../../core/schema.js";

const require = createRequire(import.meta.url);

/** Seeds live one level up from the generator's cwd (projects/unimagic/seeds). */
const localSeeds = resolve(process.cwd(), "seeds");
const SEEDS_DIR = existsSync(localSeeds) ? localSeeds : resolve(process.cwd(), "..", "seeds");

export interface TagDelta {
  /** normalized hexseq → raw tag tokens (words + signs, unpartitioned) */
  rows: Map<string, string[]>;
}

export interface SetRows {
  /** normalized hexseq → curated set name */
  rows: Map<string, CuratedSet>;
}

export interface EntityRow {
  hexseq: string;
  entity: string;
  tags: string[];
}

export interface SeedData {
  tagDelta: TagDelta;
  sets: SetRows;
  entities: EntityRow[];
}

function loadTagDelta(): TagDelta {
  const raw = JSON.parse(
    readFileSync(resolve(SEEDS_DIR, "gf-tag-delta.json"), "utf8"),
  ) as { delta: Record<string, string[]> };
  const rows = new Map<string, string[]>();
  for (const [key, tags] of Object.entries(raw.delta)) {
    rows.set(normalizeHexseq(key), tags);
  }
  return { rows };
}

function loadSets(): SetRows {
  const raw = JSON.parse(
    readFileSync(resolve(SEEDS_DIR, "gf-sets.json"), "utf8"),
  ) as { sets: Record<string, string> };
  const rows = new Map<string, CuratedSet>();
  for (const [key, set] of Object.entries(raw.sets)) {
    rows.set(normalizeHexseq(key), set as CuratedSet);
  }
  return { rows };
}

function loadEntities(): EntityRow[] {
  const arr = require(resolve(SEEDS_DIR, "gf-entity-lookup.js")) as {
    name: string;
    code: number;
    tags: string[];
  }[];
  return arr.map((r) => ({
    hexseq: cpToHex(r.code),
    entity: r.name,
    tags: r.tags ?? [],
  }));
}

export function loadSeeds(): SeedData {
  return {
    tagDelta: loadTagDelta(),
    sets: loadSets(),
    entities: loadEntities(),
  };
}
