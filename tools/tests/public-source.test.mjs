import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, existsSync, symlinkSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { auditSource } from '../source-audit.mjs';
import { exportSource } from '../export-source.mjs';
import { sourceFiles, sourceFolders, publicSeeds, coreTests, pairedFolders } from '../source-layout.mjs';
import { publicReference } from '../reference-input.mjs';

function fixture(t) {
  const base = mkdtempSync(join(tmpdir(), 'unimagic-export-'));
  t.after(() => rmSync(base, { recursive: true, force: true }));
  const root = join(base, 'source'); mkdirSync(root);
  const put = (relative, text = '{}\n') => {
    const path = join(root, relative); mkdirSync(dirname(path), { recursive: true }); writeFileSync(path, text); return path;
  };
  return { base, root, put };
}

test('export contains required source inputs, not personal history or a copied icon font', t => {
  const f = fixture(t);
  for (const file of sourceFiles) f.put(file, file.endsWith('.json') ? '{}\n' : 'portable source\n');
  for (const folder of sourceFolders) f.put(`${folder}/entry.txt`);
  for (const seed of publicSeeds) f.put(`../seeds/${seed}`);
  for (const file of coreTests) f.put(`tests/${file}`);
  for (const folder of pairedFolders) f.put(`tools/paired-mac/${folder}/entry.mjs`);
  f.put('reference/unichar-inventory.json', JSON.stringify(publicReference(Buffer.from(JSON.stringify({
    font_sha256: 'a'.repeat(64), categories: [], dynamic_sections: { private_history: ['private'] }, evidence_directory: '/private/source',
  })))));
  f.put('../seeds/recents-screenshot-seed.json', '{"private":"personal history"}');
  f.put('ios/Resources/RecentsSeed.json', '{"private":"personal history"}');
  f.put('ios/Resources/UniCharCategories.ttf', 'font');
  f.put('macos/build/UniMagic.app/private.txt');
  f.put('node_modules/private.txt');
  const out = join(f.base, 'export');
  const result = exportSource(f.root, out);
  assert.ok(result.files > sourceFiles.length);
  assert.ok(existsSync(join(out, 'seeds/emotif-builtins.json')));
  assert.ok(existsSync(join(out, 'reference/unichar-inventory.json')));
  for (const path of ['seeds/recents-screenshot-seed.json', 'ios/Resources/RecentsSeed.json', 'ios/Resources/UniCharCategories.ttf', 'macos/build', 'node_modules']) {
    assert.equal(existsSync(join(out, path)), false, path);
  }
});

test('secrets and personal absolute paths reject a public snapshot', t => {
  const f = fixture(t);
  const cases = [
    ['-----BEGIN', 'PRIVATE KEY-----'].join(' '),
    'ghp_' + 'a'.repeat(40),
    ['', 'Users', 'c', 'private'].join('/'),
  ];
  for (const content of cases) {
    f.put('bad.txt', content);
    assert.throws(() => auditSource(f.root), /Public source rejected/);
  }
});

test('a symbolic link cannot smuggle external state into the source snapshot', t => {
  const f = fixture(t), outside = join(f.base, 'outside.txt');
  writeFileSync(outside, 'external state');
  symlinkSync(outside, join(f.root, 'link.txt'));
  assert.throws(() => auditSource(f.root), /symlink/);
});

test('public catalogue input strips observed Recents and machine capture metadata', t => {
  const result = publicReference(Buffer.from(JSON.stringify({
    font_sha256: 'a'.repeat(64),
    categories: [{ id: 'Category-Arrows', name: 'Arrows', index_icon: { font_character: '→', private_path: '/private' },
      observed: [{ glyph: '→', accessibility_name: 'Right arrow', captured: 'private' }], source_positions: [{ glyph: '→', capture: 'private' }] }],
    dynamic_sections: { recently_used: ['private'] }, evidence_directory: '/private', source_app: '/private',
  })));
  const text = JSON.stringify(result);
  assert.equal(text.includes('private'), false);
  assert.equal(result.categories[0].observed[0].glyph, '→');
  const f = fixture(t); f.put('reference/unichar-inventory.json', JSON.stringify({ ...result, dynamic_sections: {} }));
  assert.throws(() => auditSource(f.root), /dynamic history/);
});
