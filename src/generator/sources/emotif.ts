/**
 * Emotif keyword seed (design.md input G — Al's own, provenance `emotif-builtin`).
 *
 * The exact built-in JSON is a portable, attributed seed. A missing default
 * seed fails the build rather than silently dropping inherited keywords.
 * Emotif's sequence encodings are
 * legacy (non-ZWJ, e.g. `1f469-2764-1f469`); reconciliation to modern RGI keys
 * happens at wire/coverage time via the ZWJ-loose index.
 */
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { normalizeHexseq } from "../normalize.js";

const localSeed = resolve(process.cwd(), "seeds", "emotif-builtins.json");
export const EMOTIF_PATH = process.env.UNIMAGIC_EMOTIF_SOURCE
  ?? (existsSync(localSeed) ? localSeed : resolve(process.cwd(), "..", "seeds", "emotif-builtins.json"));

export interface EmotifEntry {
  shortname: string;
  /** normalized (strict) hexseq — may not match a modern RGI key directly */
  hexseq: string;
  /** raw unicode spelling from the seed, for diagnostics */
  rawUnicode: string;
  name: string;
  keywords: string[];
  aliases: string[];
  asciiAliases: string[];
}

export interface EmotifData {
  entries: EmotifEntry[];
  available: boolean;
  path: string;
}

interface RawEmotif {
  unicode: string;
  name?: string;
  shortname?: string;
  keywords?: string[];
  aliases?: string[];
  aliases_ascii?: string[];
}

export function loadEmotif(path: string = EMOTIF_PATH): EmotifData {
  if (!existsSync(path)) {
    if (path === EMOTIF_PATH) throw new Error("Required Emotif built-in keyword seed is missing");
    return { entries: [], available: false, path };
  }
  const raw = JSON.parse(readFileSync(path, "utf8")) as Record<string, RawEmotif>;
  const entries: EmotifEntry[] = [];
  for (const [shortname, v] of Object.entries(raw)) {
    if (!v.unicode) continue;
    entries.push({
      shortname,
      hexseq: normalizeHexseq(v.unicode),
      rawUnicode: v.unicode,
      name: v.name ?? "",
      keywords: v.keywords ?? [],
      aliases: v.aliases ?? [],
      asciiAliases: v.aliases_ascii ?? [],
    });
  }
  return { entries, available: true, path };
}
