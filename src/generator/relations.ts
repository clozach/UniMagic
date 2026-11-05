/**
 * Build-time relations (design.md merge recipe step 7) and the stable `order`.
 *
 *  - twins[]  : confusables skeleton buckets ∪ NFKD diacritic-sibling groups —
 *               small, security/visual, non-emoji-heavy. Most records get 0.
 *  - related[]: same emoji subgroup (gender/role/base siblings), emoji-only,
 *               excluding a record's own genderVariants so the three rows stay
 *               distinct (Twins vs Related vs Variants).
 *  - genderVariants[] / skinModifiable / textPresentation feed Tier 2 field 9
 *               (Variants are derived at render time, not stored as an array).
 *  - order    : curated sets first (fixed order), then Emojis (emojibase order),
 *               then Other Glyphs — a deterministic search tie-break that keeps
 *               base-then-skins adjacency.
 */
import type { CorpusRecord, CuratedSet } from "../core/schema.js";
import { normalizeHexseq } from "./normalize.js";
import type { Draft } from "./merge.js";
import { finalizeKeywords } from "./merge.js";
import type { Confusables } from "./sources/confusables.js";

/** Bounded per design ("no scroll needed" / "can run long but not unbounded"). */
export const MAX_TWINS = 24;
export const MAX_RELATED = 40;

const DIACRITIC_SCRIPTS = new Set(["Latin", "Greek", "Cyrillic"]);
const GENDER_BASES = [0x1f468, 0x1f469, 0x1f9d1]; // man, woman, person
const GENDER_SIGNS = [0x2640, 0x2642]; // female, male

const CURATED_ORDER: CuratedSet[] = [
  "Dashes",
  "Fractions",
  "Quotes",
  "Keys",
  "Spaces",
  "Currencies",
  "Arrows",
];

// ── twins ──────────────────────────────────────────────────────────────────

function computeTwins(drafts: Map<string, Draft>, confus: Confusables): void {
  const singles = [...drafts.values()].filter((d) => d.cps.length === 1);

  // (a) confusable skeleton buckets
  const skeletonBuckets = new Map<string, string[]>();
  for (const d of singles) {
    const cp = d.cps[0];
    const skeleton = confus.map.get(cp) ?? String.fromCodePoint(cp);
    const bucket = skeletonBuckets.get(skeleton);
    if (bucket) bucket.push(d.hexseq);
    else skeletonBuckets.set(skeleton, [d.hexseq]);
  }

  // (b) diacritic-sibling groups (NFKD base letter, Latin/Greek/Cyrillic)
  const diacriticGroups = new Map<string, string[]>();
  for (const d of singles) {
    if (!d.gc || d.gc[0] !== "L") continue;
    if (!d.script || !DIACRITIC_SCRIPTS.has(d.script)) continue;
    const ch = String.fromCodePoint(d.cps[0]);
    const nfkd = ch.normalize("NFKD");
    const baseChar = [...nfkd][0];
    if (!/\p{L}/u.test(baseChar)) continue;
    const key = `${d.script}|${baseChar.toLowerCase()}`;
    const group = diacriticGroups.get(key);
    if (group) group.push(d.hexseq);
    else diacriticGroups.set(key, [d.hexseq]);
  }

  // Confusable mates and diacritic mates are kept in SEPARATE maps so the cap
  // favors confusables — the Twins row's primary, security purpose (Cyrillic а
  // vs Latin a). Diacritic siblings fill remaining slots. This keeps a base
  // Latin letter's cross-script confusables from being crowded out by its own
  // accented family (which sort earlier by hexseq).
  const confusMates = new Map<string, Set<string>>();
  const diaMates = new Map<string, Set<string>>();
  const fill = (dest: Map<string, Set<string>>, members: string[]) => {
    if (members.length < 2) return;
    for (const h of members) {
      let s = dest.get(h);
      if (!s) {
        s = new Set();
        dest.set(h, s);
      }
      for (const other of members) if (other !== h) s.add(other);
    }
  };
  for (const bucket of skeletonBuckets.values()) fill(confusMates, bucket);
  for (const group of diacriticGroups.values()) fill(diaMates, group);

  for (const d of drafts.values()) {
    const confusable = [...(confusMates.get(d.hexseq) ?? [])].sort();
    const diacritic = [...(diaMates.get(d.hexseq) ?? [])].sort();
    if (confusable.length === 0 && diacritic.length === 0) continue;
    const seen = new Set<string>();
    const ordered: string[] = [];
    for (const h of [...confusable, ...diacritic]) {
      if (seen.has(h)) continue;
      seen.add(h);
      ordered.push(h);
    }
    d.twins = ordered.slice(0, MAX_TWINS);
  }
}

