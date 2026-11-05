import { describe, expect, test } from "vitest";
import { buildIndex, search } from "../src/core/search";
import { emptyData } from "../src/core/schema";
import { teach, learnedBoost } from "../src/core/learning";
import { loadCorpus, rec } from "./helpers";

const records = [
  rec({ symbol: "x", hexseq: "78", name: "letter x", order: 0 }),
  rec({ symbol: "❌", hexseq: "274C", name: "cross mark", order: 1, keywords: [{ token: "x", source: "cldr" }] }),
  rec({ symbol: "🩻", hexseq: "1FA7B", name: "x-ray", order: 2 }),
  rec({ symbol: "☒", hexseq: "2612", name: "ballot box with x", order: 3, keywords: [{ token: "red", source: "cldr" }] }),
  rec({ symbol: "→", hexseq: "2192", name: "arrow", signs: ["->"], order: 4 }),
];
const index = buildIndex({ build: "prefix-fixture", records });
const ids = (query: string, data = emptyData()) => search({ index, data }, query).map(h => h.hexseq);

describe("literal glyph and hyphen prefix regressions", () => {
  test("literal x ranks first without hiding its built-in word matches", () => {
    expect(ids("x")[0]).toBe("78");
    expect(ids("x")).toEqual(expect.arrayContaining(["274C", "1FA7B", "2612"]));
  });
  test("provisional and learned x aliases still inject otherwise unmatched glyphs", () => {
    for (const type of ["provisional", "learned"] as const) {
      const data = { ...emptyData(), learned: [{ hexseq: "2192", term: "x", type, score: 0 }] };
      expect(ids("x", data)).toContain("2192");
    }
  });
  test("the same early-return defect cannot hide aliases for other glyphs or bare hex", () => {
    for (const query of ["x", "→", "78", "2192"]) {
      const data = teach(emptyData(), query, "274C");
      expect(ids(query, data)).toContain("274C");
    }
    // Explicit U+ notation remains an intentional codepoint lookup.
    expect(ids("U+2192", teach(emptyData(), "U+2192", "274C"))).toEqual(["2192"]);
  });
  test("xr and x-r find x-ray without unrelated x-plus-r results", () => {
    expect(ids("xr")).toEqual(["1FA7B"]);
    expect(ids("x-r")).toEqual(ids("xr"));
    expect(ids("x-r")).not.toContain("2612");
  });
  test("adding characters to either spelling only narrows the candidate set", () => {
    for (const chain of [["x", "xr", "xra", "xray"], ["x", "x-", "x-r", "x-ra", "x-ray"]]) {
      for (let i = 1; i < chain.length; i++) {
        expect(ids(chain[i]).every(id => ids(chain[i - 1]).includes(id))).toBe(true);
      }
    }
  });
  test("hyphenated learned words have the same spelling rule as built-ins", () => {
    const data = teach(emptyData(), "x-rattle", "2192");
    expect(ids("xr", data)).toContain("2192");
    expect(ids("x-r", data)).toEqual(ids("xr", data));
    expect(learnedBoost(data, "x-r", "2192")).toBe(learnedBoost(data, "xr", "2192"));
  });
  test("standalone arrow and hyphen signs retain their whole-query matching", () => {
    expect(ids("->")).toEqual(["2192"]);
    expect(ids("-")).toEqual([]);
  });
});

const corpus = loadCorpus();
(corpus ? test : test.skip)("real corpus: cross mark is recalled and both x-ray spelling chains narrow", () => {
  const full = buildIndex(corpus!);
  const env = { index: full, data: teach(emptyData(), "x", "274C") };
  const result = (q: string) => search(env, q).map(h => h.hexseq);
  expect(result("x")).toContain("274C");
  expect(result("xr")).toContain("1FA7B");
  expect(result("x-r")).toEqual(result("xr"));
  for (const chain of [["x", "xr", "xray"], ["x", "x-", "x-r", "x-ray"]]) {
    for (let i = 1; i < chain.length; i++) {
      expect(result(chain[i]).every(id => result(chain[i - 1]).includes(id))).toBe(true);
    }
  }
});
