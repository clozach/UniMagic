/**
 * Unimagic core — learning engine. Pure functions over the learned store
 * (data.json); the host owns persistence. Ported from Emotif's `Emoji.swift`
 * (upVote / SearchString) — see design.md § Tier 1. Isomorphic: no Node, no DOM.
 *
 * Model (Emotif, with one Unimagic addition):
 *  - On pick, a DUAL up-vote fires against the query that was picked:
 *      · the LAST query word  → `learned`     (start 1, +1 per repeat)
 *      · the PENULTIMATE word  → `provisional` (start 0, +1 per repeat) — a
 *        weaker co-occurrence signal that boosts RECALL (the glyph now matches
 *        that word) even at score 0.
 *  - Unimagic addition: a `provisional` alias GRADUATES to `learned` the next
 *    time that exact word is the picked (ultimate) word for that glyph. Emotif
 *    kept the two permanently separate; we reclassify for clarity.
 *  - Ranking blends by SCORE-SUM per glyph across all matching aliases.
 */

import {
  LearnedAlias,
  UnimagicData,
  UsageEntry,
  SCORE,
} from "./schema";
import { normalizeSearchText } from "./search-text";

// ─────────────────────────────────────────────────────────────────────────
// Query → words
// ─────────────────────────────────────────────────────────────────────────

/** True if the word ends in an emoji/pictographic char (Emotif excluded these). */
export function endsWithEmoji(word: string): boolean {
  return /\p{Extended_Pictographic}$/u.test(word);
}

/** Normalize a query the same way everywhere: lowercase, trim. NO diacritic fold. */
export function normQuery(q: string): string {
  return q.toLowerCase().trim();
}

/** Split a query into lowercased words (whitespace-separated, non-empty). */
export function toWords(q: string): string[] {
  return normQuery(q).split(/\s+/).filter(Boolean);
}

/** Emotif parseForVoting: the last two non-emoji words of the query. */
export function parseForVoting(q: string): {
  ultimate?: string;
  penultimate?: string;
} {
  const words = toWords(q).filter((w) => !endsWithEmoji(w));
  const ultimate = words.length >= 1 ? words[words.length - 1] : undefined;
  const penultimate = words.length >= 2 ? words[words.length - 2] : undefined;
  return { ultimate, penultimate };
}

// ─────────────────────────────────────────────────────────────────────────
// Store queries (read-only)
// ─────────────────────────────────────────────────────────────────────────

function findAlias(
  data: UnimagicData,
  term: string,
  hexseq: string,
): LearnedAlias | undefined {
  return data.learned.find((a) => a.term === term && a.hexseq === hexseq);
}

/** All learned/provisional aliases for a glyph (detail-card chips). */
export function aliasesFor(data: UnimagicData, hexseq: string): LearnedAlias[] {
  return data.learned.filter((a) => a.hexseq === hexseq);
}

/**
 * Learned/provisional score contribution for a glyph given a query. A term
 * contributes its full score on an exact match and on a prefix match (design:
 * prefix favored over substring); presence alone (even score 0) is what lets a
 * provisional alias inject the glyph into results. Returns the score-sum.
 */
export function learnedBoost(
  data: UnimagicData,
  q: string,
  hexseq: string,
): number {
  const nq = normalizeSearchText(q);
  if (!nq) return 0;
  let sum = 0;
  for (const a of data.learned) {
    if (a.hexseq !== hexseq) continue;
    if (normalizeSearchText(a.term).startsWith(nq)) sum += a.score;
  }
  return sum;
}

/**
 * Every glyph whose learned/provisional alias matches the query, with its
 * score-sum. Used by search to INJECT learned matches that the corpus index
 * wouldn't surface on its own (recall from provisional aliases at score 0).
 * Exact-term and prefix-term matches both qualify.
 */
export function learnedMatches(
  data: UnimagicData,
  q: string,
): Map<string, number> {
  const nq = normalizeSearchText(q);
  const out = new Map<string, number>();
  if (!nq) return out;
  for (const a of data.learned) {
    if (normalizeSearchText(a.term).startsWith(nq)) {
      out.set(a.hexseq, (out.get(a.hexseq) ?? 0) + a.score);
    }
  }
  return out;
}

