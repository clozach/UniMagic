import {mkdirSync} from 'node:fs';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {HOME,LOCK,readMaintenance,saveMaintenance,takeLock,atomicJSON} from './state.mjs';
import {verifyRelease,captureRelease,treeHash} from './artifact.mjs';
import {probePhone,installedApp,installAndVerify} from './device.mjs';
import {provisionAndSign} from './provision.mjs';
import {plan,phoneReady,needsConnectionNotice,RETRY_RENEW_AFTER} from './decide.mjs';
const DAY=86400000;
const authFailure=error=>/No Accounts|authentication|sign.in|session.*expir|account.*(missing|expired|invalid)|credentials/i.test(error);
const assessment=(kind,summary,extra={})=>({kind,summary,...extra});
function attention(state,reason,body){return assessment('needs-input',body,{notice:{key:reason+':'+(state.release?.hash??'unconfigured'),title:'PowWorm renewal needs you',body,links:[]}});}

/** Fixed maintenance authority only. No model, app launch, auth entry, or chat send. */
export async function maintain({force=false,home=HOME,lockPath=LOCK,io={}}={}){
 const now=(io.now??Date.now)(),read=()=>io.read?io.read():readMaintenance(home),save=value=>io.save?io.save(value):saveMaintenance(value,home);
 let state=read();const decision=plan(state,now,{force});
 if(decision==='unconfigured')return attention(state,'release-missing','Automatic renewal needs a verified installed PowWorm release registered on this Mac.');
 if(decision==='authentication')return attention(state,'apple-auth','Sign in to the existing Apple Account in Xcode, then resume PowWorm renewal.');
 if(decision==='review')return attention(state,'data-review','PowWorm installed, but saved files changed during verification. Review the retained backups before another automatic install.');
 if(decision==='healthy')return assessment('watching','PowWorm signing is healthy; no device or account access needed.');
 if(decision==='backoff')return assessment('watching','Renewal retry is saved; waiting for its bounded backoff.');
 const reach=await(io.probe??probePhone)();
 if(!phoneReady(reach,force)){
  const since=state.waitingSince??now;save({...state,kind:'waiting',waitingSince:since,summary:'Waiting for the phone on Wi-Fi or USB with its screen locked.'});
  return needsConnectionNotice(state,now,since)?attention(state,'phone-away','Leave the iPhone on the Mac’s Wi-Fi or connect it by USB, then lock its screen so PowWorm can renew.'):assessment('watching','Phone not ready; saved work is untouched and renewal will retry.');
 }
 const lock=(io.lock??takeLock)(lockPath);if(!lock)return state.release.expiresAt<now+DAY?attention(state,'maintenance-busy','PowWorm renewal is waiting on another installation or its retained lock. Review maintenance ownership on the Mac before expiry.'):assessment('watching','Another PowWorm installation owns the maintenance lock.');
 const controller=new AbortController(),stop=()=>controller.abort(),deadline=setTimeout(stop,10*60000);
 process.once('SIGTERM',stop);process.once('SIGINT',stop);
 const commandIO={signal:controller.signal,onChild:lock.onChild,...io.commandIO};
 const attempt=join(home,'attempts',randomUUID());mkdirSync(attempt,{recursive:true,mode:0o700});
 try{
  state=read();(io.verify??verifyRelease)(state.release);
  const current=await(io.installed??installedApp)(commandIO);
  if(current?.bundleVersion!==state.release.build||current?.version!==state.release.version||!state.release.installedURL||current?.url!==state.release.installedURL)return attention(state,'release-changed','PowWorm has a different installed identity. Register its latest release before maintenance; no older app was installed.');
  let pending=state.pending;
  if(!pending||pending.expiresAt<now+DAY){
   save({...state,kind:'working',summary:'Renewing the installed release’s signing profiles.'});
   const prepared=await(io.prepare??provisionAndSign)(state.release,attempt,commandIO);
   pending={...prepared,hash:(io.hash??treeHash)(prepared.app)};
   state={...state,kind:'prepared',pending};save(state);
  }
  (io.verify??verifyRelease)(pending);
  const ready=await(io.probe??probePhone)();
  if(!phoneReady(ready,force)){save({...state,kind:'prepared',pending,summary:'Fresh signing is prepared; waiting for the locked phone.'});return assessment('watching','Prepared renewal is saved for the next safe connection.');}
  save({...state,kind:'installing',pending,summary:'Installing the same PowWorm release in place.'});
  const verification=await(io.install??installAndVerify)(pending.app,state.release,join(attempt,'install'),commandIO);
  const release=await(io.capture??captureRelease)(pending.app,{home,...commandIO});release.installedAt=Date.now();release.installedURL=verification.installedURL;
  const receipt=join(attempt,'receipt.json');atomicJSON(receipt,{release,verification,previousHash:state.release.hash,finishedAt:Date.now()});
  save({kind:'healthy',release,verification,receipt,summary:'PowWorm renewed in place; saved data verified.'});
  return assessment('watching','PowWorm renewed automatically; saved work preserved and the app left closed.');
 }catch(error){
  state=read();const text=String(error.message??error).slice(0,1200);
  const kind=authFailure(text)?'needs_auth':/Saved data changed/.test(text)?'needs_review':'failed';
  save({...state,kind,error:text,retryAt:now+RETRY_RENEW_AFTER,summary:kind==='needs_auth'?'Apple authentication is required.':'Renewal stopped; installed app and backups retained.'});
  if(kind==='needs_auth')return attention(state,'apple-auth','Apple needs you to sign in again in Xcode. Automatic renewal has stopped at authentication; your installed app is preserved.');
  if(kind==='needs_review')return attention(state,'data-review','Saved files changed during installation verification. Retained backups need review; newer data was not overwritten.');
  return state.release.expiresAt<now+DAY?attention(state,'renewal-failed','PowWorm renewal failed with less than a day left. Open its maintenance record on the Mac for the saved error.'):assessment('watching','Renewal failed safely; a bounded retry is saved before expiry.');
 }finally{clearTimeout(deadline);process.removeListener('SIGTERM',stop);process.removeListener('SIGINT',stop);lock.release();save(read());}
}

