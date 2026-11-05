#!/usr/bin/env node
// Native projection: canonical glyph rows are never edited; membership is normalized.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { DatabaseSync } from 'node:sqlite';

const resource = name => new URL(`Resources/${name}`, import.meta.url);
const inventory = JSON.parse(readFileSync(resource('BrowseInventory.json'), 'utf8'));
if (inventory.schemaVersion !== 2 || inventory.counts.collections !== 36 || inventory.counts.blocks !== 316)
  throw Error('Invalid shared browse catalogue');
if (inventory.counts.observedSampleOccurrences !== 6825 || inventory.counts.supplements !== 68)
  throw Error('Observed UniChar sample/supplement preservation failed');
if (!process.argv[2]) throw Error('Usage: node prepare-inventory.mjs <generated/corpus.sqlite>');

const database = new DatabaseSync(process.argv[2]);
const byID = database.prepare('SELECT id,symbol,payload FROM glyphs WHERE id=?');
const insertGlyph = database.prepare('INSERT INTO glyphs VALUES(?,?,?,?,?,?,?,?)');
const insertWords = database.prepare('INSERT INTO words VALUES(?,?,?,?,?)');
const tokenize = value => (value.toLowerCase().replace(/(?<=[\p{L}\p{N}_])[-‐‑]+/gu, '').match(/[\p{L}\p{N}_]+/gu) || []).join(' ');
let order = database.prepare('SELECT max(ord) AS value FROM glyphs').get().value + 1;
let added = 0;

try {
  database.exec(`BEGIN;
    DROP TABLE IF EXISTS browse_samples;
    DROP TABLE IF EXISTS browse_entries;
    DROP TABLE IF EXISTS browse_categories;
    CREATE TABLE browse_categories(position INTEGER PRIMARY KEY,category TEXT UNIQUE,title TEXT,symbol TEXT,definition TEXT);
    CREATE TABLE browse_entries(category TEXT,position INTEGER,occurrence_id TEXT UNIQUE,glyph_id TEXT,symbol TEXT,name TEXT,PRIMARY KEY(category,position));
    CREATE TABLE browse_samples(category TEXT,position INTEGER,occurrence_id TEXT,glyph_id TEXT,symbol TEXT,name TEXT,PRIMARY KEY(category,position));
    CREATE INDEX browse_glyph_context ON browse_entries(glyph_id,category,position);
    CREATE INDEX browse_sample_context ON browse_samples(glyph_id,category,position);
    CREATE INDEX IF NOT EXISTS browse_corpus_order ON glyphs(ord);
    CREATE INDEX IF NOT EXISTS browse_set_order ON glyphs(setname,ord);
    CREATE INDEX IF NOT EXISTS browse_block_order ON glyphs(setname,json_extract(payload,'$.block'),ord);`);
  for (const entry of inventory.supplements) {
    const existing = byID.get(entry.glyphID);
    if (existing) {
      if (existing.symbol !== entry.symbol) throw Error(`Refusing to overwrite canonical glyph ${entry.glyphID}`);
      continue;
    }
    const payload = {
      id: entry.glyphID, symbol: entry.symbol, name: entry.name, set: 'UniChar supplement',
      skinModifiable: false, entities: [], twins: [], related: [], skinVariants: [],
      annotations: ['Observed UniChar category inventory; native supplement']
    };
    const firstcp = entry.symbol.codePointAt(0).toString(16).toUpperCase();
    insertGlyph.run(entry.glyphID, entry.symbol, entry.name, payload.set, firstcp, null, order++, JSON.stringify(payload));
    insertWords.run(entry.glyphID, tokenize(entry.name), '', '', tokenize(payload.set));
    added++;
  }
  const categoryRow = database.prepare('INSERT INTO browse_categories VALUES(?,?,?,?,?)');
  const occurrence = database.prepare('INSERT INTO browse_entries VALUES(?,?,?,?,?,?)');
  const sample = database.prepare('INSERT INTO browse_samples VALUES(?,?,?,?,?,?)');
  const storeEntry = (statement, category, entry, position) => {
    if (!byID.get(entry.glyphID)) throw Error(`Unknown member ${entry.glyphID} in ${category}`);
    statement.run(category, position, entry.occurrenceID, entry.glyphID, entry.symbol, entry.name ?? null);
  };
  for (const [position, category] of inventory.categories.entries()) {
    const { membership, sample: samples, ...definition } = category;
    categoryRow.run(position, category.id, category.title, category.defaultExemplar.symbol,
      JSON.stringify({ ...definition, membership: { kind: membership.kind } }));
    samples.forEach((entry, index) => storeEntry(sample, category.id, entry, index));
    if (membership.kind === 'explicit') membership.entries.forEach((entry, index) => storeEntry(occurrence, category.id, entry, index));
  }
  const count = database.prepare('SELECT count(*) AS value FROM glyphs').get().value;
  const metadata = database.prepare('INSERT OR REPLACE INTO metadata VALUES(?,?)');
  metadata.run('count', JSON.stringify(count));
  metadata.run('nativeBrowse', JSON.stringify({ schemaVersion: 2, revision: inventory.revision, sourceSHA256: inventory.sourceSHA256, ...inventory.counts }));
  database.exec('COMMIT; VACUUM;');
  console.log(JSON.stringify({ output: process.argv[2], categories: inventory.categories.length, ...inventory.counts, added, count, resource: fileURLToPath(resource('BrowseInventory.json')) }));
} catch (error) {
  database.exec('ROLLBACK');
  throw error;
} finally { database.close(); }
