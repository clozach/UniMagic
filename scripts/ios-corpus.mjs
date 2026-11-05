#!/usr/bin/env node
// Generates a read-only full corpus; no runtime JSON corpus or MiniSearch allocation.
import { readFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { pathToFileURL } from 'node:url';
import { DatabaseSync } from 'node:sqlite';
import { build } from 'esbuild';
const root = resolve(dirname(new URL(import.meta.url).pathname), '..');
const output = process.argv[2] || '/tmp/unimagic-build/resources/corpus.sqlite';
// Import canonical constants and tokenizer through the existing build dependency.
const compiled = await build({stdin:{contents:'export {WEIGHTS,FIELD_BOOSTS,MINISEARCH_OPTIONS} from "./src/core/search"; export {SCORE,CURATED_SETS,CURRENT_DATA_VERSION} from "./src/core/schema"; export {skinVariants} from "./src/core/glyphs"; export {wordTokenize,normalizeSearchText} from "./src/core/search-text";',resolveDir:root},bundle:true,platform:'node',format:'esm',write:false});
const core = await import('data:text/javascript;base64,' + Buffer.from(compiled.outputFiles[0].text).toString('base64'));
const corpus = JSON.parse(readFileSync(resolve(root,'unimagic-corpus.json'),'utf8'));
mkdirSync(dirname(output),{recursive:true});
const db = new DatabaseSync(output);
db.exec('DROP TABLE IF EXISTS words; DROP TABLE IF EXISTS signs; DROP TABLE IF EXISTS glyphs; DROP TABLE IF EXISTS metadata; CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT); CREATE TABLE glyphs(id TEXT PRIMARY KEY,symbol TEXT,name TEXT,setname TEXT,firstcp TEXT,canonical TEXT,ord INTEGER,payload TEXT); CREATE INDEX symbol_lookup ON glyphs(symbol); CREATE INDEX cp_lookup ON glyphs(firstcp); CREATE INDEX canonical_lookup ON glyphs(canonical); CREATE TABLE signs(sign TEXT,id TEXT); CREATE INDEX sign_lookup ON signs(sign); CREATE VIRTUAL TABLE words USING fts5(id UNINDEXED,name,tags,entities,category,tokenize="unicode61 remove_diacritics 0",prefix="1 2 3 4"); BEGIN');
const glyph = db.prepare('INSERT INTO glyphs VALUES(?,?,?,?,?,?,?,?)');
const word = db.prepare('INSERT INTO words VALUES(?,?,?,?,?)');
const sign = db.prepare('INSERT INTO signs VALUES(?,?)');
const tokenize = s => core.wordTokenize(s || '').join(' ');
for (const r of corpus.records) {
  const tags = [...new Set(r.keywords.map(k=>k.token))];
  if(r.primaryShortcode) tags.push(...r.primaryShortcode.split('_'));
  const payload = {...r,id:r.hexseq,skinModifiable:!!r.skinModifiable,skinVariants:core.skinVariants(r)};
  delete payload.keywords; delete payload.signs;
  glyph.run(r.hexseq,r.symbol,r.name,r.set || null,parseInt(r.hexseq.split(' ')[0],16).toString(16).toUpperCase(),r.primaryShortcode?.toLowerCase() || null,r.order,JSON.stringify(payload));
  word.run(r.hexseq,tokenize(r.name),tokenize(tags.join(' ')),tokenize(r.entities.join(' ')),tokenize([r.set,r.block,r.script,r.group,r.subgroup].filter(Boolean).join(' ')));
  for(const s of r.signs) sign.run(s.toLowerCase(),r.hexseq);
}
const metadata = {build:corpus.build,count:corpus.records.length,weights:core.WEIGHTS,fieldBoosts:core.FIELD_BOOSTS,score:core.SCORE,sets:core.CURATED_SETS,version:core.CURRENT_DATA_VERSION,wordFields:core.MINISEARCH_OPTIONS.fields,ranking:'FTS5 BM25 prefix AND; canonical signal weights and curation prior. Intentional approximation: no MiniSearch fuzzy recall; BM25 scale differs; usage only orders browse. Exact pasted symbols, signs, codepoints and learned alias recall retain canonical weights.'};
for(const [key,value] of Object.entries(metadata)) db.prepare('INSERT INTO metadata VALUES(?,?)').run(key,JSON.stringify(value));
db.exec('COMMIT; VACUUM;'); db.close();
console.log(JSON.stringify({output,count:corpus.records.length,build:corpus.build}));
