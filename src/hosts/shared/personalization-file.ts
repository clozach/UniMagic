import * as fs from "node:fs";
import * as path from "node:path";
import type { PersonalizationAccess, PersonalizationProvider } from "../../core/personalization-store";

/** Node and Tinycast's public fs shim both implement exclusive mkdir atomically.
 * The mutation is synchronous inside the lock; no cached snapshot can overwrite
 * another host's newer fields. A crashed owner's lock times out visibly rather
 * than guessing it is safe to remove a peer's reservation. */
export function personalizationFileProvider(file: string, access: PersonalizationAccess = "local", timeoutMs = 5_000): PersonalizationProvider {
  const lock = file + ".lock";
  const read = (): unknown => {
    try { return JSON.parse(fs.readFileSync(file, "utf8")); }
    catch (error) { if ((error as NodeJS.ErrnoException).code === "ENOENT") return {}; throw error; }
  };
  return {
    access,
    async read() { return read(); },
    async transaction<T>(change: (current: unknown) => { document: unknown; result: T }): Promise<T> {
      if (access === "shared-read-only") throw new Error("Personalization file is read-only");
      fs.mkdirSync(path.dirname(file), { recursive: true });
      const started = Date.now();
      while (true) {
        try { fs.mkdirSync(lock); break; }
        catch (error) {
          if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error;
          if (Date.now() - started >= timeoutMs) throw new Error("Personalization is busy; existing data preserved. Lock: " + lock);
          await new Promise(resolve => setTimeout(resolve, 10));
        }
      }
      const temporary = file + ".tmp-" + Date.now() + "-" + Math.random().toString(36).slice(2);
      try {
        const { document, result } = change(read());
        fs.writeFileSync(temporary, JSON.stringify(document, null, 2), "utf8");
        fs.renameSync(temporary, file);
        return result;
      } finally {
        if (fs.existsSync(temporary)) fs.unlinkSync(temporary);
        fs.rmdirSync(lock);
      }
    },
  };
}