// ── gender variants ──────────────────────────────────────────────────────────

function computeGenderVariants(drafts: Map<string, Draft>): void {
  for (const d of drafts.values()) {
    if (!d.emoji) continue;
    const found = new Set<string>();
    for (let i = 0; i < d.cps.length; i++) {
      const cp = d.cps[i];
      const alts = GENDER_BASES.includes(cp)
        ? GENDER_BASES
        : GENDER_SIGNS.includes(cp)
          ? GENDER_SIGNS
          : null;
      if (!alts) continue;
      for (const alt of alts) {
        if (alt === cp) continue;
        const swapped = d.cps.slice();
        swapped[i] = alt;
        const cand = normalizeHexseq(swapped.map((c) => c.toString(16)).join(" "));
        if (cand !== d.hexseq && drafts.has(cand)) found.add(cand);
      }
    }
    if (found.size > 0) d.genderVariants = [...found].sort();
  }
}

// ── related ──────────────────────────────────────────────────────────────────

function computeRelated(drafts: Map<string, Draft>): void {
  const bySubgroup = new Map<string, Draft[]>();
  for (const d of drafts.values()) {
    if (!d.emoji || !d.subgroup) continue;
    const list = bySubgroup.get(d.subgroup);
    if (list) list.push(d);
    else bySubgroup.set(d.subgroup, [d]);
  }
  for (const list of bySubgroup.values()) {
    list.sort((a, b) => (a.emojiOrder ?? 1e9) - (b.emojiOrder ?? 1e9));
  }
  for (const d of drafts.values()) {
    if (!d.emoji || !d.subgroup) continue;
    const siblings = bySubgroup.get(d.subgroup);
    if (!siblings || siblings.length < 2) continue;
    const exclude = new Set(d.genderVariants);
    d.related = siblings
      .filter((s) => s.hexseq !== d.hexseq && !exclude.has(s.hexseq))
      .slice(0, MAX_RELATED)
      .map((s) => s.hexseq);
  }
}

// ── order ─────────────────────────────────────────────────────────────────

function assignOrder(drafts: Map<string, Draft>): void {
  const all = [...drafts.values()];
  const curatedIndex = (set: CuratedSet | undefined) =>
    set ? CURATED_ORDER.indexOf(set) : -1;
  const firstCp = (d: Draft) => d.cps[0] ?? 0;

  const curated = all
    .filter((d) => curatedIndex(d.set) >= 0)
    .sort((a, b) =>
      curatedIndex(a.set) !== curatedIndex(b.set)
        ? curatedIndex(a.set) - curatedIndex(b.set)
        : firstCp(a) - firstCp(b),
    );
  const emojis = all
    .filter((d) => d.set === "Emojis")
    .sort((a, b) =>
      (a.emojiOrder ?? 1e9) !== (b.emojiOrder ?? 1e9)
        ? (a.emojiOrder ?? 1e9) - (b.emojiOrder ?? 1e9)
        : firstCp(a) - firstCp(b),
    );
  const others = all
    .filter((d) => d.set === "Other Glyphs")
    .sort((a, b) => firstCp(a) - firstCp(b));

  let i = 0;
  for (const d of [...curated, ...emojis, ...others]) d.order = i++;
}

// ── finalize ─────────────────────────────────────────────────────────────────

function toRecord(d: Draft): CorpusRecord {
  const rec: CorpusRecord = {
    symbol: d.symbol,
    hexseq: d.hexseq,
    name: d.name,
    entities: [...d.entities].sort(),
    keywords: finalizeKeywords(d),
    signs: [...d.signs].sort(),
    twins: d.twins,
    related: d.related,
    order: d.order,
  };
  if (d.block) rec.block = d.block;
  if (d.script) rec.script = d.script;
  if (d.age) rec.age = d.age;
  if (d.group) rec.group = d.group;
  if (d.subgroup) rec.subgroup = d.subgroup;
  if (d.set) rec.set = d.set;
  if (d.annotations.size > 0) rec.annotations = [...d.annotations];
  if (d.skinModifiable) rec.skinModifiable = true;
  if (d.genderVariants.length > 0) rec.genderVariants = d.genderVariants;
  if (d.textPresentation) rec.textPresentation = true;
  return rec;
}

/** Compute all relations + order, then materialize to sorted CorpusRecords. */
export function buildRelationsAndFinalize(
  drafts: Map<string, Draft>,
  confus: Confusables,
): CorpusRecord[] {
  computeTwins(drafts, confus);
  computeGenderVariants(drafts);
  computeRelated(drafts);
  assignOrder(drafts);
  return [...drafts.values()]
    .map(toRecord)
    .sort((a, b) => a.order - b.order);
}
