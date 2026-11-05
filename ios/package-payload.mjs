#!/usr/bin/env node
// Produce unsigned public iOS resources. The outer Mac app seals these bytes.
import {spawnSync} from 'node:child_process';
import {mkdirSync,cpSync,readdirSync,rmSync,readFileSync,writeFileSync,lstatSync} from 'node:fs';
import {join,resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
const source=dirname(fileURLToPath(import.meta.url)),output=resolve(process.argv[2]??'/tmp/unimagic-public-ios');
const buildRoot=resolve(process.env.UNIMAGIC_BUILD_ROOT??'/tmp/unimagic-unsigned-device');
function run(command,args,options={}){const result=spawnSync(command,args,{encoding:'utf8',...options});if(result.status!==0)throw Error(result.stderr||result.stdout||command+' failed');return (result.stdout??'').trim();}
run('/bin/bash',[join(source,'build.sh'),'unsigned-device'],{env:{...process.env,UNIMAGIC_BUILD_ROOT:buildRoot},stdio:'inherit'});
mkdirSync(output,{recursive:true});const stage=join(buildRoot,'public-payload'),app=join(stage,'Unimagic.app');mkdirSync(stage,{recursive:true});
cpSync(join(buildRoot,'DerivedData/Build/Products/Debug-iphoneos/Unimagic.app'),app,{recursive:true});
function sanitize(folder){for(const name of readdirSync(folder)){const file=join(folder,name);if(lstatSync(file).isSymbolicLink())throw Error('Unexpected public payload symlink');if(name==='_CodeSignature'||name==='embedded.mobileprovision'||name==='RecentsSeed.json'||name.endsWith('.ttf'))rmSync(file,{recursive:true,force:true});else if(lstatSync(file).isDirectory())sanitize(file);}}
sanitize(app);
const plist=key=>run('/usr/bin/plutil',['-extract',key,'raw',join(app,'Info.plist')]);
const archive='UniMagic-iOS.unsigned.zip',archivePath=join(output,archive);rmSync(archivePath,{force:true});
run('/usr/bin/ditto',['-c','-k','--norsrc','--keepParent',app,archivePath]);
const manifest={schemaVersion:1,product:plist('CFBundleIdentifier'),archive,app:'Unimagic.app',version:plist('CFBundleShortVersionString'),build:plist('CFBundleVersion'),sha256:createHash('sha256').update(readFileSync(archivePath)).digest('hex')};
writeFileSync(join(output,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');console.log(JSON.stringify({output,manifest},null,2));
