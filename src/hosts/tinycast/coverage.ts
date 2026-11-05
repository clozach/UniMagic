/**
 * No tofu: which glyphs this Mac cannot draw. The coverage helper (coverage.swift, built into
 * assets/ with the glyph list it reads) asks CoreText and writes the answer to the extension's
 * support folder, keyed to the corpus build and macOS version — fonts change only with the
 * system. `just tinycast-install` runs it once; after a macOS update the picker reruns it in
 * the background (several seconds) and stays usable meanwhile.
 */
import { execFile } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";

interface CoverageCache {
  key: string;
  missing: string[];
}

export interface CoveragePaths {
  helper: string;
  glyphs: string;
  cache: string;
}

export function coveragePaths(assetsPath: string, supportPath: string): CoveragePaths {
  return {
    helper: path.join(assetsPath, "unimagic-coverage"),
    glyphs: path.join(assetsPath, "glyphs.tsv"),
    cache: path.join(supportPath, "coverage.json"),
  };
}

/** Must match the key coverage.swift writes: corpus build, then the macOS version string. */
export function coverageKey(build: string, osVersion: string): string {
  return `${build} | ${osVersion}`;
}

export function readCoverage(cacheFile: string, key: string): Set<string> | null {
  try {
    const cache = JSON.parse(fs.readFileSync(cacheFile, "utf8")) as CoverageCache;
    return cache.key === key && Array.isArray(cache.missing) ? new Set(cache.missing) : null;
  } catch {
    return null;
  }
}

/** Run the helper, then read back what it cached. */
export function scanCoverage(paths: CoveragePaths, key: string): Promise<Set<string>> {
  return new Promise((resolve, reject) => {
    execFile(paths.helper, [paths.glyphs, paths.cache], (error) => {
      if (error) return reject(error);
      const found = readCoverage(paths.cache, key);
      if (found) resolve(found);
      else reject(new Error(`the scan finished but ${paths.cache} does not match ${key}`));
    });
  });
}
