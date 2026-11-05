import {compareRelease} from './release-version.mjs';
import {mkdirSync} from 'node:fs';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {requireProduct} from './products.mjs';
import {takeLock,readMaintenance,saveMaintenance,atomicJSON} from './state.mjs';
import {captureRelease,verifyRelease} from './artifact.mjs';
import {installedApp,installAndVerify} from './device.mjs';
import {signProduct,renewProductSigning} from './product-signing.mjs';
import {authenticatedPayload} from './authenticated-payload.mjs';
import {readUpdateConsent,requireUpdateAuthority} from './update-consent.mjs';

/** One shared lock across legacy renewal, product installs and device builds. */
export async function withProductLock(product,operation,io={}){
 requireProduct(product);const lock=(io.lock??takeLock)(product.lockPath);if(!lock)throw Error('Another build, renewal or installation is active');
 const attempt=join(product.home,'attempts',randomUUID());mkdirSync(attempt,{recursive:true,mode:0o700});
 try{return await operation(attempt,{...io,product,onChild:lock.onChild});}finally{lock.release();}
}

/** Bootstrap is explicitly requested by the operator; no consent exists yet.
 * Updates require current phone consent. Operator installs are separate from
 * automatic delivery and must be invoked for a specifically authorized app. */
export async function installProduct(product,app,{bootstrap=false,operator=false,io={}}={}){
 if(!bootstrap&&!operator)throw Error('Use the consent-gated published release delivery for automatic updates');
 return withProductLock(product,async(attempt,commandIO)=>{
  const current=await(io.installedApp??installedApp)(commandIO);
  if(bootstrap&&current)throw Error('Bootstrap requires an absent destination app');
  if(!bootstrap&&!current)throw Error('First installation requires explicit bootstrap');
  const release=await(io.capture??captureRelease)(app,{home:product.home,...commandIO});
  return installCaptured(product,release,attempt,{...commandIO,bootstrap,allowUpgrade:true});
 },io);
}

async function installCaptured(product,release,attempt,io){
 const previousRelease=readMaintenance(product.home).release;
 const verification=await(io.install??installAndVerify)(release.app,release,join(attempt,'install'),{...io,previousRelease});
 release.installedAt=Date.now();release.installedURL=verification.installedURL;
 const receipt=join(attempt,'receipt.json');atomicJSON(receipt,{release,verification,finishedAt:Date.now()});
 saveMaintenance({kind:'healthy',release,verification,receipt,summary:product.name+' installed; preservation verified.'},product.home);
 return {release,verification,receipt};
}

/** Trusted outer Mac release seals the unsigned phone archive. Never accepts
 * an arbitrary public ZIP or a server-provided digest as proof of identity. */
export async function deliverPublishedProduct(product,options,io={}){
 return withProductLock(product,async(attempt,commandIO)=>{
  const read=()=> (io.readConsent??readUpdateConsent)(product,join(attempt,'consent-'+randomUUID()),commandIO);
  const first=await read();requireUpdateAuthority(first);
  const payload=await(io.payload??authenticatedPayload)(product,{...options,workspace:join(attempt,'payload')},commandIO);
  const current=await(io.installedApp??installedApp)(commandIO);
  if(!current)throw Error('Automatic updates cannot bootstrap an uninstalled app');
  if(compareRelease(payload.manifest,current)<=0)return {kind:'current',build:current.bundleVersion};
  const signed=await(io.sign??signProduct)(product,payload.app,join(attempt,'signed'),commandIO);
  const release=await(io.capture??captureRelease)(signed.app,{home:product.home,...commandIO});
  const beforeInstall=async()=>{const fresh=await read();requireUpdateAuthority(fresh);if(fresh.policy.revision!==first.policy.revision)throw Error('Phone update choice changed during preparation; retry with fresh consent');};
  return installCaptured(product,release,attempt,{...commandIO,allowUpgrade:true,beforeInstall});
 },io);
}

/** Renewal uses only the registered frozen app. It neither discovers a release
 * nor uses the feature-update switch as permission to change app contents. */
export async function renewProduct(product,{force=false,io={}}={}){
 return withProductLock(product,async(attempt,commandIO)=>{
  const saved=readMaintenance(product.home),release=verifyRelease(saved.release);
  if(!force&&release.expiresAt>Date.now()+48*3600000)return {kind:'healthy',expiresAt:release.expiresAt};
  const current=await(io.installedApp??installedApp)(commandIO);
  if(current?.bundleVersion!==release.build||current?.version!==release.version||current?.url!==release.installedURL)throw Error('Installed identity changed; renew only the registered frozen release');
  const signed=await(io.renewSigning??renewProductSigning)(product,release,join(attempt,'renewed'),commandIO);
  const verification=await(io.install??installAndVerify)(signed.app,release,join(attempt,'install'),commandIO);
  const captured=await(io.capture??captureRelease)(signed.app,{home:product.home,...commandIO});
  captured.installedAt=Date.now();captured.installedURL=verification.installedURL;
  const receipt=join(attempt,'receipt.json');atomicJSON(receipt,{release:captured,verification,previousHash:release.hash,finishedAt:Date.now()});
  saveMaintenance({kind:'healthy',release:captured,verification,receipt,summary:product.name+' frozen release renewed.'},product.home);
  return {release:captured,verification,receipt};
 },io);
}
