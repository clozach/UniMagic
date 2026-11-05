/**
 * Unimagic corpus generator — entry point.
 *
 * Merges UCD-17 ∪ emojibase-17 ∪ the tracked Glyphfinder seeds (∪ Emotif, when
 * its on-disk seed is present) into `unimagic-corpus.json`, per design.md §
 * Union dataset spec. Build-time only (Node built-ins); the isomorphic core
 * never imports this.
 *
 * Run (from projects/unimagic/src/):
 *   eval "$(fnm env)" && node_modules/.bin/tsx src/generator/build.ts
 */
import { mkdtempSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { gzipSync } from "node:zlib";
import { basename, join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import type { Corpus, CorpusRecord, Provenance } from "../core/schema.js";
import { loadUcd } from "./sources/ucd.js";
import { loadEmojibase, loadShortcodes } from "./sources/emojibase.js";
import { loadSeeds } from "./sources/seeds.js";
import { loadConfusables } from "./sources/confusables.js";
import { loadEmotif } from "./sources/emotif.js";
import { merge } from "./merge.js";
import { buildRelationsAndFinalize } from "./relations.js";
import { runCoverage, formatCoverage, type CoverageReport } from "./coverage.js";
import type { SeedData } from "./sources/seeds.js";
import type { EmotifData } from "./sources/emotif.js";
import manifest from "../../source-manifest.json";

const OUTPUT = resolve(process.cwd(), "unimagic-corpus.json");
const OUTPUT_GZ = `${OUTPUT}.gz`;

export interface GenerateResult {
  corpus: Corpus;
  seeds: SeedData;
  emotif: EmotifData;
  skinBaseOf: Map<string, string>;
  meta: {
    confusablesUrl: string;
    confusablesAvailable: boolean;
    droppedSkins: number;
    emotifWired: number;
    emotifResolvedLoose: number;
    ucdExcluded: Record<string, number>;
  };
}

/** Load every source, run the merge recipe, and finalize the corpus. */
export async function generateCorpus(): Promise<GenerateResult> {
  const [ucd, confus] = await Promise.all([loadUcd(), loadConfusables()]);
  const emoji = loadEmojibase();
  const seeds = loadSeeds();
  const emotif = loadEmotif();

  const merged = merge(ucd, emoji, seeds, emotif);
  const records = buildRelationsAndFinalize(merged.drafts, confus);

  // Enrich with emojibase's canonical shortcode (canonicity signal for search).
  const shortcodes = loadShortcodes();
  for (const r of records) {
    const sc = shortcodes.get(r.hexseq);
    if (sc) r.primaryShortcode = sc;
  }

  const build =
    `UCD-${manifest.unicode} / emojibase-${manifest.emojibase} / ` +
    `confusables-${manifest.security} / ` +
    `gen:${manifest.generationDate}`;

  return {
    corpus: { build, records },
    seeds,
    emotif,
    skinBaseOf: merged.skinBaseOf,
    meta: {
      confusablesUrl: confus.sourceUrl,
      confusablesAvailable: confus.available,
      droppedSkins: emoji.droppedSkins,
      emotifWired: merged.emotifWired,
      emotifResolvedLoose: merged.emotifResolvedLoose,
      ucdExcluded: ucd.excluded,
    },
  };
}

// ── reporting ────────────────────────────────────────────────────────────────

function countBy<T>(items: T[], key: (t: T) => string | undefined): Map<string, number> {
  const m = new Map<string, number>();
  for (const it of items) {
    const k = key(it);
    if (k === undefined) continue;
    m.set(k, (m.get(k) ?? 0) + 1);
  }
  return m;
}

function sortedEntries(m: Map<string, number>): [string, number][] {
  return [...m.entries()].sort((a, b) => b[1] - a[1]);
}

function reportStats(records: CorpusRecord[]): string {
  const lines: string[] = [];
  lines.push(`Records: ${records.length}`);

  lines.push("  By set:");
  const bySet = countBy(records, (r) => r.set ?? "(none)");
  for (const [set, n] of sortedEntries(bySet)) lines.push(`    ${set.padEnd(14)} ${n}`);

  lines.push("  By emoji group (Emojis set only):");
  const byGroup = countBy(
    records.filter((r) => r.set === "Emojis"),
    (r) => r.group ?? "(no group)",
  );
  for (const [g, n] of sortedEntries(byGroup)) lines.push(`    ${g.padEnd(20)} ${n}`);

  const withTwins = records.filter((r) => r.twins.length > 0);
  const withRelated = records.filter((r) => r.related.length > 0);
  const withGender = records.filter((r) => r.genderVariants && r.genderVariants.length > 0);
  const withEntities = records.filter((r) => r.entities.length > 0);
  const skinnable = records.filter((r) => r.skinModifiable);
  const dualPres = records.filter((r) => r.textPresentation);
  const twinRefs = records.reduce((n, r) => n + r.twins.length, 0);
  const relRefs = records.reduce((n, r) => n + r.related.length, 0);

  lines.push("  Relations & flags:");
  lines.push(
    `    twins: ${withTwins.length} records ≥1 twin (${twinRefs} refs, ` +
      `max ${Math.max(0, ...records.map((r) => r.twins.length))})`,
  );
  lines.push(
    `    related: ${withRelated.length} records ≥1 related (${relRefs} refs, ` +
      `max ${Math.max(0, ...records.map((r) => r.related.length))})`,
  );
  lines.push(`    genderVariants: ${withGender.length} records`);
  lines.push(`    skinModifiable: ${skinnable.length} records`);
  lines.push(`    textPresentation: ${dualPres.length} records`);
  lines.push(`    entities: ${withEntities.length} records carry ≥1 HTML entity`);

  const kwBySource = new Map<Provenance, number>();
  let signCount = 0;
  for (const r of records) {
    for (const k of r.keywords)
      kwBySource.set(k.source, (kwBySource.get(k.source) ?? 0) + 1);
    signCount += r.signs.length;
  }
  lines.push("  Keyword tokens by provenance:");
  for (const [src, n] of [...kwBySource.entries()].sort((a, b) => b[1] - a[1]))
    lines.push(`    ${src.padEnd(18)} ${n}`);
  lines.push(`  Sign tokens (total across records): ${signCount}`);
  return lines.join("\n");
}

async function main(): Promise<void> {
  const started = Date.now();
  const gen = await generateCorpus();
  const json = JSON.stringify(gen.corpus);
  const coverage: CoverageReport = runCoverage(
    gen.corpus,
    gen.seeds,
    gen.emotif,
    gen.skinBaseOf,
    manifest.minimumRecords,
  );

  console.log("─".repeat(72));
  console.log(`build: ${gen.corpus.build}`);
  console.log(
    `confusables: ${gen.meta.confusablesAvailable ? "available" : "UNAVAILABLE (twins → diacritic siblings only)"} — ${gen.meta.confusablesUrl}`,
  );
  console.log(`dropped skin-tone rows: ${gen.meta.droppedSkins}`);
  console.log(
    `UCD excluded: ${Object.entries(gen.meta.ucdExcluded).map(([k, v]) => `${k}=${v}`).join(", ")}`,
  );
  if (gen.emotif.available) {
    console.log(
      `Emotif wired: ${gen.meta.emotifWired} entries (${gen.meta.emotifResolvedLoose} via ZWJ-loose)`,
    );
  } else {
    console.log(`Emotif: not wired (seed absent at ${gen.emotif.path})`);
  }
  console.log("─".repeat(72));
  console.log(reportStats(gen.corpus.records));
  console.log("─".repeat(72));
  console.log(formatCoverage(coverage));
  console.log("─".repeat(72));
  console.log(`done in ${((Date.now() - started) / 1000).toFixed(1)}s`);

  if (!coverage.pass) {
    console.error("Generation rejected; previous corpus/build artifacts were not changed.");
    process.exitCode = 1;
    return;
  }

  // Write both artifacts away from the project, then atomically move them into
  // place only after coverage passes. An interrupted/failed generation leaves
  // the prior corpus usable.
  const staging = mkdtempSync(join(tmpdir(), "unimagic-corpus-"));
  const stagedJson = join(staging, basename(OUTPUT));
  const stagedGzip = join(staging, basename(OUTPUT_GZ));
  try {
    writeFileSync(stagedJson, json, "utf8");
    writeFileSync(stagedGzip, gzipSync(json));
    renameSync(stagedJson, OUTPUT);
    renameSync(stagedGzip, OUTPUT_GZ);
  } finally {
    rmSync(staging, { recursive: true, force: true });
  }
  console.log(`wrote: ${OUTPUT}`);
}

const isEntry =
  process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isEntry) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
