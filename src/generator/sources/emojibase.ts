/**
 * emojibase-17 loader. Top-level entries become base records; skin-tone families
 * are collapsed (design.md merge recipe step 2 — the ~2k duplicated per-tone rows
 * carry zero search signal). We keep a skin→base index so skin-tone seed keys
 * still reconcile to their collapsed base.
 */
import { createRequire } from "node:module";
import { normalizeHexseq } from "../normalize.js";

const require = createRequire(import.meta.url);

interface EmojibaseSkin {
  hexcode: string;
  emoji?: string;
  text?: string;
  tone?: number | number[];
}

interface EmojibaseEntry {
  hexcode: string;
  label: string;
  emoji?: string;
  text?: string;
  group?: number;
  subgroup?: number;
  tags?: string[];
  order?: number;
  gender?: number;
  skins?: EmojibaseSkin[];
}

interface GroupsMeta {
  groups: Record<string, string>;
  subgroups: Record<string, string>;
}

/**
 * Canonical Unicode display names for the 10 emoji groups (kept explicit rather
 * than derived from emojibase's kebab-case meta, so `group` reads as design.md's
 * "Smileys & Emotion" example).
 */
const GROUP_NAMES: Record<number, string> = {
  0: "Smileys & Emotion",
  1: "People & Body",
  2: "Component",
  3: "Animals & Nature",
  4: "Food & Drink",
  5: "Travel & Places",
  6: "Activities",
  7: "Objects",
  8: "Symbols",
  9: "Flags",
};

export interface EmojiRecord {
  hexseq: string;
  label: string;
  /** Fully-qualified rendered glyph (emoji presentation preferred). */
  symbol: string;
  group?: string;
  subgroup?: string;
  tags: string[];
  order?: number;
  skinModifiable: boolean;
  textPresentation: boolean;
}

export interface EmojibaseData {
  /** base hexseq → collapsed emoji record */
  byKey: Map<string, EmojiRecord>;
  /** every skin-tone hexseq → its base hexseq (for seed reconciliation) */
  skinBaseOf: Map<string, string>;
  droppedSkins: number;
}

/**
 * emojibase's canonical shortcodes, keyed by normalized hexseq → primary
 * shortcode (first entry). Feeds the search-time canonicity bonus (design.md
 * Tier 1 ranking): the emoji whose primary shortcode exactly equals the query
 * is the canonical answer (❤ for "heart", not the decorated hearts).
 */
export function loadShortcodes(): Map<string, string> {
  const raw = require("emojibase-data/en/shortcodes/emojibase.json") as Record<
    string,
    string | string[]
  >;
  const out = new Map<string, string>();
  for (const [hexcode, sc] of Object.entries(raw)) {
    const primary = Array.isArray(sc) ? sc[0] : sc;
    if (!primary) continue;
    const key = normalizeHexseq(hexcode);
    if (!out.has(key)) out.set(key, primary);
  }
  return out;
}

export function loadEmojibase(): EmojibaseData {
  const data = require("emojibase-data/en/data.json") as EmojibaseEntry[];
  const meta = require("emojibase-data/meta/groups.json") as GroupsMeta;

  const byKey = new Map<string, EmojiRecord>();
  const skinBaseOf = new Map<string, string>();
  let droppedSkins = 0;

  for (const e of data) {
    const hexseq = normalizeHexseq(e.hexcode);
    const symbol = e.emoji || e.text || "";
    const group = e.group != null ? GROUP_NAMES[e.group] : undefined;
    const subgroup =
      e.subgroup != null ? meta.subgroups[String(e.subgroup)] : undefined;
    const rec: EmojiRecord = {
      hexseq,
      label: e.label,
      symbol,
      group,
      subgroup,
      tags: e.tags ?? [],
      order: e.order,
      skinModifiable: Array.isArray(e.skins) && e.skins.length > 0,
      textPresentation: Boolean(e.emoji && e.text),
    };
    byKey.set(hexseq, rec);
    if (e.skins) {
      for (const s of e.skins) {
        skinBaseOf.set(normalizeHexseq(s.hexcode), hexseq);
        droppedSkins++;
      }
    }
  }

  return { byKey, skinBaseOf, droppedSkins };
}
