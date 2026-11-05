/**
 * Coverage assertions (design.md golden, honestly adapted). Exported so a
 * vitest test can import and call `runCoverage` on a built corpus.
 *
 * Checked here:
 *  - Seed-key subset: every hexseq in gf-tag-delta / gf-sets / gf-entity-lookup
 *    resolves to a corpus record (exact, or via skin-tone base collapse, or via
 *    a ZWJ-loose match). A miss means the merge dropped curated data — a real
 *    failure.
 *  - Emotif 1,624 (local only): every Emotif unicode resolves (strict or loose),
 *    when the on-disk seed is available; skipped-with-note otherwise.
 *  - No duplicate keys; every `set` ∈ CURATED_SETS.
 *
 * The full "GF 34,306 ∪ Emotif 1,624 ⊆ ours" needs external key lists absent
 * from the repo — NOT asserted here; see the report's `notChecked`.
 */
import type { Corpus, CorpusRecord } from "../core/schema.js";
import { CURATED_SETS } from "../core/schema.js";
import type { SeedData } from "./sources/seeds.js";
import type { EmotifData } from "./sources/emotif.js";

function looseKey(hexseq: string): string {
  return hexseq
    .split(" ")
    .filter((t) => t !== "200D")
    .join(" ");
}

export interface SeedSourceResult {
  source: string;
  total: number;
  exact: number;
  viaSkinBase: number;
  viaLoose: number;
  missing: string[];
}

export interface CoverageReport {
  pass: boolean;
  recordCount: number;
  minimumRecordCount: number;
  recordCountBelowMinimum: boolean;
  seed: SeedSourceResult[];
  emotif:
    | { available: false }
    | {
        available: true;
        total: number;
        exact: number;
        viaSkinBase: number;
        viaLoose: number;
        missing: string[];
      };
  duplicateKeys: string[];
  invalidSets: { hexseq: string; set: string }[];
  notChecked: string[];
}

function resolveSeedKeys(
  source: string,
  keys: Iterable<string>,
  keySet: Set<string>,
  looseSet: Set<string>,
  skinBaseOf: Map<string, string>,
): SeedSourceResult {
  let total = 0;
  let exact = 0;
  let viaSkinBase = 0;
  let viaLoose = 0;
  const missing: string[] = [];
  for (const key of keys) {
    total++;
    if (keySet.has(key)) {
      exact++;
      continue;
    }
    const base = skinBaseOf.get(key);
    if (base && keySet.has(base)) {
      viaSkinBase++;
      continue;
    }
    if (looseSet.has(looseKey(key))) {
      viaLoose++;
      continue;
    }
    missing.push(key);
  }
  return { source, total, exact, viaSkinBase, viaLoose, missing };
}

