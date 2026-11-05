/**
 * Unimagic core — insert-at-cursor rule. Pure string math; the Obsidian editor
 * wiring (editor.replaceRange + cursor placement) lives in the picker.
 * Isomorphic: no Node, no DOM.
 *
 * Insert-only: an active selection is replaced with the glyph, a bare caret gets
 * the glyph verbatim. Adjacent text is never touched.
 *
 * This deliberately does NOT do Emotif's `String+EmojiMerging` trigger-word
 * replacement ("party!" → "🎉!", auto-space). That silently mutated neighbouring
 * text: a previously-inserted letter-class glyph — a Tai Viet or Cham letter,
 * a letterlike symbol, CJK — is `\p{L}`, indistinguishable from a typed word, so
 * the next pick would eat it (╳ replacing ꪛ; fault-ledger). Inserting runs of
 * Unicode must be lossless, so glyph insertion never rewrites what's already
 * there. Word→glyph learning still happens on pick (that's the picker's job) —
 * only the glyph↔glyph adjacency behaviour was removed.
 */

/** A slice of editor state: full text + selection. `from===to` means a caret. */
export interface EditorSlice {
  text: string;
  from: number;
  to: number;
}

/** A replacement to apply: `text.slice(from,to)` becomes `insert`. */
export interface Insertion {
  from: number;
  to: number;
  insert: string;
}

/**
 * Compute the edit for inserting `glyph` given editor `slice`.
 *
 * - Active selection (`to > from`) → replace exactly that range with the glyph.
 * - Bare caret (`to === from`) → insert the glyph at the caret, verbatim.
 *
 * Adjacent text is never inspected or rewritten, so inserting a run of glyphs is
 * lossless. `Math.min`/`Math.max` normalise a backwards selection.
 */
export function computeInsertion(slice: EditorSlice, glyph: string): Insertion {
  const from = Math.min(slice.from, slice.to);
  const to = Math.max(slice.from, slice.to);
  return { from, to, insert: glyph };
}

/** Apply an insertion, returning the new text and resulting caret offset. */
export function applyInsertion(
  slice: EditorSlice,
  ins: Insertion,
): { text: string; cursor: number } {
  const text = slice.text.slice(0, ins.from) + ins.insert + slice.text.slice(ins.to);
  return { text, cursor: ins.from + ins.insert.length };
}

/** Convenience: compute + apply in one call (used by goldens). */
export function insert(
  slice: EditorSlice,
  glyph: string,
): { text: string; cursor: number } {
  return applyInsertion(slice, computeInsertion(slice, glyph));
}
