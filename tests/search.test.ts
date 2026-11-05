import { describe, test, expect } from "vitest";
import { buildIndex, search, resolveCodepoint } from "../src/core/search";
import { emptyData } from "../src/core/schema";
import type { Corpus } from "../src/core/schema";
import { upVote, unlearn } from "../src/core/learning";
import { rec, loadCorpus } from "./helpers";
import { pickedRecord, recordFor, skinVariants, tonedRecords } from "../src/core/glyphs";

const fixture: Corpus = {
  build: "test",
  records: [
    rec({ symbol: "→", hexseq: "2192", name: "rightwards arrow", set: "Arrows", order: 1, keywords: [{ token: "arrow", source: "cldr" }], signs: ["->"] }),
    rec({ symbol: "←", hexseq: "2190", name: "leftwards arrow", set: "Arrows", order: 2, keywords: [{ token: "arrow", source: "cldr" }], signs: ["<-"] }),
    rec({ symbol: "❤️", hexseq: "2764", name: "red heart", order: 3, keywords: [{ token: "heart", source: "cldr" }, { token: "love", source: "cldr" }], entities: ["heart"] }),
    rec({ symbol: "〰️", hexseq: "3030", name: "wavy dash", order: 4, keywords: [{ token: "wave", source: "cldr" }, { token: "squiggle", source: "cldr" }] }),
  ],
};

describe("search — fixture (deterministic core behavior)", () => {
  const index = buildIndex(fixture);

  test("sign query `->` matches via the signs field", () => {
    const hits = search({ index, data: emptyData() }, "->");
    expect(hits[0]?.hexseq).toBe("2192");
  });

  test("word query `arrow` returns both arrows, canonical order first", () => {
    const hits = search({ index, data: emptyData() }, "arrow");
    expect(hits.map((h) => h.hexseq)).toEqual(["2192", "2190"]);
  });

  test("codepoint `U+2764`, bare `2764`, and decimal all resolve to ❤", () => {
    for (const q of ["U+2764", "2764", "10084"]) {
      expect(search({ index, data: emptyData() }, q)[0]?.hexseq).toBe("2764");
    }
    expect(resolveCodepoint("U+2190", index.byId)).toEqual(["2190"]);
  });

  test("pasted glyph resolves to its record", () => {
    expect(search({ index, data: emptyData() }, "❤️")[0]?.hexseq).toBe("2764");
  });

  test("learned alias injects a glyph the corpus fields don't match", () => {
    const data = upVote(emptyData(), "wibble", "2764");
    expect(search({ index, data }, "wibble")[0]?.hexseq).toBe("2764");
  });

  test("unlearn reverts the injection", () => {
    const data = unlearn(upVote(emptyData(), "wibble", "2764"), "wibble", "2764");
    expect(search({ index, data }, "wibble")).toHaveLength(0);
  });

  test("a learned alias beats builtin ordering (design state 2)", () => {
    const data = upVote(emptyData(), "arrow", "2190");
    expect(search({ index, data }, "arrow")[0]?.hexseq).toBe("2190");
  });

  test("empty query returns nothing (caller shows browse grid)", () => {
    expect(search({ index, data: emptyData() }, "  ")).toHaveLength(0);
  });
});

