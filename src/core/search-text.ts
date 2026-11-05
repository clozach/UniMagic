/** Word-search spelling: x-ray and xray share a prefix, including a trailing x-. */
export function normalizeSearchText(text: string): string {
  return text.toLowerCase().trim().replace(/(?<=[\p{L}\p{N}_])[-‐‑]+/gu, "");
}

/** Punctuation-only signs retain their separate whole-query lookup. */
export function wordTokenize(text: string): string[] {
  return normalizeSearchText(text).match(/[\p{L}\p{N}_]+/gu) ?? [];
}
