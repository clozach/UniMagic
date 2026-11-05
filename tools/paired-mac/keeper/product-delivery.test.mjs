import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,existsSync,copyFileSync,readdirSync} from 'node:fs';
import {join,dirname} from 'node:path';
import {tmpdir} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {UNIMAGIC_PRODUCT} from './products.mjs';
import {parseUpdateConsent,requireUpdateAuthority} from './update-consent.mjs';
import {deliverPublishedProduct} from './product-delivery.mjs';
import {installAndVerify} from './device.mjs';
import {exportMigration,inspectMigration,importMigration} from './migration.mjs';
const temp=()=>mkdtempSync(join(tmpdir(),'unimagic-delivery-test-'));
const uuid='00000000-0000-4000-8000-000000000001';
const policy=automaticUpdates=>({schemaVersion:1,product:UNIMAGIC_PRODUCT.bundle,automaticUpdates,revision:uuid});
const lock=()=>({onChild(){},release(){}});

test('strict phone consent rejects malformed, future, string boolean, wrong product and unknown fields',()=>{
 assert.equal(parseUpdateConsent(JSON.stringify(policy(false)),UNIMAGIC_PRODUCT).automaticUpdates,false);
 for(const value of [{...policy(true),schemaVersion:2},{...policy(true),automaticUpdates:'true'},{...policy(true),product:'other'},{...policy(true),revision:'yes'},{...policy(true),future:true}])assert.throws(()=>parseUpdateConsent(JSON.stringify(value),UNIMAGIC_PRODUCT));
 assert.throws(()=>requireUpdateAuthority({kind:'read',policy:policy(false)}));
 assert.throws(()=>requireUpdateAuthority({kind:'defer'}));
 assert.throws(()=>requireUpdateAuthority({kind:'read',policy:policy(false)},{manualRequest:uuid}),'manual Check is discovery only');
});

test('off consent never authenticates, signs or installs a candidate',async()=>{
 let effects=0;
 await assert.rejects(deliverPublishedProduct({...UNIMAGIC_PRODUCT,home:temp()},{},{lock,readConsent:async()=>({kind:'read',policy:policy(false)}),payload:async()=>{effects++;}}),/off/);
 assert.equal(effects,0);
});

test('consent is re-read at the install boundary and changed/off choices stop installation',async()=>{
 const home=temp();let reads=0,installed=0;
 const io={lock,readConsent:async()=>({kind:'read',policy:policy(++reads===1)}),payload:async()=>({manifest:{build:'2',version:'1.0.0'},app:'unsigned'}),installedApp:async()=>({bundleVersion:'1',version:'1.0.0'}),sign:async()=>({app:'signed'}),capture:async()=>({app:'frozen',build:'2',version:'1.0.0'}),install:async(a,b,c,options)=>{await options.beforeInstall();installed++;return {};}};
 await assert.rejects(deliverPublishedProduct({...UNIMAGIC_PRODUCT,home},{},io),/off/);assert.equal(reads,2);assert.equal(installed,0);
});

test('bootstrap requires explicit flag; performs installed version readback without pretending to preserve nonexistent files',async()=>{
 let installed=false,snapshots=0;
 const io={bootstrap:true,installedApp:async()=>installed?{bundleVersion:'1',version:'1.0.0',url:'new'}:null,device:async()=>{installed=true;return {ok:true};},snapshotSaved:async()=>{snapshots++;}};
 const result=await installAndVerify('app',{build:'1',version:'1.0.0'},temp(),io);assert.equal(result.bootstrap,true);assert.equal(snapshots,0);
 await assert.rejects(installAndVerify('app',{build:'0',version:'1.0.0'},temp(),{...io,bootstrap:false}),/identity/);
});

