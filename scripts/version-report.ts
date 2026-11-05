import { existsSync, readFileSync } from "node:fs";
import { basename, resolve } from "node:path";
import type { Corpus } from "../src/core/schema";
import manifest from "../source-manifest.json";

function readCorpus(path: string): Corpus | null {
  if (!existsSync(path)) return null;
  return JSON.parse(readFileSync(path, "utf8")) as Corpus;
}

const previousPath = resolve(process.argv[2] ?? "");
const currentPath = resolve(process.argv[3] ?? "unimagic-corpus.json");
const previous = readCorpus(previousPath);
const current = readCorpus(currentPath);

if (!current) throw new Error(`missing regenerated corpus: ${currentPath}`);

const before = previous?.records.length ?? 0;
const after = current.records.length;
const delta = after - before;
const sign = delta >= 0 ? "+" : "";

console.log("Annual source/version report");
console.log(
  `  pinned: Unicode ${manifest.unicode}; security ${manifest.security}; ` +
    `emojibase ${manifest.emojibase}`,
);
console.log(`  previous: ${previous ? `${before} records (${previous.build})` : "none"}`);
console.log(`  current:  ${after} records (${current.build})`);
console.log(`  delta:    ${sign}${delta} records`);
console.log(`  artifact: ${basename(currentPath)}`);
