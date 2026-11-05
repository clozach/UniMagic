import {mkdirSync,readFileSync,writeFileSync,renameSync,existsSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {homedir} from 'node:os';
import {randomUUID} from 'node:crypto';
export const ROOT=join(homedir(),'Library/Application Support/amaanah/iphone-agent-alerts');
export const HOME=join(ROOT,'native-renewal');
export const LOCK=join(ROOT,'renew.lock');
export function readJSON(path,fallback=null){try{return JSON.parse(readFileSync(path,'utf8'));}catch{return fallback;}}
export function atomicJSON(path,value){const temporary=path+'.'+randomUUID()+'.tmp';writeFileSync(temporary,JSON.stringify(value,null,2)+'\n',{mode:0o600});renameSync(temporary,path);}
export function readMaintenance(home=HOME){return readJSON(join(home,'state.json'),{kind:'unconfigured'});}
export function saveMaintenance(value,home=HOME){mkdirSync(home,{recursive:true,mode:0o700});atomicJSON(join(home,'state.json'),{...value,updatedAt:Date.now()});if(home===HOME)atomicJSON(join(ROOT,'renewal.json'),legacyState(value));return value;}
export function legacyState(value=readMaintenance()){return {expiresAt:value.release?.expiresAt,installedAt:value.release?.installedAt,renewing:inProgress(),phase:value.summary??value.kind,lastRenewError:['failed','needs_auth'].includes(value.kind)?value.error:null,relaunchPending:false};}
const alive=pid=>{try{process.kill(pid,0);return true;}catch(e){return e.code==='EPERM';}};
export function inProgress(lock=LOCK){const owner=readJSON(join(lock,'owner.json'));if(!existsSync(lock))return false;if(!owner)return true;return alive(owner.pid)||(owner.child&&alive(-owner.child));}
export function takeLock(lock=LOCK){mkdirSync(ROOT,{recursive:true});if(existsSync(lock)){if(inProgress(lock))return null;renameSync(lock,lock+'.abandoned-'+randomUUID());}try{mkdirSync(lock);}catch{return null;}const token=randomUUID(),owner={pid:process.pid,startedAt:Date.now(),token,child:null};atomicJSON(join(lock,'owner.json'),owner);return {onChild:pid=>{if(readJSON(join(lock,'owner.json'))?.token===token)atomicJSON(join(lock,'owner.json'),{...owner,child:pid});},release:()=>{const current=readJSON(join(lock,'owner.json'));if(current?.token===token&&!(current.child&&alive(-current.child)))rmSync(lock,{recursive:true});}};}
