/**
 * Unimagic core — full-corpus search. MiniSearch for the word fields, plus
 * three hand-wired signals the tokenizer can't express cleanly: whole-query
 * SIGN matching (`->`, `1/2`), codepoint/hex resolution, and injected
 * learned/provisional aliases. Isomorphic: no Node, no DOM.
 *
 * Ranking model (design.md Tier 1, cross-checked against the blessed mock):
 * per glyph, SUM the signals. Field boosts descend signs > name > tags >
 * entities > category — the mock's proven order (signs 60 > name 30 > tags 24
 * > entities 10); design.md's prose "descending boosts" over the field list is
 * ambiguous on which field wins, so we take the mock's concrete ordering.
 * Ties break by curated dataset `order` (base-then-skins adjacency).
 */

import MiniSearch, { type Options as MiniSearchOptions } from "minisearch";
import { Corpus, CorpusRecord } from "./schema";
import { learnedMatches, normQuery } from "./learning";
import { UnimagicData } from "./schema";
import { normalizeSearchText, wordTokenize } from "./search-text";
import { recordFor } from "./glyphs";

export interface SearchHit {
  hexseq: string;
  score: number;
  record: CorpusRecord;
}

// Signal weights. Named + centralized so goldens can be tuned in one place.
export const WEIGHTS = {
  /** whole-query exact match against a record's signs field. */
  sign: 60,
  /** multiplier applied to a MiniSearch relevance score. */
  text: 1,
  /** multiplier on a learned/provisional alias's score-sum. */
  learned: 40,
  /** codepoint/hex direct resolution — always tops the list. */
  codepoint: 1000,
  /** exact pasted-glyph resolution. */
  paste: 1000,
  /** query exactly equals a glyph's canonical shortcode (❤ for "heart"). */
  canonical: 500,
  /**
   * Gentle curation/commonness prior from dataset `order` (curated sets +
   * early Unicode/emoji order first). Floats common glyphs above obscure
   * look-alikes when text relevance is close, without overriding a real
   * relevance or canonical/learned signal.
   */
  curation: 50,
} as const;

// Per-field boosts (see header note on ordering).
export const FIELD_BOOSTS = {
  signs: 6,
  name: 5,
  tags: 3,
  entities: 2,
  category: 1,
} as const;

/** The MiniSearch-facing document derived from a corpus record. */
interface Doc {
  id: string; // hexseq
  name: string;
  tags: string;
  entities: string;
  category: string;
  // `signs` is handled outside MiniSearch (whole-query match), not indexed here.
}

function toDoc(r: CorpusRecord): Doc {
  // Dedupe tokens: the corpus keeps the same token per provenance (for
  // attribution), but BM25 must not double-count "heart" three times.
  const tokens = new Set(r.keywords.map((k) => k.token));
  // Make the canonical shortcode searchable too (red_heart → "red heart").
  if (r.primaryShortcode) for (const p of r.primaryShortcode.split("_")) tokens.add(p);
  return {
    id: r.hexseq,
    name: r.name,
    tags: [...tokens].join(" "),
    entities: r.entities.join(" "),
    category: [r.set, r.block, r.script, r.group, r.subgroup]
      .filter(Boolean)
      .join(" "),
  };
}

export const MINISEARCH_OPTIONS: MiniSearchOptions = {
  idField: "id",
  fields: ["name", "tags", "entities", "category"],
  tokenize: wordTokenize,
  // Lowercase only — NO diacritic folding (searching `é` must not equal `e`).
  processTerm: (term) => term.toLowerCase(),
};

/**
 * A built, queryable index over a corpus. Bundles the MiniSearch instance with
 * the by-id record map and a whole-token signs lookup.
 */
export interface IndexBundle {
  mini: MiniSearch;
  byId: Map<string, CorpusRecord>;
  /** normalized sign token → hexseqs carrying it. */
  signs: Map<string, string[]>;
  /** canonical shortcode → hexseqs (canonicity bonus lookup). */
  canonical: Map<string, string[]>;
  build: string;
}