// ─────────────────────────────────────────────────────────────────────────
// Store mutations (pure — return a NEW store; host persists it)
// ─────────────────────────────────────────────────────────────────────────

function cloneData(data: UnimagicData): UnimagicData {
  return {
    version: data.version,
    usage: data.usage.map((u) => ({ ...u })),
    learned: data.learned.map((a) => ({ ...a })),
  };
}

/**
 * Create-or-upvote one alias of a given type. If a `provisional` alias exists
 * and we're voting it as `learned`, it GRADUATES (type flips) and upvotes.
 * If a `learned` alias already exists, a weaker provisional vote for the same
 * pair upvotes the learned row rather than downgrading it.
 */
function voteAlias(
  next: UnimagicData,
  term: string,
  hexseq: string,
  type: "learned" | "provisional",
): void {
  const existing = findAlias(next, term, hexseq);
  if (existing) {
    // Never downgrade learned → provisional; a provisional voted as learned graduates.
    if (type === "learned" && existing.type === "provisional") {
      existing.type = "learned";
    }
    existing.score += SCORE.upVoteIncrement;
    return;
  }
  next.learned.push({
    term,
    hexseq,
    type,
    score: type === "learned" ? SCORE.learnedStart : SCORE.provisionalStart,
  });
}

/**
 * Apply the dual up-vote for a pick of `hexseq` after searching `query`.
 * Returns a new store. (Emotif upVote, plus Unimagic graduation.)
 */
export function upVote(
  data: UnimagicData,
  query: string,
  hexseq: string,
): UnimagicData {
  const next = cloneData(data);
  const { ultimate, penultimate } = parseForVoting(query);
  if (ultimate) voteAlias(next, ultimate, hexseq, "learned");
  if (penultimate) {
    // If the penultimate is already a learned alias for this glyph, strengthen
    // it (still upvote) rather than adding a competing provisional row.
    const learned = next.learned.find(
      (a) => a.term === penultimate && a.hexseq === hexseq && a.type === "learned",
    );
    if (learned) learned.score += SCORE.upVoteIncrement;
    else voteAlias(next, penultimate, hexseq, "provisional");
  }
  return next;
}

/**
 * Explicit "+ teach it a word" affordance: create-or-upvote a `provisional`
 * alias (design.md Tier 2 field 10). It graduates to `learned` on the next
 * pick where this word is the ultimate query word.
 */
export function teach(
  data: UnimagicData,
  term: string,
  hexseq: string,
): UnimagicData {
  const next = cloneData(data);
  const nt = normQuery(term);
  if (nt) voteAlias(next, nt, hexseq, "provisional");
  return next;
}

/** Remove a learned/provisional alias (the ✕ unlearn). Returns a new store. */
export function unlearn(
  data: UnimagicData,
  term: string,
  hexseq: string,
): UnimagicData {
  const next = cloneData(data);
  next.learned = next.learned.filter(
    (a) => !(a.term === term && a.hexseq === hexseq),
  );
  return next;
}

// ─────────────────────────────────────────────────────────────────────────
// Usage (frequently-used + usage boost)
// ─────────────────────────────────────────────────────────────────────────

/** Increment the usage tally for a glyph. Returns a new store. */
export function recordUsage(data: UnimagicData, hexseq: string): UnimagicData {
  const next = cloneData(data);
  const entry = next.usage.find((u) => u.hexseq === hexseq);
  if (entry) entry.count += 1;
  else next.usage.push({ hexseq, count: 1 });
  return next;
}

/** Top-N most-used glyph hexseqs, descending (design: "Frequently used" = top 25). */
export function frequentlyUsed(data: UnimagicData, n = 25): string[] {
  return [...data.usage]
    .sort((a: UsageEntry, b: UsageEntry) => b.count - a.count)
    .slice(0, n)
    .map((u) => u.hexseq);
}
