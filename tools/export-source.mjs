#!/usr/bin/env node
import { copyFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { sourceFiles, sourceFolders, publicSeeds, coreTests, pairedFolders, regularTree, mappedInput } from './source-layout.mjs';
import { auditSource } from './source-audit.mjs';

export function exportSource(root, destination) {
  if (existsSync(destination)) throw Error('Export destination must not exist.');
  mkdirSync(destination, { recursive: true });
  function copy(from, relative) {
    if (!existsSync(from)) throw Error(`Required portable source is missing: ${relative}`);
    const target = join(destination, relative);
    mkdirSync(dirname(target), { recursive: true });
    copyFileSync(from, target);
  }
  for (const file of sourceFiles) copy(join(root, file), file);
  for (const folder of sourceFolders) {
    const path = join(root, folder);
    if (!existsSync(path)) throw Error(`Required source directory is missing: ${folder}`);
    for (const entry of regularTree(path)) copy(entry.path, `${folder}/${entry.relative}`);
  }
  const seedRoot = mappedInput(root, 'seeds', '../seeds');
  for (const file of publicSeeds) copy(join(seedRoot, file), `seeds/${file}`);
  for (const file of coreTests) copy(join(root, 'tests', file), `tests/${file}`);
  for (const folder of pairedFolders) {
    const path = mappedInput(root, `tools/paired-mac/${folder}`, `../../iphone-agent-alerts/src/${folder}`);
    for (const entry of regularTree(path)) copy(entry.path, `tools/paired-mac/${folder}/${entry.relative}`);
  }
  writeFileSync(join(destination, 'vitest.config.ts'), 'import { defineConfig } from "vitest/config";\nexport default defineConfig({ test: { include: ["tests/*.test.ts"] } });\n');
  writeFileSync(join(destination, '.gitignore'), 'node_modules/\n.cache/\n.build/\nmacos/build/\nbuild-tinycast/\nios/build/\n*.xcodeproj/\nunimagic-corpus.json\nunimagic-corpus.json.gz\n');
  const manifest = auditSource(destination);
  return { destination, files: manifest.length, bytes: manifest.reduce((n, f) => n + f.bytes, 0), manifest };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.length !== 3) throw Error('Usage: node tools/export-source.mjs NEW_DESTINATION');
  const result = exportSource(resolve(dirname(fileURLToPath(import.meta.url)), '..'), resolve(process.argv[2]));
  console.log(JSON.stringify({ destination: result.destination, files: result.files, bytes: result.bytes }));
}
