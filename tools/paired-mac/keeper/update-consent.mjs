import {mkdirSync,readFileSync} from 'node:fs';
import {join} from 'node:path';
import {device} from './device.mjs';
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function parseUpdateConsent(bytes,product){
 const value=JSON.parse(bytes);
 const keys=['schemaVersion','product','automaticUpdates','revision','manualCheckRequest'];
 if(!value||Array.isArray(value)||Object.keys(value).some(k=>!keys.includes(k))||value.schemaVersion!==1||value.product!==product.bundle||typeof value.automaticUpdates!=='boolean'||!uuid.test(value.revision)||!(value.manualCheckRequest==null||uuid.test(value.manualCheckRequest)))throw Error('Invalid update consent');
 return value;
}
/** This reads the device now, never a cached ON value. Failure is a deferral. */
export async function readUpdateConsent(product,workspace,io={}){
 mkdirSync(workspace,{recursive:true,mode:0o700});const file=join(workspace,'consent.json');
 try{
  await(io.device??device)(['copy','from','--domain-type','appDataContainer','--domain-identifier',product.bundle,'--source',product.consentFile,'--destination',file],io);
  return {kind:'read',policy:parseUpdateConsent(readFileSync(file,'utf8'),product)};
 }catch{return {kind:'defer',reason:'Current iPhone update choice unavailable; no feature update authorized.'};}
}
export function requireUpdateAuthority(consent,{manualRequest,automatic=true}={}){
 if(consent?.kind!=='read')throw Error('Current phone update consent unavailable');
 if(manualRequest)throw Error('Check for updates requests authorize discovery only; installation requires automatic consent or an explicit paired-Mac operator action');
 if(!automatic||consent.policy.automaticUpdates!==true)throw Error('Automatic phone updates are off');
 return consent.policy.revision;
}
