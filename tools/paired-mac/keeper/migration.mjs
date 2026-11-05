import {mkdirSync,readFileSync,writeFileSync,existsSync,copyFileSync,readdirSync} from 'node:fs';
import {join,dirname} from 'node:path';
import {createHash,randomUUID} from 'node:crypto';
import {device} from './device.mjs';
import {DatabaseSync} from 'node:sqlite';
import {takeLock,atomicJSON} from './state.mjs';
import {UNIMAGIC_PRODUCT} from './products.mjs';

const support='Library/Application Support';
const local='UniMagic/LocalPersonalization/';
const stores=['learning-v1.json',local+'personalization-v1.sqlite',local+'personalization-v1.sqlite-wal',local+'personalization-v1.sqlite-shm',local+'personalization-v1.sqlite-journal'];
const hosts=[{name:'app',source:'com.clozach.amaanah.alerts',destination:UNIMAGIC_PRODUCT.bundle},{name:'keyboard',source:'com.clozach.amaanah.alerts.keyboard',destination:UNIMAGIC_PRODUCT.bundle+'.keyboard'}];
export function migrationProcesses(processes,side){
 const app=side==='source'?'AgentAlerts':'Unimagic',bundles=hosts.map(h=>h[side]),names=[app,'UnimagicKeyboard'];
 const strings=value=>typeof value==='string'?[value]:value&&typeof value==='object'?Object.values(value).flatMap(strings):[];
 return processes.filter(process=>{
  const values=strings(process).map(value=>{try{return decodeURIComponent(value);}catch{return value;}});
  if(values.some(value=>bundles.includes(value)))return true;
  if(values.some(value=>value.includes('/'+app+'.app/')&&(value.endsWith('/'+app)||value.endsWith('/UnimagicKeyboard.appex/UnimagicKeyboard'))))return true;
  // An executable basename alone cannot distinguish PowWorm's keyboard from
  // the standalone one. Refuse uncertain evidence rather than label a peer.
  const name=process.name??process.processName;
  if(names.includes(name)&&!values.some(value=>value.includes('.app/')))throw Error('Migration process owner is ambiguous; require full executable paths');
  return false;
 });
}
export async function requireQuiescent(side,io={}){
 const response=await(io.device??device)(['info','processes'],io);
 const processes=response.result?.runningProcesses??response.result?.processes;
 if(!Array.isArray(processes))throw Error('Cannot verify migration processes are stopped');
 if(migrationProcesses(processes,side).length)throw Error('Close the '+(side==='source'?'PowWorm app and embedded keyboard':'standalone UniMagic app and keyboard')+' before migration; no process was terminated');
}
function validateStore(folder,host){
 const learning=join(folder,host.name,'learning-v1.json');
 if(existsSync(learning)){const value=JSON.parse(readFileSync(learning,'utf8'));if(value.version!==1||!Array.isArray(value.usage))throw Error('Unsupported learning store');}
 for(const suffix of ['-wal','-shm','-journal'])if(existsSync(join(folder,host.name,local+'personalization-v1.sqlite'+suffix)))throw Error('SQLite sidecar present; stop the writer and checkpoint before exporting');
 const database=join(folder,host.name,local+'personalization-v1.sqlite');
 if(!existsSync(database))throw Error('Missing '+host.name+' personalization database');
 const db=new DatabaseSync(database,{readOnly:true});try{if(db.prepare('PRAGMA integrity_check').get().integrity_check!=='ok'||db.prepare('PRAGMA user_version').get().user_version!==1)throw Error('Invalid personalization database');for(const table of ['history','preferences','history_imports'])db.prepare('SELECT count(*) FROM '+table).get();}finally{db.close();}
}
const hash=file=>createHash('sha256').update(readFileSync(file)).digest('hex');

/** Enumerating an inaccessible container is a failure, never "empty". */
async function hostSnapshot(host,side,folder,io){
 const bundle=host[side],execute=io.device??device,files={};
 const list=async(path)=>{
  const response=await execute(['info','files','--domain-type','appDataContainer','--domain-identifier',bundle,...(path?['--subdirectory',path]:[]),'--no-recurse'],io);
  if(!Array.isArray(response.result?.files))throw Error('Migration container enumeration unavailable: '+bundle);
  return response.result.files;
 };
 const root=await list('');if(!root.some(f=>f.name==='Library'&&f.resources?.isDirectory))return {};
 const library=await list('Library');if(!library.some(f=>f.name==='Application Support'&&f.resources?.isDirectory))return {};
 for(const directory of ['', 'UniMagic','UniMagic/LocalPersonalization']){
  const parent=directory?directory.split('/').slice(0,-1).join('/'):null;
  if(directory&&!files['directory:'+directory])continue;
  const response=await execute(['info','files','--domain-type','appDataContainer','--domain-identifier',bundle,'--subdirectory',support+(directory?'/'+directory:''),'--no-recurse'],io);
  if(!Array.isArray(response.result?.files))throw Error('Migration container enumeration unavailable: '+bundle);
  for(const entry of response.result.files){const path=(directory?directory+'/':'')+entry.name;if(entry.resources?.isDirectory)files['directory:'+path]=true;else if(stores.includes(path))files[path]=true;}
 }
 const result={};
 for(const path of stores.filter(p=>files[p])){
  const destination=join(folder,host.name,path);mkdirSync(dirname(destination),{recursive:true,mode:0o700});
  await execute(['copy','from','--domain-type','appDataContainer','--domain-identifier',bundle,'--source',support+'/'+path,'--destination',destination],io);
  result[host.name+'/'+path]=hash(destination);
 }
 return result;
}

