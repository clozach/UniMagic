import { mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { recordUsage, teach, upVote } from "../src/core/learning";
import { CURRENT_DATA_VERSION } from "../src/core/schema";
import { expandHome, mutateShared, readShared } from "../src/hosts/tinycast/shared-store";

const dirs: string[] = [];
function pluginDir(): string {
  const dir = mkdtempSync(join(tmpdir(), "unimagic-shared-"));
  dirs.push(dir);
  return dir;
}
afterEach(() => {
  for (const dir of dirs.splice(0)) rmSync(dir, { recursive: true, force: true });
});

const obsidianFile = (settings: object, learned: object[] = []) =>
  JSON.stringify(
    {
      settings,
      learning: { version: CURRENT_DATA_VERSION, usage: [{ hexseq: "2014", count: 2 }], learned },
    },
    null,
    2,
  );

describe("the shared data.json (Tinycast host)", () => {
  test("a missing plugin folder turns learning off rather than creating one", () => {
    const file = join(pluginDir(), "absent", "data.json");
    expect(readShared(file).kind).toBe("missing");
    expect(mutateShared(file, (d) => recordUsage(d, "2014")).kind).toBe("missing");
    expect(existsSync(file)).toBe(false);
  });

  test("a plugin folder with no data.json yet starts empty and is created on the first pick", () => {
    const file = join(pluginDir(), "data.json");
    const read = readShared(file);
    expect(read.kind === "ready" && read.data.usage).toEqual([]);
    mutateShared(file, (d) => recordUsage(d, "2014"));
    expect(JSON.parse(readFileSync(file, "utf8")).learning.usage).toEqual([{ hexseq: "2014", count: 1 }]);
  });

  test("a pick keeps Obsidian's settings and unknown keys, and writes two-space JSON", () => {
    const file = join(pluginDir(), "data.json");
    const settings = { closeAfterInsert: false, clearSearchOnReopen: true, replayHints: false };
    writeFileSync(file, JSON.stringify({ ...JSON.parse(obsidianFile(settings)), extra: 7 }, null, 2));
    mutateShared(file, (d) => upVote(recordUsage(d, "2014"), "em dash", "2014"));
    const text = readFileSync(file, "utf8");
    const written = JSON.parse(text);
    expect(text).toBe(JSON.stringify(written, null, 2));
    expect(written.settings).toEqual(settings);
    expect(written.extra).toBe(7);
    expect(written.learning.usage).toEqual([{ hexseq: "2014", count: 3 }]);
    expect(written.learning.learned).toEqual([
      { term: "dash", hexseq: "2014", type: "learned", score: 1 },
      { term: "em", hexseq: "2014", type: "provisional", score: 0 },
    ]);
    expect(existsSync(join(file, "..", ".data.json.unimagic-tinycast"))).toBe(false);
  });

  test("a word Obsidian taught after the picker opened survives the next pick", () => {
    const file = join(pluginDir(), "data.json");
    writeFileSync(file, obsidianFile({}));
    const opened = readShared(file);
    expect(opened.kind).toBe("ready");
    // Obsidian learns a word while the Tinycast picker is open…
    writeFileSync(
      file,
      obsidianFile({}, [{ term: "squiggle", hexseq: "3030", type: "learned", score: 1 }]),
    );
    // …and the pick re-reads the file before writing, so the word stays.
    const after = mutateShared(file, (d) => teach(d, "dash", "2014"));
    expect(after.kind === "ready" && after.data.learned.map((a) => a.term)).toEqual(["squiggle", "dash"]);
  });

  test("a newer or malformed file is shown read-only and never overwritten", () => {
    const file = join(pluginDir(), "data.json");
    const newer = JSON.stringify({ learning: { version: CURRENT_DATA_VERSION + 1, usage: [], learned: [] } });
    writeFileSync(file, newer);
    expect(readShared(file).kind).toBe("unreadable");
    expect(mutateShared(file, (d) => recordUsage(d, "2014")).kind).toBe("unreadable");
    expect(readFileSync(file, "utf8")).toBe(newer);

    writeFileSync(file, "{ not json");
    expect(mutateShared(file, (d) => recordUsage(d, "2014")).kind).toBe("unreadable");
    expect(readFileSync(file, "utf8")).toBe("{ not json");
  });

  test("~ expands to the home folder only at the start of the path", () => {
    expect(expandHome("~/amaanah/data.json", "/Users/al")).toBe("/Users/al/amaanah/data.json");
    expect(expandHome("/tmp/~/data.json", "/Users/al")).toBe("/tmp/~/data.json");
  });
});
