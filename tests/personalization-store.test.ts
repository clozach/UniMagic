import { afterEach, describe, expect, it } from "vitest";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { spawn } from "node:child_process";
import { createPersonalizationStore, PersonalizationReadOnlyError } from "../src/core/personalization-store";
import { personalizationFileProvider } from "../src/hosts/shared/personalization-file";
import type { HistoryEvent } from "../src/core/history-schema";

const roots: string[] = [];
function fixture() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "unimagic-personalization-")); roots.push(dir);
  const file = path.join(dir, "personalization.json");
  const make = () => createPersonalizationStore(personalizationFileProvider(file, "shared-read-write"), "catalogue-2");
  return { dir, file, make, store: make() };
}
const event = (id: string, occurredAt: number | null = null): HistoryEvent => ({ eventID: id, glyphID: "1F43B 200D 2744", symbol: "🐻‍❄️", occurredAt, provenance: { kind: "pick", host: "tinycast", action: "insert" } });
afterEach(() => { for (const dir of roots.splice(0)) fs.rmSync(dir, { recursive: true }); });

describe("versioned preferences and full history", () => {
  it("preserves explicit visibility, exact exemplars, unknown fields and learning", async () => {
    const f = fixture(); const learning = { version: 1, usage: [{ hexseq: "2764", count: 40 }], learned: [{ term: "old" }] };
    fs.writeFileSync(f.file, JSON.stringify({ settings: { future: true }, learning, futureRoot: { keep: 1 } }));
    await f.store.setCategoryEnabled("set:Emojis", false);
    await f.store.applyCategoryDefaults("photo", ["set:Emojis", "set:Dashes"]);
    await f.store.applyCategoryDefaults("photo", ["set:Quotes"]);
    let p = await f.store.setCategoryExemplar("set:Dashes", { kind: "emoji", symbol: "🐻‍❄️" });
    expect(p.categoryVisibility).toEqual({ "set:Emojis": false, "set:Dashes": true });
    expect(p.exemplarOverrides["set:Dashes"].symbol).toBe("🐻‍❄️");
    p = await f.store.setCategoryExemplar("set:Dashes", null); expect(p.exemplarOverrides).toEqual({});
    p = await f.store.setCategoryEnabled("__proto__", false); expect(Object.prototype.hasOwnProperty.call(p.categoryVisibility, "__proto__")).toBe(true);
    p = await f.store.applyCategoryDefaults("reserved-name", ["toString"]); expect(p.categoryVisibility.toString).toBe(true);
    const raw = JSON.parse(fs.readFileSync(f.file, "utf8")); expect(raw.learning).toEqual(learning); expect(raw.futureRoot).toEqual({ keep: 1 }); expect(raw.history.events).toEqual([]);
  });
  it("serializes independent instances without losing concurrent picks or preferences", async () => {
    const f = fixture(), other = f.make();
    await Promise.all(Array.from({ length: 80 }, async (_, n) => {
      const store = n % 2 ? f.store : other;
      await store.appendHistoryEvent(event("pick-" + n, n));
      await store.setCategoryEnabled("block:" + n, n % 2 === 0);
    }));
    expect((await f.store.readPreferences()).categoryVisibility).toHaveProperty("block:79", false);
    expect(Object.keys((await other.readPreferences()).categoryVisibility)).toHaveLength(80);
    let cursor: string | undefined; const ids: string[] = [];
    do {
      const page = await f.store.readHistoryPage({ cursor, limit: 9 }); expect(page.events.length).toBeLessThanOrEqual(9);
      ids.push(...page.events.map(x => x.eventID)); cursor = page.nextCursor ?? undefined;
      if (ids.length === 9) await other.appendHistoryEvent(event("new-live-pick", 1000));
    } while (cursor);
    expect(ids).toHaveLength(80); expect(new Set(ids).size).toBe(80);
  });
  it("coordinates two separate writer processes on the same file", async () => {
    const f = fixture();
    const script = `const { createPersonalizationStore } = require('./src/core/personalization-store.ts');
      const { personalizationFileProvider } = require('./src/hosts/shared/personalization-file.ts');
      (async()=>{
      const store=createPersonalizationStore(personalizationFileProvider(process.argv[1]),'test');
      for(let n=0;n<25;n++){ await store.appendHistoryEvent({eventID:process.argv[2]+n,glyphID:'2764',symbol:'❤️',occurredAt:n,provenance:{kind:'pick',host:'obsidian',action:'copy'}});await store.setCategoryEnabled(process.argv[2]+n,true); }
      })().catch(error=>{console.error(error);process.exitCode=1;});`;
    await Promise.all(["app", "tinycast"].map(owner => new Promise<void>((resolve, reject) => {
      const child = spawn(process.execPath, ["--require", "tsx/cjs", "-e", script, f.file, owner], { cwd: process.cwd(), stdio: ["ignore", "pipe", "pipe"] });
      let output = ""; child.stderr.on("data", chunk => { output += chunk; }); child.on("error", reject);
      child.on("exit", code => code === 0 ? resolve() : reject(new Error(output)));
    })));
    expect((await f.store.readHistoryPage({ limit: 100 })).events).toHaveLength(50);
    expect(Object.keys((await f.store.readPreferences()).categoryVisibility)).toHaveLength(50);
  });
  it("imports snapshot order without dates once and promotes later local picks idempotently", async () => {
    const f = fixture(); await f.store.appendHistoryEvent(event("live", 200));
    const snapshot = { importID: "photo", events: [event("photo-1"), event("photo-2")] };
    expect(await f.store.importHistory(snapshot)).toEqual({ imported: 2, alreadyApplied: false });
    expect(await f.store.importHistory(snapshot)).toEqual({ imported: 0, alreadyApplied: true });
    expect((await f.store.readHistoryPage({ limit: 10 })).events.map(x => x.eventID)).toEqual(["live", "photo-1", "photo-2"]);
    expect(await f.store.mergeHistoryEvents([event("local", 300)])).toBe(1);
    expect(await f.store.mergeHistoryEvents([event("local", 300), event("later-local", 400)])).toBe(1);
    expect((await f.store.readHistoryPage({ limit: 10 })).events[0].eventID).toBe("later-local");
    const parsed = JSON.parse(fs.readFileSync(f.file, "utf8")); expect(parsed.history.events.find((x: HistoryEvent) => x.eventID === "photo-1").occurredAt).toBeNull();
  });
  it("fills later verified snapshot cells under the same import ID at source positions", async () => {
    const f = fixture();
    const cell = (position: number): HistoryEvent => ({ ...event("cell-" + position), provenance: { kind: "snapshot-import", importID: "partial", source: "photo", position } });
    await f.store.importHistory({ importID: "partial", events: [cell(0), cell(2)] });
    await f.store.mergeHistoryEvents([event("other-unknown")]);
    expect(await f.store.importHistory({ importID: "partial", events: [cell(1)] })).toEqual({ imported: 1, alreadyApplied: false });
    expect((await f.store.readHistoryPage({ limit: 10 })).events.map(x => x.eventID)).toEqual(["cell-0", "cell-1", "cell-2", "other-unknown"]);
    expect(await f.store.importHistory({ importID: "partial", events: [cell(0), cell(1), cell(2)] })).toEqual({ imported: 0, alreadyApplied: true });
  });
  it("refuses malformed/newer documents and readonly writes without changing bytes", async () => {
    const f = fixture();
    for (const raw of ["not json", JSON.stringify({ personalizationVersion: 2 }), JSON.stringify({ history: { schemaVersion: 2, events: [], appliedImports: [] } })]) {
      fs.writeFileSync(f.file, raw); await expect(f.store.appendHistoryEvent(event("x"))).rejects.toThrow(); expect(fs.readFileSync(f.file, "utf8")).toBe(raw);
    }
    fs.writeFileSync(f.file, "{}"); await f.store.appendHistoryEvent(event("valid"));
    const before = fs.readFileSync(f.file, "utf8");
    const reader = createPersonalizationStore(personalizationFileProvider(f.file, "shared-read-only"), "catalogue-2");
    expect((await reader.readHistoryPage({ limit: 1 })).events).toHaveLength(1);
    await expect(reader.setCategoryEnabled("oops", true)).rejects.toBeInstanceOf(PersonalizationReadOnlyError);
    await expect(f.store.importHistory({ importID: "bad", events: [event("would-be-added"), { ...event("invalid"), symbol: "" }] })).rejects.toThrow();
    expect(fs.readFileSync(f.file, "utf8")).toBe(before); expect(fs.existsSync(f.file + ".lock")).toBe(false);
  });
});
