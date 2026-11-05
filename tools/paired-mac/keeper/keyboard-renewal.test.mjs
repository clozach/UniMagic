import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,rmSync,existsSync} from 'node:fs';
import {join,basename} from 'node:path';
import {tmpdir} from 'node:os';
import {execFileSync} from 'node:child_process';
import {signingTargets} from './signing-targets.mjs';
import {preserveProfiles,provisioningProject,renewProfiles,provisionAndSign} from './provision.mjs';
import {BUNDLE,TEAM,treeHash} from './artifact.mjs';
import {UNIMAGIC_GROUP,inspectCapabilities} from './release-capabilities.mjs';
const folder=t=>{const path=mkdtempSync(join(tmpdir(),'pw-keyboard-'));t.after(()=>rmSync(path,{recursive:true,force:true}));return path;};
function appAt(root,keyboard=true){
 const app=join(root,'Source.app');mkdirSync(join(app,'PlugIns/AgentAlertsService.appex'),{recursive:true});writeFileSync(join(app,'corpus.sqlite'),'shared corpus');
 if(keyboard){mkdirSync(join(app,'PlugIns/UnimagicKeyboard.appex'));writeFileSync(join(app,'PlugIns/UnimagicKeyboard.appex/corpus.sqlite'),'shared corpus');}
 return app;
}
const infoFor=async file=>({app:TEAM+'.'+BUNDLE+({app:'',service:'.service',keyboard:'.keyboard',sibling:'.other'}[basename(file,'.mobileprovision')])});
function cacheAt(root){const path=join(root,'cache');mkdirSync(path);for(const key of ['app','service','keyboard','sibling'])writeFileSync(join(path,key+'.mobileprovision'),key);return path;}

