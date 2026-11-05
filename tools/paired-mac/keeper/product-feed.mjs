import {mkdirSync,readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {createHash,randomUUID} from 'node:crypto';
import {withProductLock} from './product-delivery.mjs';
import {readJSON,atomicJSON,readMaintenance,saveMaintenance} from './state.mjs';
import {device,installedApp,installAndVerify} from './device.mjs';
import {readUpdateConsent,requireUpdateAuthority} from './update-consent.mjs';
import {authenticatedPayload} from './authenticated-payload.mjs';
import {signProduct} from './product-signing.mjs';
import {captureRelease} from './artifact.mjs';
import {run} from './process.mjs';
import {compareRelease} from './release-version.mjs';
import {requireSafeZip} from './zip-safety.mjs';
const repo='clozach/UniMagic',api='https://api.github.com/repos/'+repo+'/releases/latest';
const DAY=86400000;

async function githubRelease(io){
 const response=await(io.fetch??fetch)(api,{headers:{Accept:'application/vnd.github+json','X-GitHub-Api-Version':'2022-11-28'},signal:AbortSignal.timeout(20000)});
 if(!response.ok)throw Error('GitHub release lookup returned '+response.status);
 const release=await response.json(),match=/^v(\d+\.\d+\.\d+)$/.exec(release.tag_name??'');
 if(!match||release.draft||release.prerelease||!Array.isArray(release.assets))throw Error('Invalid official UniMagic release');
 const version=match[1],name=`UniMagic-${version}-macOS-arm64.zip`,assets=release.assets.filter(a=>a.name===name);
 if(assets.length!==1)throw Error('Official Mac release archive missing or ambiguous');
 const url=`https://github.com/${repo}/releases/download/v${version}/${name}`;
 if(assets[0].browser_download_url!==url)throw Error('Unexpected release archive location');
 return {version,url};
}
async function downloadRelease(release,workspace,io){
 const response=await(io.fetch??fetch)(release.url,{signal:AbortSignal.timeout(120000)});
 if(!response.ok)throw Error('Official release download returned '+response.status);
 const host=new URL(response.url||release.url).hostname;
 if(!['github.com','release-assets.githubusercontent.com','objects.githubusercontent.com'].includes(host))throw Error('Unexpected download redirect');
 const maximum=250*1024*1024;
 if(Number(response.headers.get('content-length'))>maximum){await response.body.cancel('Release archive exceeds limit');throw Error('Release archive exceeds limit');}
 const chunks=[];let length=0;
 const reader=response.body.getReader();
 try{while(true){const {value,done}=await reader.read();if(done)break;length+=value.length;if(length>maximum){await reader.cancel('Release archive exceeds limit');throw Error('Release archive exceeds limit');}chunks.push(value);}}finally{reader.releaseLock();}
 const bytes=Buffer.concat(chunks);requireSafeZip(bytes,'UniMagic.app');
 const archive=join(workspace,'Mac.zip');writeFileSync(archive,bytes,{mode:0o600});
 const extracted=join(workspace,'mac');mkdirSync(extracted,{mode:0o700});
 await(io.run??run)('/usr/bin/ditto',['-x','-k',archive,extracted],io);
 return join(extracted,'UniMagic.app');
}
async function writePhoneStatus(product,workspace,status,io){
 const file=join(workspace,'phone-status-'+randomUUID()+'.json');atomicJSON(file,{schemaVersion:1,product:product.bundle,checkedAt:new Date().toISOString(),...status});
 await(io.device??device)(['copy','to','--domain-type','appDataContainer','--domain-identifier',product.bundle,'--source',file,'--destination','Library/Application Support/paired-mac-update-status-v1.json'],io);
}

/** Called by the Mac app's local timer. Current phone policy is the authority;
 * no feed request/download occurs while OFF without a new phone check request.
 * Checks when OFF report availability, never grant installation permission. */
export async function checkProductUpdates(product,{trustedMacApp,manual=false,io={}}={}){
 return withProductLock(product,async(attempt,commandIO)=>{
  const fresh=()=> (io.readConsent??readUpdateConsent)(product,join(attempt,'consent-'+randomUUID()),commandIO);
  const consent=await fresh();if(consent.kind!=='read')return {kind:'waiting',message:consent.reason};
  const policy=consent.policy,statePath=join(product.home,'feed-state.json'),saved=readJSON(statePath,{});
  const requested=policy.manualCheckRequest&&policy.manualCheckRequest!==saved.manualRequest;
  const status={revision:policy.revision,manualCheckRequest:policy.manualCheckRequest??null};
  const report=async(kind,message,extra={})=>{const result={kind,message,consent:policy.automaticUpdates,...extra};await(io.writeStatus??writePhoneStatus)(product,attempt,{...status,state:kind,message,...extra},commandIO);return result;};
  if(!policy.automaticUpdates&&!requested)return {kind:'off',message:'Automatic iPhone updates are off.',consent:false};
  if(!requested&&!manual&&Date.now()<(saved.nextCheckAt??0))return {kind:'waiting',message:'Next release check is scheduled on this Mac.',consent:policy.automaticUpdates};
  try{
   const release=await(io.githubRelease??githubRelease)(commandIO),current=await(io.installedApp??installedApp)(commandIO);
   if(!current)throw Error('Standalone UniMagic is not installed; first installation requires explicit bootstrap');
   // A status-only check still authenticates the candidate before announcing it.
   const candidate=await(io.downloadRelease??downloadRelease)(release,attempt,commandIO);
   const payload=await(io.payload??authenticatedPayload)(product,{trustedMacApp,candidateMacApp:candidate,workspace:join(attempt,'payload')},commandIO);
   if(payload.manifest.version!==release.version)throw Error('Published tag and signed release version differ');
   atomicJSON(statePath,{manualRequest:policy.manualCheckRequest??null,nextCheckAt:Date.now()+DAY,version:release.version});
   if(compareRelease(payload.manifest,current)<=0)return report('current','Your iPhone has the current release.',{version:release.version});
   if(!policy.automaticUpdates)return report('available',`UniMagic ${release.version} is available. Automatic updates are off; turn them on to install through your paired Mac.`,{version:release.version});
   requireUpdateAuthority(await fresh());
   const signed=await(io.sign??signProduct)(product,payload.app,join(attempt,'signed'),commandIO);
   const captured=await(io.capture??captureRelease)(signed.app,{home:product.home,...commandIO});
   const beforeInstall=async()=>{const value=await fresh();requireUpdateAuthority(value);if(value.policy.revision!==policy.revision)throw Error('Your update choice changed; waiting for a fresh check');};
   const previousRelease=readMaintenance(product.home).release;
   const verification=await(io.install??installAndVerify)(captured.app,captured,join(attempt,'install'),{...commandIO,allowUpgrade:true,previousRelease,beforeInstall});
   captured.installedURL=verification.installedURL;captured.installedAt=Date.now();
   const receipt=join(attempt,'receipt.json');atomicJSON(receipt,{release:captured,verification,finishedAt:Date.now()});
   saveMaintenance({kind:'healthy',release:captured,verification,receipt,summary:'Published UniMagic installed; data verified.'},product.home);
   return report('installed',`UniMagic ${release.version} installed through your paired Mac.`,{version:release.version});
  }catch(error){
   atomicJSON(statePath,{...saved,manualRequest:policy.manualCheckRequest??null,nextCheckAt:Date.now()+3600000});
   return report('error',String(error.message).slice(0,350));
  }
 },io);
}
