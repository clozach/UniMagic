import { describe, expect, test } from "vitest";
import { buildIndex, search } from "../src/core/search";
import { emptyData } from "../src/core/schema";
import { teach } from "../src/core/learning";
import { loadCorpus, rec } from "./helpers";

const corpus = loadCorpus();
const index = corpus && buildIndex(corpus);
const full = index ? test : test.skip;
const ids = (query: string, data = emptyData()) => search({ index: index!, data }, query).map(hit => hit.hexseq);

describe("pasted glyph presentation equivalence", () => {
  full("real corpus resolves bare, text and emoji presentations of the same symbol", () => {
    for (const [id, forms] of [
      ["00A9", ["©", "©︎", "©️"]],
      ["2665", ["♥", "♥︎", "♥️"]],
      ["2764", ["❤", "❤︎", "❤️"]],
    ] as const) for (const query of forms) expect(ids(query)[0], query).toBe(id);
  });
  full("presentation removal preserves ZWJ sequence identity", () => {
    expect(ids("❤‍🔥")[0]).toBe("2764 200D 1F525");
    expect(ids("👩‍⚕")[0]).toBe("1F469 200D 2695");
    expect(ids("❤")).not.toContain("2764 200D 1F525");
  });
  full("literal fallback retains learned recall and explicit codepoint priority", () => {
    const data = teach(emptyData(), "❤", "2192");
    expect(ids("❤", data)[0]).toBe("2764");
    expect(ids("❤", data)).toContain("2192");
    expect(ids("U+2764", teach(data, "U+2764", "2192"))[0]).toBe("2764");
    expect(ids("U+2764", teach(data, "U+2764", "2192"))).not.toContain("2192");
  });
  full("ordinary exact symbols, accents, signs and word prefixes retain their behavior", () => {
    expect(ids("→")[0]).toBe("2192");
    expect(ids("…")[0]).toBe("2026");
    expect(ids("🦉")[0]).toBe("1F989");
    expect(ids("é")[0]).toBe("00E9");
    expect(ids("->")).toContain("2192");
    expect(ids("xr")).toEqual(ids("x-r"));
    expect(ids("heart")[0]).toBe("2764");
  });
  test("an exact presentation remains preferred without injecting its alternate record", () => {
    const fixture = buildIndex({ build: "presentations", records: [
      rec({ symbol: "©️", hexseq: "00A9 FE0F", name: "emoji", order: 0 }),
      rec({ symbol: "©", hexseq: "00A9", name: "text", order: 1 }),
    ] });
    const found = (query: string) => search({ index: fixture, data: emptyData() }, query).map(hit => hit.hexseq);
    expect(found("©")).toEqual(["00A9"]);
    expect(found("©️")).toEqual(["00A9 FE0F"]);
    expect(found("©︎")).toEqual(["00A9 FE0F", "00A9"]);
  });
  test("other variation selectors and skin modifiers are never erased", () => {
    const fixture = buildIndex({ build: "variants", records: [
      rec({ symbol: "☀", hexseq: "2600", name: "sun", order: 0 }),
      rec({ symbol: "☀\uFE00", hexseq: "2600 FE00", name: "variant", order: 1 }),
      rec({ symbol: "👍", hexseq: "1F44D", name: "thumb", order: 2 }),
    ] });
    const found = (query: string) => search({ index: fixture, data: emptyData() }, query).map(hit => hit.hexseq);
    expect(found("☀\uFE00")).toEqual(["2600 FE00"]);
    expect(found("👍🏻")).toEqual([]);
  });
});
