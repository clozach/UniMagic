import { describe, test, expect } from "vitest";
import { CURATED_SETS } from "../src/core/schema";
import { loadCorpus } from "./helpers";

// Structural + coverage goldens over the generated corpus (DoD #2). Skipped
// until `just gen` has produced unimagic-corpus.json. The generator emits its
// own seed-key coverage assertion at build time; these are an independent
// second check on the shipped artifact.
describe("corpus — structural + coverage goldens (real corpus)", () => {
  const corpus = loadCorpus();
  const t = corpus ? test : test.skip;
  const norm = (h: string) => h.replace(/\s*FE0F\s*/gi, " ").trim().toUpperCase();

  t("no duplicate hexseq keys", () => {
    const seen = new Set<string>();
    const dups: string[] = [];
    for (const r of corpus!.records) {
      if (seen.has(r.hexseq)) dups.push(r.hexseq);
      seen.add(r.hexseq);
    }
    expect(dups).toEqual([]);
  });

  t("every `set` is one of the known curated sets", () => {
    const known = new Set<string>(CURATED_SETS);
    const bad = corpus!.records
      .map((r) => r.set)
      .filter((s): s is NonNullable<typeof s> => s != null && !known.has(s));
    expect([...new Set(bad)]).toEqual([]);
  });

  t("record count is sane (union corpus, CJK/Hangul excluded)", () => {
    expect(corpus!.records.length).toBeGreaterThan(20000);
  });

  t("landmark glyphs are present with expected keys", () => {
    const keys = new Set(corpus!.records.map((r) => norm(r.hexseq)));
    for (const k of ["2014", "2192", "2764", "1F600", "1F389"]) {
      expect(keys.has(k)).toBe(true);
    }
  });

  t("every record has a rendered symbol and a name", () => {
    const broken = corpus!.records.filter((r) => !r.symbol || !r.name);
    expect(broken.map((r) => r.hexseq)).toEqual([]);
  });
});
