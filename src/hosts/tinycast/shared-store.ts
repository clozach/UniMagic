/**
 * The Mac-owned learning library, shared by native UniMagic and Tinycast.
 * Every mutation locks, re-reads current bytes, preserves settings/unknown fields,
 * and atomically swaps a unique temporary file. Busy writers fail without losing data.
 */
import * as fs from "node:fs";
import * as path from "node:path";
import { emptyData, type UnimagicData } from "../../core/schema";
import { migrate } from "../../core/store-schema";

export type SharedData =
  | { kind: "ready"; data: UnimagicData }
  /** The configured library folder is absent, so learning is off. */
  | { kind: "missing"; dir: string }
  /** Malformed or from a newer Unimagic: shown read-only, never overwritten. */
  | { kind: "unreadable"; file: string; reason: string };

const TEMP_NAME = ".data.json.unimagic-tinycast";

export function expandHome(file: string, home: string): string {
  return file === "~" || file.startsWith("~/") ? path.join(home, file.slice(1)) : file;
}

function readRoot(file: string): Record<string, unknown> {
  if (!fs.existsSync(file)) return {};
  const parsed: unknown = JSON.parse(fs.readFileSync(file, "utf8"));
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("data.json is not a JSON object");
  }
  return parsed as Record<string, unknown>;
}

export function readShared(file: string): SharedData {
  const dir = path.dirname(file);
  if (!fs.existsSync(dir)) return { kind: "missing", dir };
  try {
    const root = readRoot(file);
    return { kind: "ready", data: fs.existsSync(file) ? migrate(root).data.learning : emptyData() };
  } catch (error) {
    return { kind: "unreadable", file, reason: (error as Error).message };
  }
}

/** Apply one learning change to the file's current contents and write it back. */
export function mutateShared(file: string, change: (data: UnimagicData) => UnimagicData): SharedData {
  const dir = path.dirname(file);
  if (!fs.existsSync(dir)) return { kind: "missing", dir };
  const lock = file + ".lock";
  try { fs.mkdirSync(lock); } catch (error) { return { kind: "unreadable", file, reason: "Library busy; pick again after the other picker finishes. " + String(error) }; }
  try {
    let root: Record<string, unknown>;
    let migrated: ReturnType<typeof migrate>["data"];
    try {
      root = readRoot(file);
      migrated = migrate(root).data;
    } catch (error) {
      return { kind: "unreadable", file, reason: (error as Error).message };
    }
    const learning = change(migrated.learning);
    const next = { ...root, settings: root.settings ?? migrated.settings, learning };
    const temp = path.join(dir, TEMP_NAME + "-" + Date.now() + "-" + Math.random().toString(36).slice(2));
    // Obsidian's own saveData writes two-space JSON; matching it keeps git and Sync diffs small.
    fs.writeFileSync(temp, JSON.stringify(next, null, 2), "utf8");
    fs.renameSync(temp, file);
    return { kind: "ready", data: learning };
  } finally { fs.rmdirSync(lock); }
}
