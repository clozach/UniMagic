import {mkdirSync,readdirSync,readFileSync} from 'node:fs';
import {join,relative} from 'node:path';
import {createHash} from 'node:crypto';
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
export async function installAndVerify(app,release,attempt,io={}){
 const installed=await(io.installedApp??installedApp)(io);
 if(!installed&&io.bootstrap===true){
  await io.beforeInstall?.();
  const receipt=await(io.device??device)(['install','app',app],io);
  const readback=await(io.installedApp??installedApp)(io);
  if(readback?.bundleVersion!==release.build||readback?.version!==release.version||!readback.url)throw Error('Bootstrap installed readback differs');
  return {receipt,savedFiles:0,installedURL:readback.url,verifiedAt:Date.now(),bootstrap:true};
 }
 if(!installed||(!io.allowUpgrade&&(installed.bundleVersion!==release.build||installed.version!==release.version||installed.url!==release.installedURL))||(io.allowUpgrade&&(io.product?compareRelease(installed,release)>0:Number(installed.bundleVersion)>Number(release.build))))throw Error('Installed identity differs from the saved release; refuse a downgrade');
 const preserved=io.previousRelease??release;
 if(io.previousRelease&&(installed.bundleVersion!==preserved.build||installed.version!==preserved.version||installed.url!==preserved.installedURL))throw Error('Installed identity differs from preservation baseline');
 if(io.allowUpgrade&&!io.previousRelease&&releaseCapabilities(release.capabilities,io.product?.appGroup).kind==='unimagic-sharing')throw Error('Shared upgrade requires a verified installed preservation baseline');
 const snapshotIO={...io,snapshotRelease:preserved};
 const before=await(io.snapshotSaved??snapshotSaved)(join(attempt,'saved-before'),snapshotIO);
 await io.beforeInstall?.();
 const receipt=await(io.device??device)(['install','app',app],io);
 const afterApp=await(io.installedApp??installedApp)(io);
 if(afterApp?.bundleVersion!==release.build||afterApp?.version!==release.version)throw Error('Installed app readback differs');
 const after=await(io.snapshotSaved??snapshotSaved)(join(attempt,'saved-after'),snapshotIO);
 const savedData=compareSavedData(before,after,join(attempt,'saved-before'),join(attempt,'saved-after'));
 return {receipt,savedFiles:Object.keys(before).length,savedData,installedURL:afterApp.url,verifiedAt:Date.now()};
}