export async function adoptInstalled(app,{home=HOME,io={}}={}){
 const lock=(io.lock??takeLock)();if(!lock)throw Error('Another installation is active');
 try{const commandIO={onChild:lock.onChild};const release=await(io.capture??captureRelease)(app,{home,...commandIO});const current=await(io.installed??installedApp)(commandIO);if(current?.bundleVersion!==release.build||current?.version!==release.version||!current.url)throw Error('Release does not match the installed version');release.installedAt=Date.now();release.installedURL=current.url;saveMaintenance({kind:'healthy',release,summary:'Installed release captured for automatic renewal.'},home);return release;}
 finally{lock.release();saveMaintenance(readMaintenance(home),home);}
}

/** First-party release installer: upgrades and capture share the maintenance lock. */
export async function installRelease(app,{home=HOME,io={}}={}){
 const lock=(io.lock??takeLock)();if(!lock)throw Error('Another installation is active');
 const controller=new AbortController(),stop=()=>controller.abort();process.once('SIGTERM',stop);process.once('SIGINT',stop);
 try{
  const release=await(io.capture??captureRelease)(app,{home,signal:controller.signal,onChild:lock.onChild}),attempt=join(home,'attempts','install-'+randomUUID());mkdirSync(attempt,{recursive:true});
  const previousRelease=readMaintenance(home).release;
  const verification=await(io.install??installAndVerify)(release.app,release,attempt,{signal:controller.signal,onChild:lock.onChild,allowUpgrade:true,previousRelease});
  release.installedAt=Date.now();release.installedURL=verification.installedURL;const receipt=join(attempt,'receipt.json');atomicJSON(receipt,{release,verification,finishedAt:Date.now()});saveMaintenance({kind:'healthy',release,verification,receipt,summary:'Latest installed release registered for renewal.'},home);return release;
 }finally{process.removeListener('SIGTERM',stop);process.removeListener('SIGINT',stop);lock.release();saveMaintenance(readMaintenance(home),home);}
}
