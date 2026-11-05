#!/usr/bin/env node
import {mkdtempSync,mkdirSync,symlinkSync,writeFileSync,readdirSync,rmSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
const dir=mkdtempSync(join(tmpdir(),'unimagic-native-model-'));
try {
 const app=join(dir,'Checks.app'),contents=join(app,'Contents'),bin=join(contents,'MacOS');mkdirSync(bin,{recursive:true});
 const resources=join(contents,'Resources');mkdirSync(join(resources,'paired-mac/keeper'),{recursive:true});
 for(const name of ['node','bridge.cjs'])symlinkSync(resolve('macos/build/UniMagic.app/Contents/Resources',name),join(resources,name));
 writeFileSync(join(resources,'paired-mac/keeper/product-cli.mjs'),`import fs from 'node:fs';
const command=process.argv[2];fs.appendFileSync(process.env.UNIMAGIC_LIBRARY+'/calls.jsonl',JSON.stringify({command,manual:process.argv.includes('--manual'),forced:process.argv.includes('--force')})+'\\n');
console.log(JSON.stringify(command==='renew'?{kind:'healthy',expiresAt:Date.now()+604800000}:{kind:'off',message:'Synthetic phone consent is off.'}));`);
 writeFileSync(join(contents,'Info.plist'),'<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Checks</string><key>CFBundleIdentifier</key><string>com.clozach.unimagic.fixture</string></dict></plist>');
 const sources=['Bridge.swift','PickerModel.swift','ReleaseSettings.swift','PhoneUpdateService.swift','PasteDestination.swift','KeeperCommand.swift','tests/ModelChecks.swift'].map(p=>'macos/'+p);
 execFileSync('swiftc',['-O','-parse-as-library',...sources,...readdirSync('release-kit').filter(p=>p.endsWith('.swift')).map(p=>'release-kit/'+p),'-o',join(bin,'Checks'),'-framework','AppKit','-framework','SwiftUI','-framework','Security'],{stdio:'inherit'});
 const repetitions=Number(process.env.UNIMAGIC_NATIVE_REPEAT??1);if(!Number.isInteger(repetitions)||repetitions<1||repetitions>50)throw new Error('UNIMAGIC_NATIVE_REPEAT must be1–50');
 for(let iteration=0;iteration<repetitions;iteration++){
  console.log(`Native model check ${iteration+1}/${repetitions}`);
  execFileSync(join(bin,'Checks'),[],{env:{...process.env,UNIMAGIC_FIXTURE:'1',UNIMAGIC_LIBRARY:join(dir,'library-'+iteration)},stdio:'inherit',timeout:20000});
 }
} finally {rmSync(dir,{recursive:true,force:true});}
