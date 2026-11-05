import {mkdirSync,readdirSync,readFileSync} from 'node:fs';
import {join,relative} from 'node:path';
import {createHash} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {run} from './process.mjs';
import {ROOT,readJSON} from './state.mjs';
import {BUNDLE} from './artifact.mjs';
import {compareSavedData} from './saved-data.mjs';
import {snapshotExtraDomains} from './snapshot-domains.mjs';
import {compareRelease} from './release-version.mjs';
import {releaseCapabilities} from './release-capabilities.mjs';
export const PHONE=process.env.UNIMAGIC_DEVICE_ID??readJSON(join(ROOT,'native-device.json'))?.identifier??null;
export async function resolvePhone(io={}){
 if(io.phone??PHONE)return io.phone??PHONE;
 if(!io.product)throw Error('Paired device unconfigured; set native-device.json identifier in private state');
 const response=await(io.run??run)('/usr/bin/xcrun',['devicectl','list','devices','--json-output','-'],io);
 const devices=JSON.parse(response.stdout).result?.devices;
 if(!Array.isArray(devices))throw Error('Paired iPhone discovery unavailable');
 const eligible=devices.filter(d=>d.hardwareProperties?.platform==='iOS'&&d.connectionProperties?.pairingState==='paired'&&d.hardwareProperties?.deviceType==='iPhone');
 if(eligible.length!==1)throw Error('Select one paired iPhone with --phone or private device configuration');
 return eligible[0].identifier;
}
export async function device(args,io={}){const phone=await resolvePhone(io);const response=await(io.run??run)('/usr/bin/xcrun',['devicectl','device',...args,'--device',phone,'--timeout','45','--json-output','-'],{...io,timeout:60000});return JSON.parse(response.stdout);}
export async function probePhone(io={}){try{const r=await device(['info','lockState'],io);return {reachable:true,locked:r.result?.passcodeRequired===true};}catch{return {reachable:false};}}
export async function installedApp(io={}){const r=await device(['info','apps'],io);const apps=r.result?.apps??[];return apps.find(x=>x.bundleIdentifier===(io.product?.bundle??BUNDLE))??null;}
export function savedHashes(directory){const result={};const visit=path=>{for(const item of readdirSync(path,{withFileTypes:true}).sort((a,b)=>a.name.localeCompare(b.name))){const file=join(path,item.name);if(item.isDirectory())visit(file);else result[relative(directory,file)]=createHash('sha256').update(readFileSync(file)).digest('hex');}};visit(directory);return result;}
export async function snapshotSaved(folder,io={}){mkdirSync(folder,{recursive:true,mode:0o700});const execute=io.device??device;for(const [name,source]of [['support','Library/Application Support'],['preferences','Library/Preferences']]){const destination=join(folder,name);mkdirSync(destination,{recursive:true,mode:0o700});await execute(['copy','from','--domain-type','appDataContainer','--domain-identifier',io.product?.bundle??BUNDLE,'--source',source,'--destination',destination],io);}await snapshotExtraDomains(folder,io.snapshotRelease,execute,io);return savedHashes(folder);}
function abortable(promise,signal){
 signal.throwIfAborted();
 return new Promise((resolve,reject)=>{
  const cleanup=()=>signal.removeEventListener('abort',stopped);
  const stopped=()=>{cleanup();reject(signal.reason);};signal.addEventListener('abort',stopped,{once:true});
  Promise.resolve(promise).then(value=>{cleanup();resolve(value);},error=>{cleanup();reject(error);});
 });
}
function installationURL(receipt,bundle){
 const apps=receipt?.result?.installedApplications;if(!Array.isArray(apps)||!apps.length)return null;
 const matching=apps.filter(app=>(app.bundleID??app.bundleIdentifier)===bundle);
 if(matching.length!==1)throw Error('Installed app readback differs: OS receipt bundle is missing or ambiguous');
 const url=matching[0].installationURL;
 if(url===undefined)return null;
 if(typeof url!=='string'||!url.trim())throw Error('Installed app readback differs: invalid OS installation URL');
 return url;
}
/** CoreDevice can briefly return its previous catalogue after a successful OS
 * install. Poll reads only: one install, exact identity, fresh receipt URL when
 * supplied, and no saved-after snapshot until that metadata is observed. */
