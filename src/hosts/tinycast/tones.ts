/**
 * Skin tones: the six presentations of a tone-capable emoji, in Unicode's order, and the default
 * tone a pick uses. Pure, so the suite drives it; tone-state.ts persists the default.
 */
import type { CorpusRecord } from "../../core";
import { skinVariants } from "../../core/glyphs";

export const TONES = [
  { id: "none", name: "No skin tone" },
  { id: "light", name: "Light" },
  { id: "mediumLight", name: "Medium-light" },
  { id: "medium", name: "Medium" },
  { id: "mediumDark", name: "Medium-dark" },
  { id: "dark", name: "Dark" },
] as const;

export type ToneId = (typeof TONES)[number]["id"];

/** Anything stored that is not a known tone reads as none, so a bad value never hides a glyph. */
export function parseTone(raw: unknown): ToneId {
  return TONES.find((t) => t.id === raw)?.id ?? "none";
}

export function toneName(tone: ToneId): string {
  return TONES.find((t) => t.id === tone)?.name ?? "No skin tone";
}

/** The glyph in `tone`, or the glyph itself when it has no tones. */
export function toned(record: CorpusRecord, tone: ToneId): string {
  const variants = skinVariants(record);
  return variants[TONES.findIndex((t) => t.id === tone)] ?? record.symbol;
}
