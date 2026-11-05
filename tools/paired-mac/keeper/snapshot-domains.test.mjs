import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,rmSync,existsSync} from 'node:fs';
import {join,dirname} from 'node:path';
import {tmpdir} from 'node:os';
import {snapshotExtraDomains} from './snapshot-domains.mjs';
import {installAndVerify,snapshotSaved} from './device.mjs';
import {UNIMAGIC_GROUP} from './release-capabilities.mjs';
const folder=t=>{const p=mkdtempSync(join(tmpdir(),'pw-snapshot-'));t.after(()=>rmSync(p,{recursive:true,force:true}));return p;};
const dir=name=>({name,resources:{isDirectory:true}});
const shared={build:'12',version:'1.1.0',installedURL:'original',capabilities:{kind:'unimagic-sharing',appGroup:UNIMAGIC_GROUP,keyboardFullAccess:true}};

test('shared release snapshots actual app, keyboard-local and group stores separately',async t=>{
 const copies=[];
 const device=async args=>{
  if(args[0]==='info')return {result:{files:args.includes('--subdirectory')?[dir('Application Support'),dir('Preferences')]:[dir('Library')]}};
  const target=args[args.indexOf('--destination')+1],domain=args[args.indexOf('--domain-identifier')+1];
  assert.ok(existsSync(target),'devicectl requires the destination to exist for an empty remote folder');
  copies.push({domain,source:args[args.indexOf('--source')+1]});mkdirSync(target,{recursive:true});writeFileSync(join(target,'fixture'),domain);return{};
 };
 const hashes=await snapshotSaved(folder(t),{device,snapshotRelease:shared});
 assert.equal(copies.length,6);
 assert.deepEqual(Object.keys(hashes),['keyboard/preferences/fixture','keyboard/support/fixture','preferences/fixture','shared/preferences/fixture','shared/support/fixture','support/fixture']);
 assert.equal(copies.filter(x=>x.domain===UNIMAGIC_GROUP).length,2);
});
test('isolated keyboard keeps local history coverage but never requires a nonexistent group',async()=>{
 const requests=[];await snapshotExtraDomains('/fixture',{build:'11'},async args=>{requests.push(args);return{result:{files:[]}};});
 assert.equal(requests.length,1);assert.equal(requests[0][requests[0].indexOf('--domain-identifier')+1],'com.clozach.amaanah.alerts.keyboard');
 await snapshotExtraDomains('/fixture',{build:'9'},async()=>{throw Error('Old release has no extra containers');});
});
test('failed or malformed container enumeration is never treated as an empty store',async()=>{
 await assert.rejects(snapshotExtraDomains('/fixture',shared,async()=>{throw Error('Locked');}),/Locked/);
 await assert.rejects(snapshotExtraDomains('/fixture',shared,async()=>({result:{}})),/enumeration missing/);
});
test('first shared upgrade preserves known installed stores before any new-version migration',async t=>{
 const previousRelease={build:'11',version:'1.1.0',installedURL:'old'},seen=[];let installed={bundleVersion:'11',version:'1.1.0',url:'old'};
 await installAndVerify('/new.app',shared,folder(t),{allowUpgrade:true,previousRelease,
  installedApp:async()=>installed,snapshotSaved:async(_folder,io)=>{seen.push(io.snapshotRelease);return {history:'same'};},
  device:async()=>{installed={bundleVersion:'12',version:'1.1.0',url:'new'};return{};},
 });
 assert.deepEqual(seen,[previousRelease,previousRelease]);
});
test('unknown or stale shared-upgrade baseline stops before touching the installer',async t=>{
 const base={allowUpgrade:true,installedApp:async()=>({bundleVersion:'11',version:'1.1.0',url:'old'}),device:async()=>{throw Error('Must not install');}};
 await assert.rejects(installAndVerify('/new.app',shared,folder(t),base),/verified installed preservation baseline/);
 await assert.rejects(installAndVerify('/new.app',shared,folder(t),{...base,previousRelease:{build:'10',version:'1.1.0',installedURL:'old'}}),/preservation baseline/);
});
for(const changed of ['keyboard/support/UniMagic/LocalPersonalization/personalization-v1.sqlite','shared/support/UniMagic/personalization-v1.sqlite'])test(`real changed ${changed.split('/')[0]} history is detected`,async t=>{
 const root=folder(t);let reads=0;
 await assert.rejects(installAndVerify('/new.app',shared,root,{
  installedApp:async()=>({bundleVersion:'12',version:'1.1.0',url:'original'}),device:async()=>({}),
  snapshotSaved:async destination=>{const file=join(destination,changed);mkdirSync(dirname(file),{recursive:true});writeFileSync(file,++reads===1?'old history':'lost history');return{[changed]:reads===1?'before':'after'};},
 }),/Saved data changed/);
});
