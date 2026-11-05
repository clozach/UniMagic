/**
 * Unimagic core — corpus + learning schema, and the ported Emotif score
 * constants. Isomorphic: no Node built-ins, no DOM.
 *
 * This file is the single canonical record of the Emotif score constants
 * (design.md § Tier 1) — Emotif's Swift source isn't in the vault, only on
 * disk at ~/Documents/4-Archives/emotif/. Change these only against that
 * source or an explicit decision.
 */

// ─────────────────────────────────────────────────────────────────────────
// Provenance & curated sets
// ─────────────────────────────────────────────────────────────────────────

/**
 * Where a keyword/sign token came from. Every merged token is provenance-tagged
 * (design.md merge recipe step 3) so attribution and score seeding stay honest.
 */
export type Provenance =
  | "ucd" // UnicodeData name tokens + NamesList annotations
  | "cldr" // CLDR / emojibase keywords
  | "glyphfinder-sheet" // GF human sheet-tag layer (colors, case, ASCII look-alikes)
  | "entity-lookup" // GF hand-authored entity-tag records ((c), 1/2, ->)
  | "emotif-builtin"; // Al's own Emotif keyword lists

/**
 * The 8 curated non-emoji sets in Glyphfinder's fixed order, plus the two
 * catch-alls. `set` on a record is exactly one of these (golden: every set ∈
 * the known list). Emoji live under `group`/`subgroup`, not a curated set.
 */
export type CuratedSet =
  | "Dashes"
  | "Fractions"
  | "Quotes"
  | "Keys"
  | "Spaces"
  | "Currencies"
  | "Arrows"
  | "Emojis"
  | "Other Glyphs";

export const CURATED_SETS: readonly CuratedSet[] = [
  "Dashes",
  "Fractions",
  "Quotes",
  "Keys",
  "Spaces",
  "Currencies",
  "Arrows",
  "Emojis",
  "Other Glyphs",
] as const;

// ─────────────────────────────────────────────────────────────────────────
// Corpus record
// ─────────────────────────────────────────────────────────────────────────

/** A keyword token with its origin, for search-field population + attribution. */
export interface KeywordToken {
  token: string;
  source: Provenance;
}

/**
 * One glyph in the union corpus. Shape from design.md § Union dataset spec
 * (record shape). Skin-tone families are collapsed to a base record
 * (`skinModifiable`), expanded at render time — the 1,445 duplicated GF rows
 * are dropped (zero search signal). `variants` are likewise NOT stored as an
 * array; they're derived at render time from `skinModifiable` /
 * `genderVariants` / `textPresentation`.
 */
export interface CorpusRecord {
  /** Fully-qualified rendered glyph (display + copy form). */
  symbol: string;
  /**
   * Normalized codepoint-sequence key: uppercase hex, single-space separated,
   * FE0F tokens stripped (design.md merge recipe step 1). This is THE join key
   * and the corpus's unique id.
   */
  hexseq: string;
  /** Primary Unicode name (or emojibase label for sequences). */
  name: string;
  block?: string;
  script?: string;
  /** Unicode version the code point was added in (DerivedAge). */
  age?: string;
  /** emoji top-level group, e.g. "Smileys & Emotion". */
  group?: string;
  /** emoji subgroup — drives Related computation (design.md Tier 2 field 8). */
  subgroup?: string;
  /** Curated set membership (non-emoji sections). */
  set?: CuratedSet;
  /** HTML entity names (no & / ;), e.g. ["mdash"]. */
  entities: string[];
  /** Word-tokens for the `tags` search field, provenance-tagged. */
  keywords: KeywordToken[];
  /** Sign-tokens for the `signs` field: `->`, `(c)`, `1/2`, single punctuation. */
  signs: string[];
  /** Confusables ∪ diacritic siblings — small, security/visual (Tier 2 field 7). */
  twins: string[];
  /** Emoji semantic siblings — can be long, emoji-only in v1 (Tier 2 field 8). */
  related: string[];
  /** Permissive NamesList annotations (Unicode-licensed prose). */
  annotations?: string[];
  /** Base emoji supports the 5 Fitzpatrick skin-tone modifiers. */
  skinModifiable?: boolean;
  /** Sibling hexseqs for gender presentation variants, if any. */
  genderVariants?: string[];
  /** Supports VS15 text vs VS16 emoji presentation. */
  textPresentation?: boolean;
  /**
   * emojibase's canonical (primary) shortcode, e.g. `heart` for ❤. Used as the
   * canonicity signal that disambiguates near-synonyms (❤ wins "heart" over the
   * decorated hearts). Absent for non-emoji.
   */
  primaryShortcode?: string;
  /**
   * Stable dataset order for secondary tie-break sorting (design.md Tier 1) —
   * curated sections first, base-then-skins adjacency preserved.
   */
  order: number;
}