export async function waitForInstalledMetadata(release,receipt,io={}){
 const timeout=io.readbackTimeoutMs??20000,interval=io.readbackPollMs??500;
 if(!Number.isInteger(timeout)||timeout<1||timeout>30000||!Number.isInteger(interval)||interval<1||interval>1000)throw Error('Invalid bounded installed-metadata polling policy');
 const bundle=release.bundle??io.product?.bundle??BUNDLE,expectedURL=installationURL(receipt,bundle);
 const now=io.readbackNow??(()=>performance.now()),deadline=now()+timeout,controller=new AbortController();
 const timedOut=()=>Error('Installed app readback differs: metadata refresh timed out; installation was not repeated');
 const stop=()=>controller.abort(io.signal.reason??Error('Installed app readback aborted'));
 io.signal?.throwIfAborted();io.signal?.addEventListener('abort',stop,{once:true});
 const timer=setTimeout(()=>controller.abort(timedOut()),timeout);
 const sleep=io.readbackSleep??((ms,signal)=>delay(ms,undefined,{signal}));
 try{
  for(let attempt=0;attempt<=Math.ceil(timeout/interval);attempt++){
   controller.signal.throwIfAborted();if(now()>=deadline)throw timedOut();
   let app;
   try{app=await abortable((io.installedApp??installedApp)({...io,signal:controller.signal}),controller.signal);}
   catch(error){if(controller.signal.aborted)throw controller.signal.reason;app=null;}
   controller.signal.throwIfAborted();if(now()>=deadline)throw timedOut();
   if(app?.bundleIdentifier&&app.bundleIdentifier!==bundle)throw Error('Installed app readback differs: wrong bundle identity');
   if(app?.bundleIdentifier===bundle&&app.bundleVersion===release.build&&app.version===release.version&&typeof app.url==='string'&&app.url.trim()&&(!expectedURL||app.url===expectedURL))return app;
   const remaining=deadline-now();if(remaining<=0)throw timedOut();
   await abortable(sleep(Math.min(interval,remaining),controller.signal),controller.signal);
  }
  throw timedOut();
 }finally{clearTimeout(timer);io.signal?.removeEventListener('abort',stop);}
}
export async function installAndVerify(app,release,attempt,io={}){
 const installed=await(io.installedApp??installedApp)(io);
 if(!installed&&io.bootstrap===true){
  await io.beforeInstall?.();
  const receipt=await(io.device??device)(['install','app',app],io);
  const readback=await waitForInstalledMetadata(release,receipt,io);
  return {receipt,savedFiles:0,installedURL:readback.url,verifiedAt:Date.now(),bootstrap:true};
 }
 if(!installed||(!io.allowUpgrade&&(installed.bundleVersion!==release.build||installed.version!==release.version||installed.url!==release.installedURL))||(io.allowUpgrade&&(io.product?compareRelease(installed,release)>0:Number(installed.bundleVersion)>Number(release.build))))throw Error('Installed identity differs from the saved release; refuse a downgrade');
 const preserved=io.previousRelease??release;
 if(io.previousRelease&&(installed.bundleVersion!==preserved.build||installed.version!==preserved.version||installed.url!==preserved.installedURL))throw Error('Installed identity differs from preservation baseline');
 if(io.allowUpgrade&&!io.previousRelease&&releaseCapabilities(release.capabilities,io.product?.appGroup).kind==='unimagic-sharing')throw Error('Shared upgrade requires a verified installed preservation baseline');
 const retiresKeyboard=!io.product&&Number(installed.bundleVersion)>=10&&Number(installed.bundleVersion)<16&&Number(release.build)>=16;
 if(retiresKeyboard&&(!io.previousRelease||!io.allowUpgrade||typeof io.verifyKeyboardRetirement!=='function'))throw Error('Use the explicit verified keyboard retirement installer');
 const snapshotIO={...io,snapshotRelease:preserved};
 const before=await(io.snapshotSaved??snapshotSaved)(join(attempt,'saved-before'),snapshotIO);
 const retiredFiles=retiresKeyboard?await io.verifyKeyboardRetirement({attempt,before,release,previous:preserved}):null;
 await io.beforeInstall?.();
 const receipt=await(io.device??device)(['install','app',app],io);
 const afterApp=await waitForInstalledMetadata(release,receipt,io);
 const after=await(io.snapshotSaved??snapshotSaved)(join(attempt,'saved-after'),retiresKeyboard?{...io,snapshotRelease:release}:snapshotIO);
 const retained=retiresKeyboard?Object.fromEntries(Object.entries(before).filter(([path])=>!path.startsWith('keyboard/')&&!path.startsWith('shared/'))):before;
 const savedData=compareSavedData(retained,after,join(attempt,'saved-before'),join(attempt,'saved-after'));
 return {receipt,...(retiredFiles?{retiredFiles}:{}),savedFiles:Object.keys(retained).length,savedData,installedURL:afterApp.url,verifiedAt:Date.now()};
}
