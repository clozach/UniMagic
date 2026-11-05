/**
 * Key normalization + token partitioning for the corpus generator.
 *
 * The join key (design.md merge recipe step 1): uppercase hex, single-space
 * separated, FE0F tokens stripped, each codepoint zero-padded to ≥4 digits
 * (matching the seed convention: "0022", "00A0", "1F441 200D 1F5E8").
 *
 * The words/signs partition (merge recipe step 4) is a hard contract: sign
 * tokens (`->`, `(c)`, `1/2`, single punctuation) go to `signs`; word tokens
 * (letters/digits only) go to `keywords`.
 */

/** Uppercase hex for a single codepoint, zero-padded to a minimum of 4 digits. */
export function cpToHex(cp: number): string {
  const h = cp.toString(16).toUpperCase();
  return h.length < 4 ? h.padStart(4, "0") : h;
}

/**
 * Normalize any codepoint-sequence spelling to the corpus join key. Accepts
 * space- or hyphen-separated hex (emojibase uses `-`, seeds use spaces).
 * Strips FE0F (emoji variation selector) so emojibase-5 unqualified and modern
 * fully-qualified forms reconcile to one key.
 */
export function normalizeHexseq(raw: string): string {
  return raw
    .trim()
    .split(/[\s-]+/)
    .filter((t) => t.length > 0)
    .map((t) => t.toUpperCase())
    .filter((t) => t !== "FE0F")
    .map((t) => cpToHex(parseInt(t, 16)))
    .join(" ");
}

/**
 * A "loose" key with ZWJ (200D) *and* FE0F stripped — used only to reconcile
 * legacy non-ZWJ emoji encodings (Emotif's EmojiOne seed spells sequences like
 * `1f469-2764-1f469`) against modern RGI keys. Never used as a primary key.
 */
export function looseHexseq(raw: string): string {
  return normalizeHexseq(raw)
    .split(" ")
    .filter((t) => t !== "200D")
    .join(" ");
}

/** Parse a normalized hexseq back to its codepoint array. */
export function hexseqToCps(hexseq: string): number[] {
  return hexseq.split(" ").map((h) => parseInt(h, 16));
}

/** The rendered glyph for a bare codepoint sequence (no VS/ZWJ qualification). */
export function cpsToSymbol(cps: number[]): string {
  return String.fromCodePoint(...cps);
}

// ─────────────────────────────────────────────────────────────────────────
// Token partitioning
// ─────────────────────────────────────────────────────────────────────────

/** A token is a *word* iff it is entirely letters/digits (Unicode-aware). */
const WORD_RE = /^[\p{L}\p{N}]+$/u;

/** True for sign tokens: `->`, `(c)`, `1/2`, `€`, single punctuation, etc. */
export function isSign(token: string): boolean {
  return token.length > 0 && !WORD_RE.test(token);
}

/** Split a name/label/annotation phrase into raw tokens (words + signs). */
export function splitPhrase(str: string): string[] {
  return str
    .toLowerCase()
    .split(/[\s\-_/:;,.()[\]{}<>"'|]+/)
    .map((t) => t.trim())
    .filter((t) => t.length > 0);
}

/**
 * Partition an already-tokenized list (e.g. a seed tag array) into lowercased
 * word tokens and verbatim sign tokens.
 */
export function partitionTokens(tokens: string[]): {
  words: string[];
  signs: string[];
} {
  const words: string[] = [];
  const signs: string[] = [];
  for (const raw of tokens) {
    const t = raw.trim();
    if (t.length === 0) continue;
    if (isSign(t)) signs.push(t);
    else words.push(t.toLowerCase());
  }
  return { words, signs };
}

/** Partition a free-text phrase (name/label/alias) into words + signs. */
export function partitionPhrase(str: string): { words: string[]; signs: string[] } {
  return partitionTokens(splitPhrase(str));
}