test('frozen build 9 keeps two signing targets; build 10 requires its keyboard and refuses unknown siblings',t=>{
 const root=folder(t),app=appAt(root,false);assert.deepEqual(signingTargets(app).map(t=>t.key),['service','app']);
 assert.throws(()=>signingTargets(app,{requireKeyboard:true}),/keyboard extension missing/);
 mkdirSync(join(app,'PlugIns/UnimagicKeyboard.appex'));assert.deepEqual(signingTargets(app,{requireKeyboard:true}).map(t=>t.key),['service','keyboard','app']);
 mkdirSync(join(app,'PlugIns/Other.appex'));assert.throws(()=>signingTargets(app),/Unsupported extension/);
});
test('renewal profile request matches the actual frozen extension inventory without Full Access',t=>{
 const root=folder(t);provisioningProject(join(root,'old'));provisioningProject(join(root,'new'),{keyboard:true});
 assert.doesNotMatch(readFileSync(join(root,'old/project.yml'),'utf8'),/ProfileKeyboard|keyboard-service/);
 const spec=readFileSync(join(root,'new/project.yml'),'utf8');assert.match(spec,/- target: ProfileKeyboard\n        embed: true/);assert.match(spec,/com.clozach.amaanah.alerts.keyboard/);assert.match(spec,/RequestsOpenAccess: false/);
});
test('profile preservation includes the keyboard only for releases that shipped it',async t=>{
 const root=folder(t),cache=cacheAt(root),io={profileCache:cache,profileInfo:infoFor};
 const old=await preserveProfiles(join(root,'old'),io);old.evacuate();assert.ok(existsSync(join(cache,'keyboard.mobileprovision')));old.restore();
 const current=await preserveProfiles(join(root,'new'),{...io,keyboard:true});current.evacuate();
 assert.equal(existsSync(join(cache,'keyboard.mobileprovision')),false);assert.equal(readFileSync(join(cache,'sibling.mobileprovision'),'utf8'),'sibling');
 current.restore();for(const key of ['app','service','keyboard'])assert.equal(readFileSync(join(cache,key+'.mobileprovision'),'utf8'),key);
});
test('Apple authentication failure restores all three cached profiles without installing',async t=>{
 const root=folder(t),cache=cacheAt(root),calls=[];
 await assert.rejects(renewProfiles(join(root,'attempt'),{keyboard:true,profileCache:cache,profileInfo:infoFor,run:async(command)=>{calls.push(command);if(command.endsWith('xcodebuild'))throw Error('No Accounts');return {stdout:''};}}),/No Accounts/);
 for(const key of ['app','service','keyboard','sibling'])assert.equal(readFileSync(join(cache,key+'.mobileprovision'),'utf8'),key);
 assert.deepEqual(calls,['/opt/homebrew/bin/xcodegen','/usr/bin/xcodebuild']);
});
test('renewal rejects stale or missing keyboard profile expiry',async t=>{
 const root=folder(t),cache=join(root,'cache');mkdirSync(cache);const fresh=new Date(Date.now()+7*86400000).toISOString();
 const selected={app_expires:fresh,service_expires:fresh,keyboard_expires:new Date().toISOString()};
 const io={keyboard:true,profileCache:cache,run:async command=>({stdout:command.endsWith('select-profiles')?JSON.stringify(selected):''})};
 await assert.rejects(renewProfiles(join(root,'stale'),io),/all profiles/);
 delete selected.keyboard_expires;await assert.rejects(renewProfiles(join(root,'missing'),io),/all profiles/);
});
test('renewal signs both shipped extensions before the app, preserving frozen corpus and original release',async t=>{
 const root=folder(t),app=appAt(root),before=treeHash(app),cache=cacheAt(root),signed=[];let requested;
 const selected=Object.fromEntries(['app','service','keyboard'].map(key=>[key+'_path',join(cache,key+'.mobileprovision')]));
 const result=await provisionAndSign({app,build:'10'},join(root,'attempt'),{
  renewProfiles:async(_attempt,options)=>{requested=options.keyboard;return selected;},profileInfo:async()=>({xml:'fixture.plist'}),
  run:async(command,args)=>{if(command.endsWith('codesign'))signed.push(args.at(-1));return {stdout:TEAM+'.'+BUNDLE};},
  inspectApp:async path=>{assert.deepEqual(signingTargets(path).map(t=>t.key),['service','keyboard','app']);return {build:'10',expiresAt:123};},
 });
 assert.equal(requested,true);assert.deepEqual(signed.map(path=>basename(path)),['AgentAlertsService.appex','UnimagicKeyboard.appex','PowWorm.app']);
 assert.equal(readFileSync(join(result.app,'PlugIns/UnimagicKeyboard.appex/corpus.sqlite'),'utf8'),'shared corpus');
 assert.equal(readFileSync(join(result.app,'PlugIns/UnimagicKeyboard.appex/embedded.mobileprovision'),'utf8'),'keyboard');assert.equal(treeHash(app),before);
});
for(const sharing of [false,true])test(`real entitlement preparation ${sharing?'preserves':'does not add'} sharing from newer profiles`,{skip:process.platform!=='darwin'},async t=>{
 const root=folder(t),app=appAt(root),cache=cacheAt(root),signed=[];
 const capabilities=sharing?{kind:'unimagic-sharing',appGroup:UNIMAGIC_GROUP,keyboardFullAccess:true}:{kind:'isolated'};
 const selected=Object.fromEntries(['app','service','keyboard'].map(key=>[key+'_path',join(cache,key+'.mobileprovision')]));
 const info=Object.fromEntries(['app','service','keyboard'].map(key=>{
  const entitlements={'application-identifier':TEAM+'.'+BUNDLE+(key==='app'?'':'.'+key),'com.apple.security.application-groups':[UNIMAGIC_GROUP,'group.unrelated']};
  const xml=join(root,key+'.plist');writeFileSync(xml,JSON.stringify({Entitlements:entitlements}));
  return[key,{xml,entitlements}];
 }));
 await provisionAndSign({app,build:'12',capabilities},join(root,'attempt'),{
  renewProfiles:async(_attempt,options)=>{assert.deepEqual(options.capabilities,capabilities);return selected;},
  profileInfo:async file=>info[basename(file,'.mobileprovision')],
  run:async(command,args)=>{
   if(command.endsWith('codesign')){
    const bundle=basename(args.at(-1)),key=bundle==='PowWorm.app'?'app':bundle==='UnimagicKeyboard.appex'?'keyboard':'service';
    signed.push({key,entitlements:JSON.parse(execFileSync('/usr/bin/plutil',['-convert','json','-o','-',args[args.indexOf('--entitlements')+1]],{encoding:'utf8'})),fullAccess:key==='keyboard'?sharing:undefined});
    return{stdout:''};
   }
   return{stdout:execFileSync(command,args,{encoding:'utf8'})};
  },
  inspectApp:async()=>({build:'12',capabilities:inspectCapabilities(signed)}),
 });
 assert.deepEqual(inspectCapabilities(signed),capabilities);
 assert.equal(signed.find(target=>target.key==='service').entitlements['com.apple.security.application-groups'],undefined);
 for(const target of signed)assert.deepEqual(target.entitlements['keychain-access-groups'],[TEAM+'.'+BUNDLE+(target.key==='app'?'':'.'+target.key)]);
});
