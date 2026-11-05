#!/usr/bin/env node
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, copyFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { DatabaseSync } from 'node:sqlite';

const reference = JSON.parse(readFileSync(new URL('../../../../research/unichar-inventory.json', import.meta.url)));
const inventory = JSON.parse(readFileSync(new URL('../../Resources/BrowseInventory.json', import.meta.url)));
assert.equal(inventory.schemaVersion, 2);
assert.equal(inventory.categories.length, 354);
for (const source of reference.categories) {
  const category = inventory.categories.find(c => c.id === `unichar:${source.id}`);
  assert.ok(category, source.id);
  assert.deepEqual(category.sample.map(e => e.symbol), source.observed.map(e => e.glyph), source.name);
  assert.equal(category.defaultExemplar.symbol, source.index_icon.font_character);
}
assert.ok(process.argv[2], 'Pass unaugmented canonical corpus.sqlite');
const scratch = mkdtempSync(join(tmpdir(), 'unimagic-projection-test-'));
try {
  const output = join(scratch, 'corpus.sqlite');
  copyFileSync(process.argv[2], output);
  const original = new DatabaseSync(process.argv[2], { readOnly: true });
  const before = original.prepare('SELECT * FROM glyphs ORDER BY id').all();
  assert.equal(before.length, 39626);
  original.close();
  for (let pass = 0; pass < 2; pass++) {
    const run = spawnSync(process.execPath, [new URL('../../prepare-inventory.mjs', import.meta.url).pathname, output], { encoding: 'utf8' });
    assert.equal(run.status, 0, run.stderr);
    const db = new DatabaseSync(output, { readOnly: true });
    const lookup = db.prepare('SELECT * FROM glyphs WHERE id=?');
    for (const row of before) assert.deepEqual(lookup.get(row.id), row, `Canonical row changed: ${row.id}`);
    assert.equal(db.prepare('SELECT count(*) AS n FROM glyphs').get().n, 39694);
    assert.equal(db.prepare('SELECT count(*) AS n FROM browse_categories').get().n, 354);
    let observed = 0;
    for (const category of inventory.categories) {
      const read = table => db.prepare(`SELECT occurrence_id,glyph_id,symbol,name FROM ${table} WHERE category=? ORDER BY position`).all(category.id).map(row => ({ ...row }));
      const expected = entries => entries.map(e => ({ occurrence_id: e.occurrenceID, glyph_id: e.glyphID, symbol: e.symbol, name: e.name ?? null }));
      assert.deepEqual(read('browse_samples'), expected(category.sample), `Samples ${category.id}`);
      assert.deepEqual(read('browse_entries'), expected(category.membership.kind === 'explicit' ? category.membership.entries : []), `Membership ${category.id}`);
      if (category.source.kind === 'unichar-observed') observed += category.sample.length;
    }
    assert.equal(observed, 6825);
    for (const [sql, args, index] of [
      ['SELECT g.payload FROM glyphs g WHERE g.setname=? ORDER BY g.ord LIMIT ? OFFSET ?', ['Other Glyphs', 100, 37000], 'browse_set_order'],
      ["SELECT g.payload FROM glyphs g WHERE g.setname='Other Glyphs' AND json_extract(g.payload,'$.block')=? ORDER BY g.ord LIMIT ? OFFSET ?", ['Runic', 100, 0], 'browse_block_order'],
    ]) {
      const plan = db.prepare(`EXPLAIN QUERY PLAN ${sql}`).all(...args).map(r => r.detail).join(' ');
      assert.ok(plan.includes(index), plan);
      assert.ok(!/TEMP B-TREE/.test(plan), plan);
    }
    db.close();
  }
  console.log('Projection: 354 categories, 6825 exact observed samples, normalized full membership, canonical-row preservation, indexed late pages and repeat preparation pass');
} finally { rmSync(scratch, { recursive: true, force: true }); }
