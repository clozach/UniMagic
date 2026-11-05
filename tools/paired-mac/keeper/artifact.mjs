import {readFileSync,readdirSync,mkdirSync,cpSync,renameSync,existsSync,lstatSync,rmSync,writeFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {createHash,randomUUID} from 'node:crypto';
import {run} from './process.mjs';
import {HOME,atomicJSON} from './state.mjs';
import {signingTargets,embeddedKeyboardBuild} from './signing-targets.mjs';
import {requireProduct} from './products.mjs';
import {inspectCapabilities,groupsForTarget,requireProfileGroups} from './release-capabilities.mjs';
export const BUNDLE='com.clozach.amaanah.alerts',TEAM='AD29JN9GKN',IDENTITY='8570B3D50CF453628EF2656136D36C7E47D47569';
export function treeHash(directory){const hash=createHash('sha256');const visit=(path,relative='')=>{for(const name of readdirSync(path).sort()){const file=join(path,name),key=relative+name,stat=lstatSync(file);if(stat.isSymbolicLink())throw Error('Release must not contain symlinks');if(stat.isDirectory())visit(file,key+'/');else{hash.update(key+'\0');hash.update(readFileSync(file));}}};visit(directory);return hash.digest('hex');}
export async function plist(file,key,io={}){return (await (io.run??run)('/usr/bin/plutil',['-extract',key,'raw',file],io)).stdout.trim();}
export async function profileInfo(file,workspace,io={}){const xml=join(workspace,randomUUID()+'.plist');const {stdout}=await(io.run??run)('/usr/bin/security',['cms','-D','-i',file],io);writeFileSync(xml,stdout,{mode:0o600});const entitlements=JSON.parse((await(io.run??run)('/usr/bin/plutil',['-extract','Entitlements','json','-o','-',xml],io)).stdout);let devices=[];try{devices=JSON.parse((await(io.run??run)('/usr/bin/plutil',['-extract','ProvisionedDevices','json','-o','-',xml],io)).stdout);}catch{}return {devices,expiresAt:Date.parse(await plist(xml,'ExpirationDate',io)),app:await plist(xml,'Entitlements.application-identifier',io),uuid:await plist(xml,'UUID',io),entitlements,xml};}
async function signedEntitlements(bundle,workspace,io){
 const {stdout}=await(io.run??run)('/usr/bin/codesign',['-d','--entitlements',':-',bundle],io);
 const file=join(workspace,randomUUID()+'-signed.plist');writeFileSync(file,stdout,{mode:0o600});
 return JSON.parse((await(io.run??run)('/usr/bin/plutil',['-convert','json','-o','-',file],io)).stdout);
}
export async function inspectApp(app,workspace,io={}){
 const product=io.product?requireProduct(io.product):null,expectedBundle=product?.bundle??BUNDLE,expectedTeam=product?.team??TEAM;
 await(io.run??run)('/usr/bin/codesign',['--verify','--deep','--strict',app],io);
 const bundle=await plist(join(app,'Info.plist'),'CFBundleIdentifier',io),build=await plist(join(app,'Info.plist'),'CFBundleVersion',io),version=await plist(join(app,'Info.plist'),'CFBundleShortVersionString',io);
 if(bundle!==expectedBundle||!/^\d+$/.test(build))throw Error('Unexpected release identity');
 const retired=!product&&Number(build)>=16;
 if((!retired&&!existsSync(join(app,'corpus.sqlite')))||(!product&&!existsSync(join(app,'Assets.car'))))throw Error('Current native resources/corpus missing');
 if(retired&&(existsSync(join(app,'corpus.sqlite'))||!['false','0'].includes(await plist(join(app,'Info.plist'),'UniMagicLegacyKeyboardRetained',io))))throw Error('Retired PowWorm package must omit its legacy corpus and keyboard');
 const targets=product?product.targets:signingTargets(app,{requireKeyboard:embeddedKeyboardBuild(build)}),profiles=[],signed=[];
 if(retired&&targets.some(t=>t.key==='keyboard'))throw Error('Retired keyboard still embedded');
 if(product){const actual=readdirSync(join(app,'PlugIns')).filter(name=>name.endsWith('.appex')).sort(),expected=targets.filter(t=>t.path).map(t=>t.path.split('/').at(-1)).sort();if(JSON.stringify(actual)!==JSON.stringify(expected))throw Error('Product extensions differ');}
 for(const target of targets){
  const path=join(app,target.path),profile=await profileInfo(join(path,'embedded.mobileprovision'),workspace,io);
  if(profile.app!==expectedTeam+'.'+expectedBundle+target.suffix)throw Error('Unexpected profile team/app');
  if(await plist(join(path,'Info.plist'),'CFBundleIdentifier',io)!==expectedBundle+target.suffix)throw Error('Unexpected extension identity');
  if(product&&(await plist(join(path,'Info.plist'),'CFBundleShortVersionString',io))!==version)throw Error('Extension marketing version differs from app');
  if(await plist(join(path,'Info.plist'),'CFBundleVersion',io)!==build)throw Error('Extension version differs from app');
  let fullAccess;
  if(target.key==='keyboard'){
   if(await plist(join(path,'Info.plist'),'NSExtension.NSExtensionPointIdentifier',io)!=='com.apple.keyboard-service')throw Error('Keyboard extension point missing');
   const declaration=await plist(join(path,'Info.plist'),'NSExtension.NSExtensionAttributes.RequestsOpenAccess',io);
   if(!['false','0','true','1'].includes(declaration))throw Error('Invalid keyboard Full Access declaration');
   fullAccess=['true','1'].includes(declaration);
   if(!existsSync(join(path,'corpus.sqlite'))||!readFileSync(join(path,'corpus.sqlite')).equals(readFileSync(join(app,'corpus.sqlite'))))throw Error('Keyboard corpus differs from app');
  }
  profiles.push(profile);
  const entitlements=await signedEntitlements(path,workspace,io);
  if(product){
   if(entitlements['application-identifier']!==expectedTeam+'.'+expectedBundle+target.suffix||entitlements['com.apple.developer.team-identifier']!==expectedTeam)throw Error('Signed target identity differs');
   if(profile.expiresAt<Date.now()+600000)throw Error('Product signing profile expired or expires shortly');
   const certPath=join(workspace,'certificate-'+target.key);await(io.run??run)('/usr/bin/codesign',['-d','--extract-certificates='+certPath,path],io);
   if(createHash('sha1').update(readFileSync(certPath+'0')).digest('hex').toUpperCase()!==product.identity)throw Error('Extension signing certificate differs');
  }
  signed.push({key:target.key,entitlements,fullAccess});
 }
 const capabilities=inspectCapabilities(signed,product?.appGroup);
 if(product){for(const target of targets.filter(t=>['app','keyboard'].includes(t.key)))if(await plist(join(app,target.path,'Info.plist'),'UniMagicVisibilityAppGroup',io)!==product.appGroup)throw Error('Configured visibility group differs from signed release');}
 if(product&&signed.find(t=>t.key==='keyboard')?.fullAccess!==false)throw Error('Standalone keyboard Full Access must stay off');
 for(let i=0;i<targets.length;i++)requireProfileGroups(profiles[i].entitlements,groupsForTarget(capabilities,targets[i].key,product?.appGroup));
 const cert=join(workspace,'certificate');await(io.run??run)('/usr/bin/codesign',['-d','--extract-certificates='+cert,app],io);
 if(createHash('sha1').update(readFileSync(cert+'0')).digest('hex').toUpperCase()!==(product?.identity??IDENTITY))throw Error('Unexpected release signing certificate');
 return {...(product?{product:product.id}:{}),bundle,build,version,targets:targets.map(target=>target.key),capabilities,expiresAt:Math.min(...profiles.map(profile=>profile.expiresAt))};
}
export async function captureRelease(app,{home=HOME,...io}={}){
 mkdirSync(home,{recursive:true,mode:0o700});const staging=join(home,'capture-'+randomUUID());mkdirSync(staging,{mode:0o700});
 const appName=io.product?.appName??'PowWorm.app';const copy=join(staging,appName);cpSync(resolve(app),copy,{recursive:true});let info;try{info=await inspectApp(copy,staging,io);}catch(error){rmSync(staging,{recursive:true});throw error;}const hash=treeHash(copy),folder=join(home,'releases',hash);mkdirSync(join(home,'releases'),{recursive:true});
 const release={...info,hash,app:join(folder,appName),capturedAt:Date.now()};atomicJSON(join(staging,'release.json'),release);
 if(!existsSync(folder))renameSync(staging,folder);else rmSync(staging,{recursive:true});
 return release;
}
export function verifyRelease(release){if(!release?.app||treeHash(release.app)!==release.hash)throw Error('Frozen release is missing or changed');return release;}