export function buildIndex(corpus: Corpus): IndexBundle {
  const byId = new Map<string, CorpusRecord>();
  const signs = new Map<string, string[]>();
  const canonical = new Map<string, string[]>();
  const push = (map: Map<string, string[]>, key: string, hexseq: string) => {
    const arr = map.get(key);
    if (arr) arr.push(hexseq);
    else map.set(key, [hexseq]);
  };
  for (const r of corpus.records) {
    byId.set(r.hexseq, r);
    for (const sign of r.signs) push(signs, sign.toLowerCase(), r.hexseq);
    if (r.primaryShortcode) push(canonical, r.primaryShortcode.toLowerCase(), r.hexseq);
  }
  const mini = new MiniSearch(MINISEARCH_OPTIONS);
  mini.addAll(corpus.records.map(toDoc));
  return { mini, byId, signs, canonical, build: corpus.build };
}

/** Serialize the index for per-device caching (MiniSearch.loadJSON round-trip). */
export function serializeIndex(bundle: IndexBundle): string {
  return JSON.stringify(bundle.mini);
}

// ─────────────────────────────────────────────────────────────────────────
// Query resolution
// ─────────────────────────────────────────────────────────────────────────

/**
 * Resolve a codepoint/hex/decimal query to a first-codepoint match.
 * Handles `U+2014`, `2014`, `1F600`, and decimal (`8212`). GF never shipped
 * this. Returns hexseqs whose leading codepoint matches.
 */
export function resolveCodepoint(q: string, byId: Map<string, CorpusRecord>): string[] {
  const nq = q.trim();
  let cp: number | undefined;
  const hex = nq.match(/^(?:u\+|0x)?([0-9a-f]{2,6})$/i);
  if (hex) cp = parseInt(hex[1], 16);
  const dec = nq.match(/^([0-9]{1,7})$/);
  // A bare all-digits string could be hex or decimal; prefer hex if it names a
  // plausible code point, else fall back to decimal. (`2014` → U+2014.)
  if (hex && dec) {
    // ambiguous: try hex first, then decimal
    const asHex = codepointHexseqs(parseInt(hex[1], 16), byId);
    if (asHex.length) return asHex;
    return codepointHexseqs(parseInt(dec[1], 10), byId);
  }
  if (cp === undefined && dec) cp = parseInt(dec[1], 10);
  if (cp === undefined) return [];
  return codepointHexseqs(cp, byId);
}

function codepointHexseqs(cp: number, byId: Map<string, CorpusRecord>): string[] {
  if (!Number.isFinite(cp) || cp < 0 || cp > 0x10ffff) return [];
  const target = cp.toString(16).toUpperCase().replace(/^0+/, "") || "0";
  const hits: CorpusRecord[] = [];
  for (const [hexseq, r] of byId) {
    const first = hexseq.split(" ")[0].replace(/^0+/, "") || "0";
    if (first === target) hits.push(r);
  }
  // Prefer the exact single-codepoint glyph over sequences that merely start
  // with it ("U+2764" → ❤, not ❤‍🔥).
  hits.sort(
    (a, b) =>
      a.hexseq.split(" ").length - b.hexseq.split(" ").length || a.order - b.order,
  );
  return hits.map((r) => r.hexseq);
}

// ─────────────────────────────────────────────────────────────────────────
// Search
// ─────────────────────────────────────────────────────────────────────────

export interface SearchEnv {
  index: IndexBundle;
  data: UnimagicData;
}

/** Result cap before virtualization (design.md ~500). */
export const RESULT_CAP = 500;

/**
 * Run a query, returning ranked hits. Empty query → [] (caller shows the
 * browse grid). Explicit codepoints resolve directly; bare hex and literal
 * glyphs join word matches, because they may also be someone's vocabulary.
 */
