import { describe, test, expect } from "vitest";
import { computeInsertion, insert } from "../src/core/compose";

describe("compose — insert-only (no trigger-word replacement)", () => {
  test("caret → glyph inserted verbatim, nothing adjacent touched", () => {
    expect(insert({ text: "party!", from: 6, to: 6 }, "🎉").text).toBe("party!🎉");
  });

  test("caret mid-line → plain insert, preceding word left intact", () => {
    expect(insert({ text: "let's party", from: 11, to: 11 }, "🎉").text).toBe(
      "let's party🎉",
    );
  });

  test("caret at line end → no auto-appended space", () => {
    expect(insert({ text: "party", from: 5, to: 5 }, "🎉").text).toBe("party🎉");
  });

  test("caret before following word text → no separating space", () => {
    expect(insert({ text: "partyfoo", from: 5, to: 5 }, "🎉").text).toBe(
      "party🎉foo",
    );
  });

  test("consecutive letter-class glyphs stack, never replace each other", () => {
    // ꪛ = U+AA9B TAI VIET LETTER HIGH BO (a \p{L} letter). The old trigger-word
    // rule treated it as a typed word and let the next pick eat it. Now it stays.
    expect(insert({ text: "ꪛ", from: 1, to: 1 }, "╳").text).toBe("ꪛ╳");
  });

  test("active selection is replaced verbatim (no trailing space)", () => {
    const slice = { text: "hello world", from: 0, to: 5 };
    expect(computeInsertion(slice, "🎉")).toEqual({ from: 0, to: 5, insert: "🎉" });
    expect(insert(slice, "🎉").text).toBe("🎉 world");
  });

  test("backwards selection is normalised", () => {
    expect(computeInsertion({ text: "hello", from: 5, to: 0 }, "🎉")).toEqual({
      from: 0,
      to: 5,
      insert: "🎉",
    });
  });

  test("caret after a space → plain insert", () => {
    expect(insert({ text: "a b", from: 2, to: 2 }, "🎉").text).toBe("a 🎉b");
  });

  test("empty document → just the glyph", () => {
    expect(insert({ text: "", from: 0, to: 0 }, "🎉").text).toBe("🎉");
  });
});