/** The build-time corpus artifact (unimagic-corpus.json). */
export interface Corpus {
  /** Unicode + generator version stamp, e.g. "UCD-17.0 / emojibase-17". */
  build: string;
  records: CorpusRecord[];
}

// ─────────────────────────────────────────────────────────────────────────
// Learning: aliases, usage, and the Emotif score constants
// ─────────────────────────────────────────────────────────────────────────

/**
 * Alias provenance/state. `builtin` aliases are seeded from corpus keywords at
 * search time (never persisted). Only `learned` and `provisional` live in the
 * user's data.json — hence the separate LearnedAlias type below.
 */
export type AliasType = "builtin" | "learned" | "provisional";

/**
 * A user-taught association, persisted in plugin data.json. `provisional`
 * graduates to `learned` on the next exact pick (Unimagic's addition over
 * Emotif). Discriminated on `type` so only these two states are representable
 * in the store — `builtin` can never be persisted here.
 */
export interface LearnedAlias {
  term: string;
  hexseq: string;
  type: "learned" | "provisional";
  score: number;
}

/** Usage tally driving "Frequently used" and the usage boost. */
export interface UsageEntry {
  hexseq: string;
  count: number;
}

/** The full persisted store (plugin data.json). */
export interface UnimagicData {
  /** settingsVersion for migration + index invalidation (design.md). */
  version: number;
  usage: UsageEntry[];
  learned: LearnedAlias[];
}

/**
 * Emotif score constants — ported from Emotif's `Emoji.swift`. design.md is the
 * only spec record of these; keep them in sync with that doc.
 *
 * Builtin seeds (blended at search time from corpus keyword provenance):
 *   - name / ASCII-shortcut  → 3
 *   - keyword                → 2
 *   - soft-alias             → 0
 * Learned (query→glyph on pick): starts 1, +1 each repeat pick.
 * Provisional (co-occurring word): starts 0, +1 each repeat; graduates to
 *   learned on the next exact pick.
 */
export const SCORE = {
  builtinName: 3,
  builtinKeyword: 2,
  builtinSoftAlias: 0,
  learnedStart: 1,
  provisionalStart: 0,
  upVoteIncrement: 1,
} as const;

/**
 * Map a builtin keyword token's provenance to its seed score. `entity-lookup`
 * tokens (`->`, `(c)`, `1/2`) and a glyph's own name tokens carry ASCII-shortcut
 * weight (3); ordinary cldr/emotif/sheet word tags are keywords (2). Soft
 * aliases (weak associations) score 0 and only matter as tie-breakers.
 */
export function builtinScore(source: Provenance): number {
  switch (source) {
    case "ucd":
    case "entity-lookup":
      return SCORE.builtinName;
    case "cldr":
    case "emotif-builtin":
    case "glyphfinder-sheet":
      return SCORE.builtinKeyword;
    default:
      return SCORE.builtinSoftAlias;
  }
}

export const CURRENT_DATA_VERSION = 1;

export function emptyData(): UnimagicData {
  return { version: CURRENT_DATA_VERSION, usage: [], learned: [] };
}
