#!/usr/bin/env -S pnpm exec tsx
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { buildBrowseCatalogue, type BrowseReference, type BrowseSeed } from "../src/generator/browse-catalogue";
import type { Corpus } from "../src/core/schema";

const root = new URL("../", import.meta.url);
const portableReference = new URL("reference/unichar-inventory.json", root);
const referenceBytes = readFileSync(existsSync(portableReference) ? portableReference : new URL("../research/unichar-inventory.json", root));
const corpus = JSON.parse(readFileSync(new URL("unimagic-corpus.json", root), "utf8")) as Corpus;
const reference = JSON.parse(referenceBytes.toString()) as BrowseReference & { source_sha256?: string };
const portableSeed = new URL("seeds/browse-catalogue.json", root);
const seed = JSON.parse(readFileSync(existsSync(portableSeed) ? portableSeed : new URL("../seeds/browse-catalogue.json", root), "utf8")) as BrowseSeed;
const blocks = Object.fromEntries(readFileSync(new URL(".cache/Blocks.txt", root), "utf8").split("\n").flatMap(line => {
  const match = line.match(/^([0-9A-F]+)\.\.[0-9A-F]+;\s*(.+)$/);
  return match ? [[match[2].trim(), Number.parseInt(match[1], 16)]] : [];
}));
const catalogue = buildBrowseCatalogue(corpus, reference, seed, reference.source_sha256 ?? createHash("sha256").update(referenceBytes).digest("hex"), blocks);
writeFileSync(new URL("ios/Resources/BrowseInventory.json", root), JSON.stringify(catalogue) + "\n");
console.log(JSON.stringify({ revision: catalogue.revision, ...catalogue.counts, bytes: JSON.stringify(catalogue).length }));
