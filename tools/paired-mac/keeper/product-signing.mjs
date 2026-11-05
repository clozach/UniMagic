import {mkdirSync,readdirSync,cpSync,copyFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {homedir} from 'node:os';
import {run} from './process.mjs';
import {profileInfo,inspectApp,plist} from './artifact.mjs';
import {requireProduct} from './products.mjs';
import {resolvePhone} from './device.mjs';
import {groupsForTarget,requireProfileGroups,requireSameCapabilities} from './release-capabilities.mjs';

/** Exact cached profile selection; never contacts Apple or prompts for login. */
export async function selectProductProfiles(product,workspace,io={}){
 requireProduct(product);mkdirSync(workspace,{recursive:true,mode:0o700});
 const cache=io.profileCache??join(homedir(),'Library/Developer/Xcode/UserData/Provisioning Profiles'),profiles=[];
 for(const file of readdirSync(cache).filter(x=>x.endsWith('.mobileprovision'))){
  const path=join(cache,file);try{profiles.push({path,...await(io.profileInfo??profileInfo)(path,workspace,io)});}catch{}
 }
 return Object.fromEntries(product.targets.map(target=>{
  const candidates=profiles.filter(p=>p.app===product.team+'.'+product.bundle+target.suffix&&p.expiresAt>(io.now??Date.now)()+(io.minimumRemaining??3600000))
   .filter(p=>!io.phone||(p.devices??[]).includes(io.phone))
   .filter(p=>{try{requireProfileGroups(p.entitlements,['app','keyboard'].includes(target.key)?[product.appGroup]:[]);return true;}catch{return false;}})
   .sort((a,b)=>b.expiresAt-a.expiresAt);
  if(!candidates.length)throw Error('No valid cached profile for '+product.bundle+target.suffix+'; bootstrap requires Apple provisioning on the paired Mac. No account access attempted.');
  return [target.key,candidates[0]];
 }));
}

/** Signs only the explicit frozen target set under the caller's install lock. */
export async function signProduct(product,source,workspace,io={}){
 requireProduct(product);const phone=await(io.resolvePhone??resolvePhone)({...io,product});
 io={...io,phone};const execute=io.run??run,selected=await(io.selectProfiles??selectProductProfiles)(product,workspace,io);
 const app=join(workspace,product.appName);cpSync(source,app,{recursive:true});
 for(const target of product.targets){
  const profile=selected[target.key],bundle=join(app,target.path),file=join(workspace,target.key+'-entitlements.plist');
  const groups=['app','keyboard'].includes(target.key)?[product.appGroup]:[];
  requireProfileGroups(profile.entitlements,groups);copyFileSync(profile.path,join(bundle,'embedded.mobileprovision'));
  // Grant only the configured capabilities, not arbitrary cached-profile extras.
  const entitlements={'application-identifier':product.team+'.'+product.bundle+target.suffix,'com.apple.developer.team-identifier':product.team,'keychain-access-groups':[product.team+'.'+product.bundle+target.suffix],'get-task-allow':true};
  if(groups.length)entitlements['com.apple.security.application-groups']=groups;
  writeFileSync(file,JSON.stringify(entitlements),{mode:0o600});await execute('/usr/bin/plutil',['-convert','xml1',file],io);
  for(const name of readdirSync(bundle).filter(x=>x.endsWith('.dylib')))await execute('/usr/bin/codesign',['--force','--sign',product.identity,join(bundle,name)],io);
  await execute('/usr/bin/codesign',['--force','--sign',product.identity,'--entitlements',file,bundle],io);
 }
 const inspected=await(io.inspectApp??inspectApp)(app,workspace,{...io,product});
 return {app,...inspected};
}

/** Re-signing a saved release cannot change its capabilities or build. */
export async function renewProductSigning(product,release,workspace,io={}){
 const {refreshProductProfiles}=await import('./product-provision.mjs');
 try{await selectProductProfiles(product,join(workspace,'profile-check'),{...io,minimumRemaining:6*86400000});}
 catch{await(io.refreshProfiles??refreshProductProfiles)(product,join(workspace,'refresh'),io);}
 const result=await signProduct(product,release.app,workspace,{...io,minimumRemaining:6*86400000});
 requireSameCapabilities(release.capabilities,result.capabilities,product.appGroup);
 if(result.bundle!==release.bundle||result.build!==release.build||result.version!==release.version)throw Error('Renewal changed frozen release identity');
 return result;
}
