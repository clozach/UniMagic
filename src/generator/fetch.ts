/** Checksum-verified, atomic cache for pinned build-time Unicode sources. */
import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { createHash } from "node:crypto";
import { resolve } from "node:path";
import { get } from "node:https";

export const CACHE_DIR = resolve(process.cwd(), ".cache");

export interface PinnedSource {
  url: string;
  sha256: string;
}

function httpsGet(url: string): Promise<string> {
  return new Promise((resolvePromise, reject) => {
    get(url, (res) => {
      const status = res.statusCode ?? 0;
      if (status >= 300 && status < 400 && res.headers.location) {
        res.resume();
        httpsGet(new URL(res.headers.location, url).toString()).then(resolvePromise, reject);
        return;
      }
      if (status !== 200) {
        res.resume();
        reject(new Error(`HTTP ${status} for ${url}`));
        return;
      }
      const chunks: Buffer[] = [];
      res.on("data", (chunk) => chunks.push(chunk as Buffer));
      res.on("end", () => resolvePromise(Buffer.concat(chunks).toString("utf8")));
      res.on("error", reject);
    }).on("error", reject);
  });
}

function sha256(text: string): string {
  return createHash("sha256").update(text, "utf8").digest("hex");
}

export function verifyPinnedSource(filename: string, text: string, expected: string): string {
  const actual = sha256(text);
  if (actual !== expected) {
    throw new Error(
      `checksum mismatch for ${filename}: expected ${expected}, received ${actual}`,
    );
  }
  return text;
}

/**
 * Read a verified cache entry or fetch its pinned URL. Set
 * UNIMAGIC_REFRESH_SOURCES=1 for an explicit network refresh; a failed fetch or
 * checksum never replaces the last verified cache file.
 */
export async function getCached(filename: string, source: PinnedSource): Promise<string> {
  if (!existsSync(CACHE_DIR)) mkdirSync(CACHE_DIR, { recursive: true });
  const path = resolve(CACHE_DIR, filename);
  const refresh = process.env.UNIMAGIC_REFRESH_SOURCES === "1";
  if (existsSync(path) && !refresh) {
    return verifyPinnedSource(filename, readFileSync(path, "utf8"), source.sha256);
  }

  const text = verifyPinnedSource(filename, await httpsGet(source.url), source.sha256);
  const next = `${path}.next`;
  writeFileSync(next, text, "utf8");
  renameSync(next, path);
  return text;
}