// ── Query goldens against the REAL generated corpus (DoD #2). Skipped until
//    `just gen` has produced unimagic-corpus.json. ────────────────────────
describe("search — query goldens (real corpus)", () => {
  const corpus = loadCorpus();
  const t = corpus ? test : test.skip;
  const norm = (h: string) => h.replace(/\s*FE0F\s*/gi, " ").trim().toUpperCase();

  t("`arrow` surfaces arrows; teaching floats → to #1", () => {
    const index = buildIndex(corpus!);
    const isArrow = (r: { set?: string; name: string }) =>
      r.set === "Arrows" || /arrow/i.test(r.name);
    const fresh = search({ index, data: emptyData() }, "arrow");
    // Fresh corpus: the top hit is an arrow, and → is findable. No single arrow
    // is canonically #1 over the others (← is as valid as →); the mock's
    // →-first was a *learned* alias, asserted next.
    expect(isArrow(fresh[0].record)).toBe(true);
    expect(fresh.some((h) => norm(h.hexseq) === "2192")).toBe(true);
    // Teaching "arrow" → → makes it rank #1 (design state 2: learned beats builtin).
    const taught = upVote(emptyData(), "arrow", "2192");
    expect(norm(search({ index, data: taught }, "arrow")[0].hexseq)).toBe("2192");
  });

  t("`heart` → ❤ (U+2764) ranks #1", () => {
    const index = buildIndex(corpus!);
    expect(norm(search({ index, data: emptyData() }, "heart")[0].hexseq)).toBe("2764");
  });

  t("`U+2764` resolves to ❤", () => {
    const index = buildIndex(corpus!);
    expect(norm(search({ index, data: emptyData() }, "U+2764")[0].hexseq)).toBe("2764");
  });

  t("`->` returns arrows at the top", () => {
    const index = buildIndex(corpus!);
    const hits = search({ index, data: emptyData() }, "->");
    expect(hits.length).toBeGreaterThan(0);
    expect(hits[0].record.set === "Arrows" || /arrow/i.test(hits[0].record.name)).toBe(true);
  });
});

describe("search — words taught to a skin-tone variant", () => {
  const lotus = rec({ symbol: "🧘‍♀️", hexseq: "1F9D8 200D 2640", name: "woman in lotus position", order: 1, skinModifiable: true, keywords: [{ token: "yoga", source: "cldr" }] });
  const index = buildIndex({ build: "test", records: [lotus] });
  const light = "1F9D8 1F3FB 200D 2640";

  test("a word picked on 🧘🏻‍♀️ finds 🧘🏻‍♀️, not the base", () => {
    const data = upVote(emptyData(), "kk", light);
    const hits = search({ index, data }, "kk");
    expect(hits.map((h) => h.hexseq)).toEqual([light]);
    expect(hits[0].record.symbol).toBe("🧘\u{1F3FB}‍♀️");
    expect(hits[0].record.name).toBe("woman in lotus position: light skin tone");
    expect(hits[0].record.skinModifiable).toBe(false);
  });

  test("the base keeps its own words and tones", () => {
    const hits = search({ index, data: emptyData() }, "yoga");
    expect(hits.map((h) => h.hexseq)).toEqual(["1F9D8 200D 2640"]);
  });

  test("tonedRecords and recordFor agree on hexseq and glyph", () => {
    const tones = tonedRecords(lotus);
    expect(tones.map((r) => r.symbol)).toEqual(skinVariants(lotus).slice(1));
    expect(recordFor(index, light)?.symbol).toBe(tones[0].symbol);
    expect(recordFor(index, "1F9D8 1F3FB")).toBeUndefined();
  });

  test("pickedRecord maps a picked tone to its record, ignoring VS16", () => {
    const thumb = rec({ symbol: "👍\uFE0F", hexseq: "1F44D", name: "thumbs up", order: 2, skinModifiable: true });
    expect(pickedRecord(thumb, "👍🏻").hexseq).toBe("1F44D 1F3FB");
    expect(pickedRecord(thumb, "👍🏻\uFE0F").hexseq).toBe("1F44D 1F3FB");
    expect(pickedRecord(lotus, lotus.symbol)).toBe(lotus);
  });
});

describe("search — real corpus: KK → 🧘🏻‍♀️", () => {
  const corpus = loadCorpus();
  // ㏍ is named "square kk", so one pick lands 🧘🏻‍♀️ 4th, as for any glyph; the second wins.
  test.skipIf(!corpus)("a word picked twice on 🧘🏻‍♀️ ranks it first; the base keeps its own words", () => {
    const index = buildIndex(corpus!);
    const light = "1F9D8 1F3FB 200D 2640";
    let data = upVote(emptyData(), "yoga", "1F9D8 200D 2640");
    data = upVote(upVote(data, "kk", light), "kk", light);
    const hits = search({ index, data }, "kk");
    expect(hits[0].record.symbol).toBe("🧘🏻‍♀️");
    expect(search({ index, data }, "yoga")[0].hexseq).toBe("1F9D8 200D 2640");
  });
});
