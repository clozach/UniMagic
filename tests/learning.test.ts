import { describe, test, expect } from "vitest";
import { emptyData } from "../src/core/schema";
import {
  upVote,
  teach,
  unlearn,
  learnedBoost,
  learnedMatches,
  parseForVoting,
  aliasesFor,
} from "../src/core/learning";

describe("learning — Emotif dual up-vote + Unimagic graduation", () => {
  test("single-word pick creates a learned alias (start 1, +1 per repeat)", () => {
    let d = upVote(emptyData(), "squiggle", "3030");
    expect(d.learned).toEqual([
      { term: "squiggle", hexseq: "3030", type: "learned", score: 1 },
    ]);
    d = upVote(d, "squiggle", "3030");
    expect(d.learned[0].score).toBe(2);
  });

  test("dual signal: last word → learned(1), penultimate → provisional(0)", () => {
    expect(parseForVoting("wavy line")).toEqual({
      ultimate: "line",
      penultimate: "wavy",
    });
    const d = upVote(emptyData(), "wavy line", "3030");
    const learned = d.learned.find((a) => a.term === "line");
    const prov = d.learned.find((a) => a.term === "wavy");
    expect(learned).toMatchObject({ type: "learned", score: 1 });
    expect(prov).toMatchObject({ type: "provisional", score: 0 });
  });

  test("teach creates a provisional (score 0) that graduates to learned on next pick", () => {
    let d = teach(emptyData(), "squiggle", "3030");
    expect(d.learned[0]).toMatchObject({ type: "provisional", score: 0 });
    d = upVote(d, "squiggle", "3030");
    expect(d.learned).toHaveLength(1);
    expect(d.learned[0]).toMatchObject({ type: "learned", score: 1 });
  });

  test("unlearn removes the alias (ranking reverts) — DoD unlearn golden", () => {
    let d = upVote(emptyData(), "squiggle", "3030");
    expect(learnedBoost(d, "squiggle", "3030")).toBe(1);
    d = unlearn(d, "squiggle", "3030");
    expect(d.learned).toHaveLength(0);
    expect(learnedBoost(d, "squiggle", "3030")).toBe(0);
  });

  test("provisional at score 0 still injects recall via learnedMatches", () => {
    const d = teach(emptyData(), "wibble", "2764");
    const m = learnedMatches(d, "wibble");
    expect(m.get("2764")).toBe(0); // present (recall) even at score 0
  });

  test("prefix match contributes; unrelated query does not", () => {
    const d = upVote(upVote(emptyData(), "squiggle", "3030"), "squiggle", "3030");
    expect(learnedBoost(d, "squig", "3030")).toBe(2); // prefix
    expect(learnedBoost(d, "zzz", "3030")).toBe(0);
  });

  test("aliasesFor returns a glyph's chips", () => {
    let d = upVote(emptyData(), "squiggle", "3030");
    d = teach(d, "wavy", "3030");
    expect(aliasesFor(d, "3030").map((a) => a.term).sort()).toEqual([
      "squiggle",
      "wavy",
    ]);
  });

  test("immutable: source store is never mutated", () => {
    const base = emptyData();
    upVote(base, "x", "1F600");
    expect(base.learned).toHaveLength(0);
  });
});
