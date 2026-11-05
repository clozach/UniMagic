#!/usr/bin/env node
/** Synthetic end-to-end desktop bridge acceptance; never opens the personal library. */
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,rmSync,mkdirSync,writeFileSync,readFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {createInterface} from 'node:readline';
import assert from 'node:assert/strict';
const library=mkdtempSync(join(tmpdir(),'unimagic-bridge-'));
const child=spawn('macos/build/UniMagic.app/Contents/Resources/node',['macos/build/bridge.cjs'],{env:{...process.env,UNIMAGIC_LIBRARY:library},stdio:['pipe','pipe','inherit']});
const iterator=createInterface({input:child.stdout})[Symbol.asyncIterator]();
let id=0;
async function request(op,args={}) {child.stdin.write(JSON.stringify({op,requestID:++id,...args})+'\n');const {value,done}=await iterator.next();assert(!done,'Bridge exited');const envelope=JSON.parse(value);assert(!envelope.error,envelope.error);return envelope.result;}
try {
 const categories=await request('categories');assert.equal(categories.length,354);
 assert.equal((await request('list',{category:'recents'})).records.length,0);
 const x=await request('list',{query:'x'});assert(x.records.some(r=>r.symbol==='x'));
 for(const query of ['xr','x-r'])assert((await request('list',{query})).records.some(r=>r.symbol==='🩻'));
 const direct=await request('list',{query:'U+2192'});assert.equal(direct.records[0].symbol,'→');
 const glyph=direct.records[0];
 const detail=await request('details',{id:glyph.id});assert(detail.values.some(v=>v.label==='UTF-8'&&v.value==='E2 86 92'));assert(detail.values.some(v=>v.label==='Swift'));assert(detail.contexts.length);
 await request('teach',{id:glyph.id,term:'synthetic zorbation'});
 assert.equal((await request('list',{query:'synthetic zorbation'})).records[0].symbol,'→');
 await request('pick',{id:glyph.id,symbol:'→',query:'synthetic zorbation',action:'copy'});
 const recent=(await request('list',{category:'recents'})).records[0];assert.equal(recent.symbol,'→');assert((await request('details',{id:recent.id})).values.some(row=>row.label==='History'));
 await request('unlearn',{id:glyph.id,term:'synthetic zorbation'});
 const toned=(await request('list',{query:'U+1F44D'})).records[0];assert((await request('details',{id:toned.id})).variants.some(symbol=>symbol.replace(/\uFE0F/g,'')==='👍🏻'));
 const store=join(library,'personalization-v1.json'),saved=JSON.parse(readFileSync(store,'utf8'));
 saved.history.events.unshift({eventID:'synthetic-legacy-toned',glyphID:'1F44D',symbol:'👍🏻',occurredAt:1,provenance:{kind:'pick',host:'tinycast',action:'copy'}});writeFileSync(store,JSON.stringify(saved));
 const historical=(await request('list',{category:'recents'})).records[0];const historicalDetail=await request('details',{id:historical.id});
 assert(historicalDetail.variants.every(symbol=>[...symbol].filter(cp=>cp==='🏻').length<=1),'Historical toned records must not get a second tone modifier');
 await request('visibility',{category:'set:Emojis',enabled:false});assert.equal((await request('categories')).find(c=>c.id==='set:Emojis').enabled,false);
 const bad=join(library,'malformed');mkdirSync(bad);writeFileSync(join(bad,'personalization-v1.json'),'broken');
 const failed=spawnSync('macos/build/UniMagic.app/Contents/Resources/node',['macos/build/bridge.cjs'],{env:{...process.env,UNIMAGIC_LIBRARY:bad},encoding:'utf8',timeout:5000});
 assert.equal(failed.status,1);assert(failed.stderr.length<2200,'Startup diagnostics must stay bounded and never dump the corpus');
 console.log('Native bridge acceptance passed:354 categories, empty defaults, literal/prefix/codepoint search, encodings, teach/unlearn, exact history, variants, visibility.');
} finally {child.stdin.end();await new Promise(resolve=>child.once('exit',resolve));rmSync(library,{recursive:true,force:true});}