function fixture(){
 const root=temp(),containers={};
 for(const bundle of ['com.clozach.amaanah.alerts','com.clozach.amaanah.alerts.keyboard','com.clozach.unimagic','com.clozach.unimagic.keyboard']){containers[bundle]=join(root,bundle);mkdirSync(join(containers[bundle],'Library/Application Support'),{recursive:true});}
 for(const [index,bundle]of ['com.clozach.amaanah.alerts','com.clozach.amaanah.alerts.keyboard'].entries()){
  const support=join(containers[bundle],'Library/Application Support'),dbfile=join(support,'UniMagic/LocalPersonalization/personalization-v1.sqlite');mkdirSync(dirname(dbfile),{recursive:true});
  writeFileSync(join(support,'learning-v1.json'),JSON.stringify({version:1,usage:[{symbol:index?'β':'α',count:index+2}],aliases:{word:index?'β':'α'}}));
  const db=new DatabaseSync(dbfile);db.exec('PRAGMA user_version=1; CREATE TABLE history(event_id TEXT); CREATE TABLE preferences(payload TEXT); CREATE TABLE history_imports(import_id TEXT);');db.prepare('INSERT INTO history VALUES(?)').run(index?'keyboard-only':'app-only');db.prepare('INSERT INTO preferences VALUES(?)').run(JSON.stringify({categoryVisibility:{one:!!index},exemplarOverrides:{one:index?'β':'α'}}));db.close();
 }
 const writes=[];
 const device=async args=>{
  if(args[0]==='info'&&args[1]==='processes')return {result:{runningProcesses:[]}};
  const value=key=>args[args.indexOf(key)+1],bundle=value('--domain-identifier');
  if(args[0]==='info'){const path=join(containers[bundle],args.includes('--subdirectory')?value('--subdirectory'):'');return {result:{files:readdirSync(path,{withFileTypes:true}).map(e=>({name:e.name,resources:{isDirectory:e.isDirectory()}}))}};}
  if(args[1]==='from'){const destination=value('--destination');mkdirSync(dirname(destination),{recursive:true});copyFileSync(join(containers[bundle],value('--source')),destination);return {};}
  const destination=join(containers[bundle],value('--destination'));mkdirSync(dirname(destination),{recursive:true});copyFileSync(value('--source'),destination);writes.push(destination);return {};
 };
 return {root,containers,writes,io:{device,lock}};
}

test('migration preserves separate app and keyboard history/learning/preferences byte-for-byte and retries idempotently',async()=>{
 const f=fixture(),snapshot=join(f.root,'export');await exportMigration(snapshot,{io:f.io});
 const receipt=await importMigration(snapshot,{workspace:join(f.root,'import1'),io:f.io});assert.equal(Object.keys(receipt.after).length,4);assert.equal(f.writes.length,4);
 const app=join(f.containers['com.clozach.unimagic'],'Library/Application Support/UniMagic/LocalPersonalization/personalization-v1.sqlite');const db=new DatabaseSync(app,{readOnly:true});assert.equal(db.prepare('SELECT event_id FROM history').get().event_id,'app-only');db.close();
 await importMigration(snapshot,{workspace:join(f.root,'import2'),io:f.io});assert.equal(f.writes.length,4);
});

test('migration refuses newer destination; separately captured baseline permits exact compare-and-set',async()=>{
 const f=fixture(),snapshot=join(f.root,'export');await exportMigration(snapshot,{io:f.io});const path=join(f.containers['com.clozach.unimagic'],'Library/Application Support/learning-v1.json');writeFileSync(path,'newer');
 await assert.rejects(importMigration(snapshot,{workspace:join(f.root,'refused'),io:f.io}),/newer/);assert.equal(f.writes.length,0);assert.equal(readFileSync(path,'utf8'),'newer');
 const expected=await inspectMigration(join(f.root,'baseline'),{side:'destination',io:f.io});await importMigration(snapshot,{workspace:join(f.root,'cas'),expected,io:f.io});assert.equal(f.writes.length,4);
});

test('migration refuses running destinations and corrupt export before any phone write',async()=>{
 const f=fixture(),snapshot=join(f.root,'export');await exportMigration(snapshot,{io:f.io});
 await assert.rejects(importMigration(snapshot,{workspace:join(f.root,'busy'),io:{...f.io,device:async args=>args[1]==='processes'?{result:{runningProcesses:[{executable:'/private/Unimagic.app/Unimagic'}]}}:f.io.device(args)}}),/Close/);assert.equal(f.writes.length,0);
 writeFileSync(join(snapshot,'data/app/learning-v1.json'),'tampered');await assert.rejects(importMigration(snapshot,{workspace:join(f.root,'corrupt'),io:f.io}),/changed/);assert.equal(f.writes.length,0);
});

test('migration detects only exact source app/keyboard paths, including keyboard without running PowWorm',async()=>{
 const {migrationProcesses}=await import('./migration.mjs');
 const sourceKeyboard={executable:'file:///private/var/containers/Bundle/Application/ID/AgentAlerts.app/PlugIns/UnimagicKeyboard.appex/UnimagicKeyboard'};
 const destinationKeyboard={executable:'file:///private/var/containers/Bundle/Application/ID/Unimagic.app/PlugIns/UnimagicKeyboard.appex/UnimagicKeyboard'};
 assert.deepEqual(migrationProcesses([sourceKeyboard,destinationKeyboard,{executable:'/Other.app/UnimagicKeyboard'}],'source'),[sourceKeyboard]);
 assert.deepEqual(migrationProcesses([sourceKeyboard,destinationKeyboard],'destination'),[destinationKeyboard]);
});