export function search(env: SearchEnv, query: string): SearchHit[] {
  const nq = normQuery(query);
  if (!nq) return [];
  const { index, data } = env;

  // 1. Codepoint / hex / decimal — direct resolution, tops the list.
  const cps = resolveCodepoint(nq, index.byId);
  if (cps.length && /^(?:u\+|0x)/i.test(nq)) return toHits(cps, WEIGHTS.codepoint, index);

  // 2. Exact pasted glyph.
  const raw = query.trim();
  const pasted: string[] = [];
  for (const [hexseq, r] of index.byId) {
    if (r.symbol === raw) pasted.push(hexseq);
  }
  // Corpus glyphs often carry emoji presentation (VS16). A pasted text/bare
  // form names the same glyph. Keep exact matches first, and leave ZWJ, skin
  // modifiers, accents and every other variation selector intact.
  if (!pasted.length && /[\p{Emoji}\uFE0E\uFE0F]/u.test(raw)) {
    const neutral = raw.replace(/[\uFE0E\uFE0F]/gu, "");
    for (const [hexseq, r] of index.byId) {
      if (r.symbol.replace(/[\uFE0E\uFE0F]/gu, "") === neutral) pasted.push(hexseq);
      if (pasted.length === RESULT_CAP) break;
    }
  }

  // 3. Accumulate scores across signals.
  const scores = new Map<string, number>();
  const add = (hexseq: string, s: number) =>
    scores.set(hexseq, (scores.get(hexseq) ?? 0) + s);
  cps.forEach((hexseq, position) => add(hexseq, WEIGHTS.codepoint - position));
  for (const hexseq of pasted) add(hexseq, WEIGHTS.paste);

  // 3a. MiniSearch word fields (prefix + fuzzy-on-words, AND).
  const results = index.mini.search(nq, {
    prefix: true,
    // Fuzzy 0.2 on words only — and only for length ≥ 6, so a short query like
    // "arrow" (5) stays exact instead of fuzzy-matching "narrow" (1 edit) and
    // dragging obscure look-alikes to the top.
    fuzzy: (term) => (term.length >= 6 && /^[\p{L}]/u.test(term) ? 0.2 : false),
    combineWith: "AND",
    boost: FIELD_BOOSTS,
  });
  for (const res of results) add(res.id, res.score * WEIGHTS.text);

  // 3b. Whole-query SIGN match (`->`, `1/2`, single punctuation).
  const signHits = index.signs.get(nq);
  if (signHits) for (const hexseq of signHits) add(hexseq, WEIGHTS.sign);

  // 3c. Injected learned / provisional aliases (recall + boost).
  for (const [hexseq, s] of learnedMatches(data, nq)) {
    // Presence alone injects the glyph; score scales the rank.
    add(hexseq, WEIGHTS.learned * (s + 1));
  }

  // 3d. Canonical shortcode exact match — disambiguates near-synonyms.
  const canon = index.canonical.get(normalizeSearchText(nq));
  if (canon) for (const hexseq of canon) add(hexseq, WEIGHTS.canonical);

  // 4. Add the curation prior, then rank: score desc, curated `order` asc.
  const n = index.byId.size || 1;
  const hits: SearchHit[] = [];
  for (const [hexseq, score] of scores) {
    // A learned word may name a toned variant the corpus folds into its base.
    const record = recordFor(index, hexseq);
    if (!record) continue;
    const curated = WEIGHTS.curation * (1 - record.order / n);
    hits.push({ hexseq, score: score + curated, record });
  }
  hits.sort((a, b) => b.score - a.score || a.record.order - b.record.order);
  return hits.slice(0, RESULT_CAP);
}

function toHits(hexseqs: string[], score: number, index: IndexBundle): SearchHit[] {
  // Input order is already meaningful (codepoint: exact-single first) — preserve it.
  const hits: SearchHit[] = [];
  for (const hexseq of hexseqs) {
    const record = index.byId.get(hexseq);
    if (record) hits.push({ hexseq, score, record });
  }
  return hits;
}
