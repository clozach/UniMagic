/**
 * UTS #39 confusables loader — the visual/security-confusability half of the
 * Twins relation (design.md Tier 2 field 7).
 *
 * Unicode security data lags the main UCD, so its independently pinned version
 * comes from source-manifest.json. Its checksum is mandatory: silently dropping
 * the security half of Twins would make an annual build look healthier than it is.
 */
import { getCached } from "../fetch.js";
import manifest from "../../../source-manifest.json";

export interface Confusables {
  /** source codepoint → prototype/skeleton string it maps to */
  map: Map<number, string>;
  sourceUrl: string;
  available: boolean;
}

/** Parse `SRC ; TGT TGT … ; TYPE # comment` data lines into a source→target map. */
function parse(text: string): Map<number, string> {
  const map = new Map<number, string>();
  for (const line of text.split("\n")) {
    if (line.length === 0 || line[0] === "#") continue;
    const hash = line.indexOf("#");
    const body = (hash >= 0 ? line.slice(0, hash) : line).trim();
    if (body.length === 0) continue;
    const parts = body.split(";");
    if (parts.length < 2) continue;
    const srcHexes = parts[0].trim().split(/\s+/);
    if (srcHexes.length !== 1) continue; // single-codepoint sources only
    const src = parseInt(srcHexes[0], 16);
    if (Number.isNaN(src)) continue;
    const targetCps = parts[1]
      .trim()
      .split(/\s+/)
      .map((h) => parseInt(h, 16))
      .filter((n) => !Number.isNaN(n));
    if (targetCps.length === 0) continue;
    map.set(src, String.fromCodePoint(...targetCps));
  }
  return map;
}

export async function loadConfusables(): Promise<Confusables> {
  const source = manifest.files["confusables.txt"];
  const text = await getCached("confusables.txt", source);
  return { map: parse(text), sourceUrl: source.url, available: true };
}