export async function inspectMigration(folder,{side='source',io={}}={}){
 if(!['source','destination'].includes(side))throw Error('Expected source or destination');
 mkdirSync(folder,{recursive:true,mode:0o700});const files={};
 for(const host of hosts)Object.assign(files,await hostSnapshot(host,side,folder,io));
 const result={schemaVersion:1,kind:'unimagic-host-transfer',side,files};atomicJSON(join(folder,'manifest.json'),result);return result;
}

/** Two stable copies fence active writers. Originals are read only. No history
 * is synthesized, reordered or merged. Keep these snapshots private. */
export async function exportMigration(folder,{io={}}={}){
 if(existsSync(folder))throw Error('Export requires a new private directory');
 mkdirSync(folder,{recursive:true,mode:0o700});
 await requireQuiescent('source',io);
 const first=await inspectMigration(join(folder,'data'),{io}),second=await inspectMigration(join(folder,'stability-check'),{io});
 if(JSON.stringify(first.files)!==JSON.stringify(second.files))throw Error('Source changed while exporting; stop the two source processes and retry into a new directory');
 for(const host of hosts)if(!first.files[host.name+'/'+local+'personalization-v1.sqlite'])throw Error('Source '+host.name+' personalization database missing; refuse incomplete transfer');
 for(const host of hosts)validateStore(join(folder,'data'),host);
 const manifest={...first,id:randomUUID(),createdAt:new Date().toISOString(),sourceBundles:hosts.map(h=>h.source),destinationBundles:hosts.map(h=>h.destination)};
 atomicJSON(join(folder,'manifest.json'),manifest);return manifest;
}

export function readMigration(folder){
 const manifest=JSON.parse(readFileSync(join(folder,'manifest.json'),'utf8'));
 if(manifest.schemaVersion!==1||manifest.kind!=='unimagic-host-transfer'||manifest.side!=='source'||!manifest.files||JSON.stringify(manifest.sourceBundles)!==JSON.stringify(hosts.map(h=>h.source))||JSON.stringify(manifest.destinationBundles)!==JSON.stringify(hosts.map(h=>h.destination)))throw Error('Invalid migration manifest');
 for(const [path,digest]of Object.entries(manifest.files)){
  if(!hosts.some(h=>stores.some(s=>h.name+'/'+s===path))||!/^[a-f0-9]{64}$/.test(digest)||hash(join(folder,'data',path))!==digest)throw Error('Migration file changed or path unsupported');
 }
 for(const host of hosts)validateStore(join(folder,'data'),host);
 return manifest;
}

/** Restore only to new destinations, or against a separately captured exact
 * baseline. A newer destination stops the transaction; retries skip matches. */
export async function importMigration(folder,{expected,workspace,io={}}={}){
 const lock=(io.lock??takeLock)(UNIMAGIC_PRODUCT.lockPath);if(!lock)throw Error('Another installation or renewal is active');
 try{
  await requireQuiescent('destination',io);
  const manifest=readMigration(folder);mkdirSync(workspace,{recursive:true,mode:0o700});
  const before=await inspectMigration(join(workspace,'destination-before'),{side:'destination',io});
  if(Object.keys(before.files).some(path=>/-wal$|-shm$|-journal$/.test(path)))throw Error('Destination SQLite sidecar present; close and checkpoint before import');
  if(expected&&(expected.schemaVersion!==1||expected.side!=='destination'))throw Error('Expected destination snapshot required');
  for(const [path,digest]of Object.entries(before.files))if(digest!==manifest.files[path]&&digest!==expected?.files?.[path])throw Error('Destination has newer or unapproved data: '+path);
  // Absence is part of the CAS as well: disappearance since baseline is not new.
  if(expected)for(const path of Object.keys(expected.files))if(!before.files[path])throw Error('Destination baseline file disappeared: '+path);
  const approved={...before.files};
  for(const host of hosts){
   // Recheck the whole host immediately before its writes, rather than relying
   // on the snapshot made before the other host was transferred.
   const fresh=await hostSnapshot(host,'destination',join(workspace,'cas-'+host.name),io);
   for(const path of new Set([...Object.keys(fresh),...Object.keys(approved).filter(p=>p.startsWith(host.name+'/'))]))if(fresh[path]!==approved[path])throw Error('Destination changed before import: '+path);
   for(const path of stores){
    const key=host.name+'/'+path,digest=manifest.files[key];if(!digest||fresh[key]===digest)continue;
    await requireQuiescent('destination',io);
    await(io.device??device)(['copy','to','--domain-type','appDataContainer','--domain-identifier',host.destination,'--source',join(folder,'data',key),'--destination',support+'/'+path],io);
   }
  }
  const after=await inspectMigration(join(workspace,'destination-after'),{side:'destination',io});
  for(const [path,digest]of Object.entries(manifest.files))if(after.files[path]!==digest)throw Error('Migration readback differs; retain all snapshots: '+path);
  const receipt={schemaVersion:1,importID:manifest.id,verifiedAt:new Date().toISOString(),before:before.files,after:after.files};atomicJSON(join(workspace,'receipt.json'),receipt);return receipt;
 }finally{lock.release();}
}
