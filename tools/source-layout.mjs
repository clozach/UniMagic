import { existsSync, lstatSync, readdirSync } from 'node:fs';
import { join, resolve } from 'node:path';

export const sourceFiles = [
  'README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'VERSION', 'CHANGES.md',
  'package.json', 'pnpm-lock.yaml', 'pnpm-workspace.yaml', 'tsconfig.json',
  'source-manifest.json', 'release-product.json', 'esbuild.macos.mjs', 'esbuild.tinycast.mjs', 'Justfile',
  'src/types.d.ts',
];
export const sourceFolders = [
  'src/core', 'src/generator', 'src/hosts/shared', 'src/hosts/macos',
  'src/hosts/tinycast', 'macos', 'ios', 'release-kit', 'tools', 'scripts', 'licenses', 'reference',
];
export const publicSeeds = [
  'gf-tag-delta.json', 'gf-sets.json', 'gf-entity-lookup.js', 'GLYPHFINDER-NOTICE.md',
  'browse-catalogue.json', 'emotif-builtins.json', 'EMOTIF-NOTICE.md',
];
export const coreTests = [
  'helpers.ts', 'compose.test.ts', 'corpus.test.ts', 'encodings.test.ts',
  'learning.test.ts', 'search.test.ts', 'search-prefix.test.ts', 'search-presentation.test.ts',
  'personalization-store.test.ts', 'tinycast-shared-store.test.ts',
];
export const pairedFolders = ['keeper', 'signing'];
const ignoredParts = new Set(['node_modules', 'build', '.build', '.cache', '.git', '.DS_Store']);
const forbiddenNames = new Set(['UniCharCategories.ttf', 'RecentsSeed.json', 'recents-screenshot-seed.json']);

export function exportable(relative) {
  const parts = relative.split('/');
  return !parts.some(p => ignoredParts.has(p) || p.startsWith('.'))
    && !parts.some(p => forbiddenNames.has(p))
    && !relative.includes('.xcodeproj/') && !relative.endsWith('.xcodeproj')
    && !relative.startsWith('tools/private/');
}

export function regularTree(root, prefix = '') {
  const result = [];
  for (const entry of readdirSync(root, { withFileTypes: true })) {
    const relative = prefix ? `${prefix}/${entry.name}` : entry.name;
    if (!exportable(relative)) continue;
    const path = join(root, entry.name);
    if (lstatSync(path).isSymbolicLink()) throw Error(`Source symlink is not exportable: ${relative}`);
    if (entry.isDirectory()) result.push(...regularTree(path, relative));
    else if (entry.isFile()) result.push({ relative, path });
  }
  return result;
}

export function mappedInput(root, relative, fallback) {
  const local = resolve(root, relative);
  return existsSync(local) ? local : resolve(root, fallback);
}
