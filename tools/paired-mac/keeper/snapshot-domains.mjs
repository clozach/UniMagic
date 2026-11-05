import {join} from 'node:path';
import {mkdirSync} from 'node:fs';
import {releaseCapabilities} from './release-capabilities.mjs';

/** Snapshot the installed release's stores, including keyboard-local history.
 * Optional directories are skipped only after successful explicit enumeration;
 * an inaccessible container or failed listing must stop before installation. */
export async function snapshotExtraDomains(folder,release,device,io={}) {
 const domains=[];
 if((release?.targets??[]).includes('keyboard')||Number(release?.build)>=10)
  domains.push({name:'keyboard',type:'appDataContainer',identifier:(io.product?.bundle??'com.clozach.amaanah.alerts')+'.keyboard'});
 const capabilities=releaseCapabilities(release?.capabilities,io.product?.appGroup);
 if(capabilities.kind==='unimagic-sharing')domains.push({name:'shared',type:'appGroupDataContainer',identifier:capabilities.appGroup});
 for(const domain of domains){
  const args=['--domain-type',domain.type,'--domain-identifier',domain.identifier];
  const list=async subdirectory=>{
   const response=await device(['info','files',...args,...(subdirectory?['--subdirectory',subdirectory]:[]),'--no-recurse'],io);
   if(!Array.isArray(response.result?.files))throw Error('Saved-data directory enumeration missing');
   return response.result.files;
  };
  const root=await list();
  if(!root.some(file=>file.name==='Library'&&file.resources?.isDirectory))continue;
  const files=await list('Library');
  for(const [name,source] of [['support','Application Support'],['preferences','Preferences']]){
   if(!files.some(file=>file.name===source&&file.resources?.isDirectory))continue;
   const destination=join(folder,domain.name,name);mkdirSync(destination,{recursive:true,mode:0o700});
   await device(['copy','from',...args,'--source','Library/'+source,'--destination',destination],io);
  }
 }
 return domains.map(({name,type,identifier})=>({name,type,identifier}));
}
