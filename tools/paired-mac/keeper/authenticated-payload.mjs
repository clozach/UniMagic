import {readFileSync,mkdirSync,existsSync,readdirSync,lstatSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {run} from './process.mjs';
import {plist} from './artifact.mjs';
import {requireProduct} from './products.mjs';
import {requireSafeZip} from './zip-safety.mjs';

/** The trusted, locally installed Mac app's designated requirement is the pin.
 * A release page, URL, downloaded manifest or hash alone is not an authority. */
export async function authenticatedPayload(product,{trustedMacApp,candidateMacApp,workspace,macBundle='com.clozach.unimagic.mac'},io={}){
 requireProduct(product);const execute=io.run??run;
 if(resolve(trustedMacApp)===resolve(candidateMacApp))throw Error('Candidate requires independent installed Mac trust anchor');
 await execute('/usr/bin/codesign',['--verify','--deep','--strict',trustedMacApp],io);
 const requirementOutput=await execute('/usr/bin/codesign',['-d','-r-',trustedMacApp],io);
 const requirement=(requirementOutput.stderr+'\n'+requirementOutput.stdout).split('\n').find(line=>line.startsWith('designated => '))?.slice(14);
 if(!requirement||!requirement.includes('anchor apple')||!requirement.includes('certificate'))throw Error('Installed Mac app lacks a certificate-backed designated requirement');
 await execute('/usr/bin/codesign',['--verify','--deep','--strict','-R='+requirement,candidateMacApp],io);
 for(const app of [trustedMacApp,candidateMacApp])if(await plist(join(app,'Contents/Info.plist'),'CFBundleIdentifier',io)!==macBundle)throw Error('Unexpected Mac app bundle');
 const root=join(candidateMacApp,'Contents/Resources/iOS'),manifest=JSON.parse(readFileSync(join(root,'manifest.json'),'utf8'));
 if(manifest.schemaVersion!==1||manifest.product!==product.bundle||manifest.archive!=='UniMagic-iOS.unsigned.zip'||manifest.app!==product.appName||!/^\d+$/.test(manifest.build)||!/^\d+\.\d+\.\d+$/.test(manifest.version)||!/^[a-f0-9]{64}$/.test(manifest.sha256))throw Error('Invalid sealed iOS manifest');
 if(await plist(join(candidateMacApp,'Contents/Info.plist'),'CFBundleShortVersionString',io)!==manifest.version)throw Error('Mac and sealed iOS release versions differ');
 const archive=join(root,manifest.archive);
 if(createHash('sha256').update(readFileSync(archive)).digest('hex')!==manifest.sha256)throw Error('Sealed iOS archive digest differs');
 requireSafeZip(readFileSync(archive),product.appName);
 mkdirSync(workspace,{recursive:false,mode:0o700});await execute('/usr/bin/ditto',['-x','-k',archive,workspace],io);
 const app=join(workspace,product.appName);
 const walk=path=>{for(const item of readdirSync(path)){const file=join(path,item),stat=lstatSync(file);if(stat.isSymbolicLink())throw Error('iOS payload contains symlink');if(stat.isDirectory())walk(file);if(item==='embedded.mobileprovision'||item.endsWith('.ttf'))throw Error('Private profile or unlicensed font in public payload');}};walk(app);
 for(const target of product.targets){const info=join(app,target.path,'Info.plist');if(!existsSync(info)||await plist(info,'CFBundleIdentifier',io)!==product.bundle+target.suffix||await plist(info,'CFBundleVersion',io)!==manifest.build||await plist(info,'CFBundleShortVersionString',io)!==manifest.version)throw Error('Payload target identity differs');}
 return {manifest,app};
}
