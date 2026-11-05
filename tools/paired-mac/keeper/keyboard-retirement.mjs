// Manual PowWorm cutover. Every old domain is archived before the old extension
// disappears. The keeper continues to require the original targets for renewal.
import {mkdirSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import {device,installedApp,savedHashes} from './device.mjs';
import {snapshotKeyboard,migrationProcesses} from './migration.mjs';
import {HOME,takeLock,atomicJSON} from './state.mjs';
import {UNIMAGIC_PRODUCT} from './products.mjs';

const paths=['keyboard/learning-v1.json','keyboard/UniMagic/LocalPersonalization/personalization-v1.sqlite'];
const readReceipt=file=>JSON.parse(readFileSync(file,'utf8'));
const demand=(value,reason)=>{if(!value)throw Error(reason);};
const equal=(a,b)=>paths.every(p=>a[p]&&a[p]===b[p]);
export function verifyKeyboardCAS(current,baseline,desired) {
 demand(paths.every(p=>current[p]&&baseline[p]&&desired[p]&&(current[p]===baseline[p]||current[p]===desired[p])),'Standalone keyboard changed since transfer. Preserve both snapshots and reconcile before retirement.');
}
async function requireIdleKeyboards(io){
 const r=await (io.device??device)(['info','processes'],io);
 const list=r.result?.runningProcesses??r.result?.processes;
 demand(Array.isArray(list),'Cannot verify keyboard processes');
 for(const side of ['source','destination'])for(const p of migrationProcesses(list,side)){
  const path=p.executable??p.executablePath;
  demand(typeof path==='string'&&/\/(AgentAlerts|Unimagic)\.app\/\1$/.test(path),'Close the active keyboard before copying keyboard data.');
 }
}
function assertSnapshot(files){demand(Object.keys(files).length===paths.length&&paths.every(p=>files[p]),'Both complete keyboard stores required');}

// Copy only if the destination still matches the last verified import. A retry
// may finish an interrupted copy if every file is either the old or desired byte
// sequence. Independent app settings are in a separate container and never copied.
export async function catchUpKeyboard(baselinePath,io={}) {
 const baseline=readReceipt(baselinePath).after;demand(baseline,'Verified migration receipt required');
 const lock=takeLock();demand(lock,'Another installation/renewal is active');
 const work=join(HOME,'attempts','keyboard-transfer-'+randomUUID());
 try{
  mkdirSync(work,{recursive:true,mode:0o700});const ctx={...io,onChild:lock.onChild};
  await requireIdleKeyboards(ctx);
  const src=await snapshotKeyboard(join(work,'source'),'source',ctx),dst=await snapshotKeyboard(join(work,'before'),'destination',ctx);
  assertSnapshot(src);assertSnapshot(dst);verifyKeyboardCAS(dst,baseline,src);
  for(const p of paths){
   if(dst[p]===src[p])continue;
   await requireIdleKeyboards(ctx);
   const fresh=await snapshotKeyboard(join(work,'compare-'+paths.indexOf(p)),'destination',ctx);
   demand(equal(fresh,dst),'Keyboard changed during transfer; retained snapshots');
   await (ctx.device??device)(['copy','to','--domain-type','appDataContainer','--domain-identifier',UNIMAGIC_PRODUCT.bundle+'.keyboard','--source',join(work,'source',p),'--destination','Library/Application Support/'+p.slice('keyboard/'.length)],ctx);
   dst[p]=src[p];
  }
  const after=await snapshotKeyboard(join(work,'after'),'destination',ctx);
  demand(equal(after,src)&&equal(src,await snapshotKeyboard(join(work,'stable-source'),'source',ctx)),'Keyboard readback differs; keep all snapshots');
  const receipt=join(work,'receipt.json');atomicJSON(receipt,{kind:'verified-keyboard-transfer',after,verifiedAt:Date.now()});return receipt;
 }finally{lock.release();}
}

export function requireTransferredHistory(legacy,destination) {
 const db=new DatabaseSync(destination,{readOnly:true});
 try{
  db.prepare('ATTACH DATABASE ? AS legacy').run(legacy);
  demand(db.prepare('PRAGMA main.integrity_check').get().integrity_check==='ok','Standalone keyboard database damaged');
  const missing=db.prepare('SELECT 1 FROM (SELECT event_id,occurred_at,payload FROM legacy.history EXCEPT SELECT event_id,occurred_at,payload FROM main.history) LIMIT 1').get();
  demand(!missing,'Transferred keyboard history missing or changed; review private snapshots before retirement');
 }finally{db.close();}
}
export function retirementVerifier(transferReceipt){
 const proof=readReceipt(transferReceipt);
 demand(proof.kind==='verified-keyboard-transfer'&&paths.every(p=>/^[a-f0-9]{64}$/.test(proof.after?.[p])),'Verified keyboard catch-up receipt required');
 return async({attempt,before,previous,release})=>{
  demand(previous.bundle==='com.clozach.amaanah.alerts'&&previous.build==='15'&&previous.targets.includes('keyboard')&&previous.capabilities.kind==='unimagic-sharing'&&release.build==='16'&&release.capabilities.kind==='isolated'&&JSON.stringify(release.targets)===JSON.stringify(['service','app']),'Unsupported retirement identity');
  demand((await installedApp({product:UNIMAGIC_PRODUCT}))?.bundleIdentifier===UNIMAGIC_PRODUCT.bundle,'Standalone UniMagic missing');
  const archive=join(attempt,'saved-before'),verified=savedHashes(archive);
  const retired=Object.fromEntries(Object.entries(before).filter(([p])=>p.startsWith('keyboard/')||p.startsWith('shared/')));
  demand(Object.keys(retired).every(p=>verified[p]===retired[p]),'Archived retirement data changed');
  for(const p of paths)demand(before[p.replace('keyboard/','keyboard/support/')]===proof.after[p],'Legacy keyboard changed since catch-up; repeat verified transfer first');
  const dest=join(attempt,'standalone-before');assertSnapshot(await snapshotKeyboard(dest,'destination'));
  requireTransferredHistory(join(archive,paths[1].replace('keyboard/','keyboard/support/')),join(dest,paths[1]));
  await requireIdleKeyboards({});
  atomicJSON(join(attempt,'retired-domains.json'),{transferReceipt,retired,verifiedAt:Date.now()});return retired;
 };
}
