import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,existsSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {authenticatedPayload} from './authenticated-payload.mjs';
import {UNIMAGIC_PRODUCT} from './products.mjs';
function fixture(){
 const root=mkdtempSync(join(tmpdir(),'um-auth-')),trusted=join(root,'installed.app'),candidate=join(root,'candidate.app'),resources=join(candidate,'Contents/Resources/iOS'),source=join(root,'Unimagic.app');
 for(const app of [trusted,candidate]){mkdirSync(join(app,'Contents'),{recursive:true});writeFileSync(join(app,'Contents/Info.plist'),JSON.stringify({CFBundleIdentifier:'com.clozach.unimagic.mac',CFBundleShortVersionString:'1.0.0'}));}
 for(const target of UNIMAGIC_PRODUCT.targets){mkdirSync(join(source,target.path),{recursive:true});writeFileSync(join(source,target.path,'Info.plist'),JSON.stringify({CFBundleIdentifier:UNIMAGIC_PRODUCT.bundle+target.suffix,CFBundleVersion:'1',CFBundleShortVersionString:'1.0.0'}));}
 mkdirSync(resources,{recursive:true});const archive=join(resources,'UniMagic-iOS.unsigned.zip');assert.equal(spawnSync('/usr/bin/ditto',['-c','-k','--norsrc','--keepParent',source,archive]).status,0);
 const manifest={schemaVersion:1,product:UNIMAGIC_PRODUCT.bundle,archive:'UniMagic-iOS.unsigned.zip',app:'Unimagic.app',version:'1.0.0',build:'1',sha256:createHash('sha256').update(readFileSync(archive)).digest('hex')};writeFileSync(join(resources,'manifest.json'),JSON.stringify(manifest));
 const calls=[],requirement='identifier "com.clozach.unimagic.mac" and anchor apple generic and certificate leaf[subject.OU] = "TESTTEAM00"';
 const io={run:async(command,args)=>{calls.push([command,args]);if(command.endsWith('codesign'))return {stdout:'',stderr:args.includes('-r-')?'designated => '+requirement:''};if(command.endsWith('plutil'))return{stdout:JSON.parse(readFileSync(args.at(-1),'utf8'))[args[1]],stderr:''};const result=spawnSync(command,args,{encoding:'utf8'});if(result.status)throw Error(result.stderr);return result;}};
 return {root,trusted,candidate,resources,manifest,calls,requirement,io};
}
test('authenticated intake pins independent installed signer, exact bundle/version/digest and every iOS target',async()=>{
 const f=fixture(),workspace=join(f.root,'extracted');const result=await authenticatedPayload(UNIMAGIC_PRODUCT,{trustedMacApp:f.trusted,candidateMacApp:f.candidate,workspace},f.io);
 assert.ok(existsSync(result.app));assert.ok(f.calls.some(([command,args])=>command.endsWith('codesign')&&args.includes('-R='+f.requirement)&&args.at(-1)===f.candidate));
});
test('intake rejects a self-trust candidate, ad-hoc trust anchor and modified sealed bytes',async()=>{
 const f=fixture();await assert.rejects(authenticatedPayload(UNIMAGIC_PRODUCT,{trustedMacApp:f.candidate,candidateMacApp:f.candidate,workspace:join(f.root,'self')},f.io),/independent/);
 await assert.rejects(authenticatedPayload(UNIMAGIC_PRODUCT,{trustedMacApp:f.trusted,candidateMacApp:f.candidate,workspace:join(f.root,'adhoc')},{run:async()=>({stdout:'',stderr:'designated => identifier "ad-hoc"'})}),/certificate-backed/);
 writeFileSync(join(f.resources,f.manifest.archive),'tampered');await assert.rejects(authenticatedPayload(UNIMAGIC_PRODUCT,{trustedMacApp:f.trusted,candidateMacApp:f.candidate,workspace:join(f.root,'tampered')},f.io),/digest/);assert.ok(!existsSync(join(f.root,'tampered')));
});
