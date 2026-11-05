/** One Mac-owned library; legacy originals remain untouched for rollback. */
import * as fs from "node:fs";
import * as path from "node:path";
import { homedir } from "node:os";

export function macLibrary(home = homedir()): string {
  return path.join(home, "Library", "Application Support", "UniMagic", "Library");
}
/** Find existing desktop stores through Obsidian's own portable vault registry. */
function legacyLibrary(home:string):string|undefined {
  const registry=path.join(home,"Library","Application Support","obsidian","obsidian.json");
  if (!fs.existsSync(registry)) return;
  const root=JSON.parse(fs.readFileSync(registry,"utf8")) as {vaults?:Record<string,{path?:string}>};
  const candidates=[...new Set(Object.values(root.vaults??{}).flatMap(v=>typeof v.path==="string"?[path.join(v.path,".obsidian","plugins","unimagic","data.json")]:[]))].filter(file=>fs.existsSync(file));
  if (candidates.length>1) throw new Error("Several legacy UniMagic libraries exist. Choose one with UNIMAGIC_LEGACY_DATA before first launch; none were changed.");
  return candidates[0];
}
/** Exact byte migration, protected against two simultaneous first launches. */
export function ensureMacLibrary(legacyFile?: string, home = homedir()): string {
  const dir = macLibrary(home);
  fs.mkdirSync(dir, { recursive: true });
  const ownedData=path.join(dir,"data.json");
  if (fs.existsSync(ownedData) && fs.existsSync(path.join(dir,"personalization-v1.json"))) return ownedData;
  const lock = path.join(dir, ".migration.lock");
  try { fs.mkdirSync(lock); }
  catch (error) { throw new Error(`UniMagic library migration is busy; retry after the other picker finishes. ${String(error)}`); }
  try {
    const legacy = legacyFile ?? legacyLibrary(home);
    if (!legacy) return path.join(dir,"data.json");
    const copies: {source:string;target:string;bytes:Buffer}[] = [];
    for (const name of ["data.json", "personalization-v1.json"]) {
      const target = path.join(dir, name);
      const source = name === "data.json" ? legacy : path.join(path.dirname(legacy), name);
      if (!fs.existsSync(target) && fs.existsSync(source)) {
        // Parse before copying; never replace a malformed source with empty data.
        const bytes = fs.readFileSync(source);
        const value: unknown = JSON.parse(bytes.toString("utf8"));
        if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(`Invalid legacy library: ${source}`);
        copies.push({source,target,bytes});
      }
    }
    for (const {target,bytes} of copies) {
      const temporary=target+".migrating";
      fs.writeFileSync(temporary,bytes);
      // Tinycast supports atomic rename but has no fsync shim; Node also flushes to disk.
      if (typeof fs.fsyncSync === "function") {
        const descriptor=fs.openSync(temporary,"r");try {fs.fsyncSync(descriptor);} finally {fs.closeSync(descriptor);}
      }
      fs.renameSync(temporary,target);
      if (!fs.readFileSync(target).equals(bytes)) throw new Error(`Migration readback failed: ${target}`);
    }
    return path.join(dir, "data.json");
  } finally { fs.rmdirSync(lock); }
}