export function runCoverage(
  corpus: Corpus,
  seeds: SeedData,
  emotif: EmotifData,
  skinBaseOf: Map<string, string>,
  minimumRecordCount = 0,
): CoverageReport {
  const keySet = new Set<string>();
  const looseSet = new Set<string>();
  const duplicateKeys: string[] = [];
  const invalidSets: { hexseq: string; set: string }[] = [];
  const validSets = new Set<string>(CURATED_SETS);

  for (const r of corpus.records) {
    if (keySet.has(r.hexseq)) duplicateKeys.push(r.hexseq);
    keySet.add(r.hexseq);
    looseSet.add(looseKey(r.hexseq));
    if (r.set !== undefined && !validSets.has(r.set)) {
      invalidSets.push({ hexseq: r.hexseq, set: String(r.set) });
    }
  }

  const seed: SeedSourceResult[] = [
    resolveSeedKeys(
      "gf-tag-delta",
      seeds.tagDelta.rows.keys(),
      keySet,
      looseSet,
      skinBaseOf,
    ),
    resolveSeedKeys(
      "gf-sets",
      seeds.sets.rows.keys(),
      keySet,
      looseSet,
      skinBaseOf,
    ),
    resolveSeedKeys(
      "gf-entity-lookup",
      seeds.entities.map((e) => e.hexseq),
      keySet,
      looseSet,
      skinBaseOf,
    ),
  ];

  let emotifResult: CoverageReport["emotif"];
  if (!emotif.available) {
    emotifResult = { available: false };
  } else {
    let exact = 0;
    let viaSkinBase = 0;
    let viaLoose = 0;
    const missing: string[] = [];
    for (const ent of emotif.entries) {
      if (keySet.has(ent.hexseq)) {
        exact++;
        continue;
      }
      const base = skinBaseOf.get(ent.hexseq);
      if (base && keySet.has(base)) {
        viaSkinBase++;
        continue;
      }
      if (looseSet.has(looseKey(ent.hexseq))) {
        viaLoose++;
        continue;
      }
      missing.push(ent.rawUnicode);
    }
    emotifResult = {
      available: true,
      total: emotif.entries.length,
      exact,
      viaSkinBase,
      viaLoose,
      missing,
    };
  }

  const seedMisses = seed.reduce((n, s) => n + s.missing.length, 0);
  const recordCountBelowMinimum = corpus.records.length < minimumRecordCount;
  const pass =
    seedMisses === 0 && duplicateKeys.length === 0 && invalidSets.length === 0 &&
    !recordCountBelowMinimum;

  return {
    pass,
    recordCount: corpus.records.length,
    minimumRecordCount,
    recordCountBelowMinimum,
    seed,
    emotif: emotifResult,
    duplicateKeys,
    invalidSets,
    notChecked: [
      "Full GF 34,306 key list (not in repo) — only the extracted seed keys are asserted.",
      emotif.available
        ? "Emotif checked against local on-disk seed."
        : "Emotif 1,624 (external, on-disk only) — seed file absent this session.",
    ],
  };
}

/** Human-readable PASS/FAIL summary for the build log. */
export function formatCoverage(r: CoverageReport): string {
  const lines: string[] = [];
  lines.push(`Coverage: ${r.pass ? "PASS ✅" : "FAIL ❌"}  (records: ${r.recordCount})`);
  if (r.minimumRecordCount > 0) {
    lines.push(
      `  Record-count floor: ${r.recordCount}/${r.minimumRecordCount}` +
        (r.recordCountBelowMinimum ? "  BELOW PINNED FLOOR ❌" : " ✅"),
    );
  }
  lines.push("  Seed-key subset (every curated key must resolve):");
  for (const s of r.seed) {
    const resolved = s.exact + s.viaSkinBase + s.viaLoose;
    lines.push(
      `    ${s.source.padEnd(18)} ${resolved}/${s.total} resolved` +
        ` (exact ${s.exact}, via skin-base ${s.viaSkinBase}, via ZWJ-loose ${s.viaLoose})` +
        (s.missing.length ? `  MISSING ${s.missing.length}: ${s.missing.slice(0, 12).join(", ")}` : ""),
    );
  }
  if (r.emotif.available) {
    const resolved = r.emotif.exact + r.emotif.viaSkinBase + r.emotif.viaLoose;
    lines.push(
      `  Emotif: ${resolved}/${r.emotif.total} resolved` +
        ` (exact ${r.emotif.exact}, via skin-base ${r.emotif.viaSkinBase}, via ZWJ-loose ${r.emotif.viaLoose})` +
        (r.emotif.missing.length
          ? `  MISSING ${r.emotif.missing.length}: ${r.emotif.missing.slice(0, 12).join(", ")}`
          : ""),
    );
  } else {
    lines.push("  Emotif: SKIPPED (on-disk seed not present this session)");
  }
  lines.push(
    `  Duplicate keys: ${r.duplicateKeys.length}` +
      (r.duplicateKeys.length ? ` (${r.duplicateKeys.slice(0, 8).join(", ")})` : " ✅"),
  );
  lines.push(
    `  Invalid sets: ${r.invalidSets.length}` +
      (r.invalidSets.length
        ? ` (${r.invalidSets.slice(0, 8).map((x) => `${x.hexseq}=${x.set}`).join(", ")})`
        : " ✅"),
  );
  for (const n of r.notChecked) lines.push(`  note: ${n}`);
  return lines.join("\n");
}

/** Convenience type re-export for tests. */
export type { CorpusRecord };
