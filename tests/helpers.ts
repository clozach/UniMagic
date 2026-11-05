import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import type { Corpus, CorpusRecord } from "../src/core/schema";

/** Load the generated corpus, or null if `just gen` hasn't been run yet.
 * The path is resolved lazily so importing `rec` (e.g. from a happy-dom test,
 * where import.meta.url isn't a file URL) never touches fileURLToPath. */
export function loadCorpus(): Corpus | null {
  const path = fileURLToPath(new URL("../unimagic-corpus.json", import.meta.url));
  if (!existsSync(path)) return null;
  return JSON.parse(readFileSync(path, "utf8")) as Corpus;
}

/** Minimal corpus-record factory for deterministic unit fixtures. */
export function rec(p: Partial<CorpusRecord> & Pick<CorpusRecord, "symbol" | "hexseq" | "name" | "order">): CorpusRecord {
  return {
    entities: [],
    keywords: [],
    signs: [],
    twins: [],
    related: [],
    ...p,
  };
}
