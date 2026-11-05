import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {requireTransferredHistory,verifyKeyboardCAS} from './keyboard-retirement.mjs';
import {installAndVerify} from './device.mjs';
import {snapshotExtraDomains} from './snapshot-domains.mjs';

const previous={bundle:'com.clozach.amaanah.alerts',build:'15',version:'1.1.0',installedURL:'old',targets:['service','keyboard','app']};
const next={...previous,build:'16',targets:['service','app']};
const installed=r=>({bundleIdentifier:r.bundle,bundleVersion:r.build,version:r.version,url:r===next?'new':'old'});
test('generic install refuses retirement before mutating the device',async()=>{
 let touched=false;await assert.rejects(installAndVerify('/candidate',next,'/fixture',{allowUpgrade:true,previousRelease:previous,installedApp:async()=>installed(previous),snapshotSaved:async()=>{touched=true;},device:async()=>{touched=true;}}),/explicit verified/);assert.equal(touched,false);
});
test('explicit retirement retains keyboard/group in before snapshot, verifies remaining domain after install',async()=>{
 let called=false,proof=false;const scopes=[];
 const retired={'keyboard/support/k':'K','shared/preferences/g':'G'};
 const result=await installAndVerify('/candidate',next,'/fixture',{allowUpgrade:true,previousRelease:previous,installedApp:async()=>installed(called?next:previous),snapshotSaved:async(p,i)=>{scopes.push(i.snapshotRelease.build);return called?{main:'M'}:{main:'M',...retired};},verifyKeyboardRetirement:async({before})=>{assert.deepEqual(before,{main:'M',...retired});proof=true;return retired;},device:async()=>{assert.ok(proof);called=true;return{};}});
 assert.deepEqual(scopes,['15','16']);assert.equal(result.savedFiles,1);assert.deepEqual(result.retiredFiles,retired);
 await snapshotExtraDomains('/fixture',next,async()=>assert.fail('retired containers must not be accessed on renewal'));
});
test('transfer rejects a newer standalone keyboard and permits restart from partially copied data',()=>{
 const l='keyboard/learning-v1.json',h='keyboard/UniMagic/LocalPersonalization/personalization-v1.sqlite',old={[l]:'a',[h]:'b'},next={[l]:'A',[h]:'B'};
 assert.doesNotThrow(()=>verifyKeyboardCAS({...old,[h]:'B'},old,next));assert.throws(()=>verifyKeyboardCAS({...old,[h]:'independent event'},old,next),/changed since/);
});
test('standalone may add events; existing exact events and original dates must survive',t=>{
 const dir=mkdtempSync(join(tmpdir(),'retired-keyboard-'));t.after(()=>rmSync(dir,{recursive:true,force:true}));
 const files=['source','destination'].map(n=>join(dir,n));
 for(const file of files){const db=new DatabaseSync(file);db.exec("CREATE TABLE history(event_id TEXT,occurred_at REAL,payload TEXT); INSERT INTO history VALUES('id',NULL,'original');");db.close();}
 const db=new DatabaseSync(files[1]);db.exec("INSERT INTO history VALUES('new',1,'new pick')");db.close();assert.doesNotThrow(()=>requireTransferredHistory(...files));
 const changed=new DatabaseSync(files[1]);changed.exec("UPDATE history SET payload='different' WHERE event_id='id'");changed.close();assert.throws(()=>requireTransferredHistory(...files),/missing or changed/);
});
