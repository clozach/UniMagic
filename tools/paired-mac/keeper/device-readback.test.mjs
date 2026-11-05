import test from 'node:test';
import assert from 'node:assert/strict';
import {installAndVerify,waitForInstalledMetadata} from './device.mjs';
const bundle='com.clozach.amaanah.alerts';
const release={bundle,build:'15',version:'1.1.0'};
const current={bundleIdentifier:bundle,bundleVersion:'15',version:'1.1.0',url:'new'};
const old={...current,bundleVersion:'14',url:'old'};
const receipt={result:{installedApplications:[{bundleID:bundle,installationURL:'new'}]}};
function clock(){let now=0;return {readbackTimeoutMs:20,readbackPollMs:5,readbackNow:()=>now,readbackSleep:async ms=>{now+=ms;}};}
for(const lag of [1,2])test(`in-place install tolerates ${lag} stale catalogue reads before snapshot`,async()=>{
 let installed=false,reads=0,installs=0;const events=[];
 const result=await installAndVerify('/fixture.app',release,'/fixture',{
  ...clock(),allowUpgrade:true,installedApp:async()=>{if(!installed)return old;events.push('read');return ++reads<=lag?old:current;},
  device:async()=>{installed=true;installs++;return receipt;},snapshotSaved:async path=>{events.push(path.endsWith('saved-before')?'before':'after');return {draft:'same'};}
 });
 assert.equal(installs,1);assert.equal(result.installedURL,'new');assert.deepEqual(events,['before',...Array(lag+1).fill('read'),'after']);
});
test('bootstrap uses same polling and exact product identity',async()=>{
 const product={bundle:'com.clozach.unimagic'};let installed=false,reads=0,installs=0;
 const result=await installAndVerify('/fixture.app',{...release,bundle:product.bundle},'/fixture',{
  ...clock(),product,bootstrap:true,installedApp:async()=>installed?(++reads<3?null:{...current,bundleIdentifier:product.bundle}):null,
  device:async()=>{installed=true;installs++;return {result:{installedApplications:[{bundleID:product.bundle,installationURL:'new'}]}};},snapshotSaved:async()=>assert.fail('bootstrap snapshot')
 });assert.equal(result.bootstrap,true);assert.equal(installs,1);assert.equal(reads,3);
});
test('same-build renewal waits for OS receipt URL instead of cached URL',async()=>{
 let reads=0;const result=await waitForInstalledMetadata(release,receipt,{...clock(),installedApp:async()=>++reads<3?{...current,url:'old'}:current});
 assert.equal(reads,3);assert.equal(result.url,'new');
});
for(const mismatch of [{...old},{...current,version:'1.0.0'},{...current,url:''},{...current,url:'old'},null])test(`mismatched metadata times out without a second install or after snapshot: ${JSON.stringify(mismatch)}`,async()=>{
 let installed=false,installs=0,snapshots=0;
 await assert.rejects(installAndVerify('/fixture.app',release,'/fixture',{...clock(),allowUpgrade:true,
  installedApp:async()=>installed?mismatch:old,device:async()=>{installed=true;installs++;return receipt;},snapshotSaved:async()=>{snapshots++;return {};}
 }),/metadata refresh timed out; installation was not repeated/);
 assert.equal(installs,1);assert.equal(snapshots,1);
});
test('wrong bundle identity fails immediately',async()=>{
 await assert.rejects(waitForInstalledMetadata(release,receipt,{...clock(),installedApp:async()=>({...current,bundleIdentifier:'other'})}),/wrong bundle identity/);
});
test('legacy receipt without URL permits exact tuple and nonempty queried URL',async()=>{
 assert.equal((await waitForInstalledMetadata(release,{success:true},{...clock(),installedApp:async()=>current})).url,'new');
 await assert.rejects(waitForInstalledMetadata(release,{result:{installedApplications:[{bundleID:'other',installationURL:'new'}]}},{...clock(),installedApp:async()=>current}),/receipt bundle/);
});
test('abort interrupts a stalled read without after snapshot or reinstall',async()=>{
 const controller=new AbortController();let installed=false,installs=0,snapshots=0;
 const work=installAndVerify('/fixture.app',release,'/fixture',{signal:controller.signal,allowUpgrade:true,
 installedApp:async()=>{if(!installed)return old;queueMicrotask(()=>controller.abort(Error('explicit abort')));return new Promise(()=>{});},
 device:async()=>{installed=true;installs++;return receipt;},snapshotSaved:async()=>{snapshots++;return {};}});
 await assert.rejects(work,/explicit abort/);assert.equal(installs,1);assert.equal(snapshots,1);
});
test('real bounded timeout interrupts a stalled metadata query',async()=>{
 await assert.rejects(waitForInstalledMetadata(release,receipt,{readbackTimeoutMs:10,readbackPollMs:1,installedApp:async()=>new Promise(()=>{})}),/timed out/);
});
