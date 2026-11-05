import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,rmSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {execFileSync} from 'node:child_process';
import {UNIMAGIC_GROUP,inspectCapabilities,requireSameCapabilities,requireProfileGroups,groupsForTarget} from './release-capabilities.mjs';
import {provisioningProject} from './provision.mjs';

const isolated={kind:'isolated'};
const shared={kind:'unimagic-sharing',appGroup:UNIMAGIC_GROUP,keyboardFullAccess:true};
const entitlements=groups=>({'com.apple.security.application-groups':groups});
const signed=(groups=[],fullAccess=false)=>[
 {key:'service',entitlements:{}},
 {key:'keyboard',entitlements:entitlements(groups),fullAccess},
 {key:'app',entitlements:entitlements(groups)},
];
const folder=t=>{const path=mkdtempSync(join(tmpdir(),'pw-capabilities-'));t.after(()=>rmSync(path,{recursive:true,force:true}));return path;};

test('actual signatures distinguish isolated, read-only sharing and optional Full Access releases',()=>{
 assert.deepEqual(inspectCapabilities(signed()),isolated);
 assert.deepEqual(inspectCapabilities(signed([UNIMAGIC_GROUP],true)),shared);
 assert.deepEqual(inspectCapabilities(signed([UNIMAGIC_GROUP],false)),{...shared,keyboardFullAccess:false});
 assert.deepEqual(groupsForTarget(shared,'service'),[]);
 assert.deepEqual(groupsForTarget(shared,'keyboard'),[UNIMAGIC_GROUP]);
});
test('mismatched groups, unknown groups, service sharing and APNs on any target are refused',()=>{
 const mismatched=signed([UNIMAGIC_GROUP]);mismatched[1].entitlements={};
 assert.throws(()=>inspectCapabilities(mismatched),/differ/);
 assert.throws(()=>inspectCapabilities(signed(['group.somewhere.else'])),/Unsupported App Group/);
 const service=signed();service[0].entitlements=entitlements([UNIMAGIC_GROUP]);
 assert.throws(()=>inspectCapabilities(service),/service must not/);
 for(const target of [0,1,2]){const values=signed();values[target].entitlements['aps-environment']='development';assert.throws(()=>inspectCapabilities(values),/APNs/);}
 assert.throws(()=>inspectCapabilities(signed([],true)),/Full Access requires/);
});
test('renewal never upgrades, drops or changes frozen sharing and access requirements',()=>{
 requireSameCapabilities(undefined,isolated);requireSameCapabilities(shared,{...shared});
 assert.throws(()=>requireSameCapabilities(undefined,shared),/changed frozen/);
 assert.throws(()=>requireSameCapabilities(shared,isolated),/changed frozen/);
 assert.throws(()=>requireSameCapabilities(shared,{...shared,keyboardFullAccess:false}),/changed frozen/);
 assert.throws(()=>groupsForTarget({kind:'isolated',appGroup:UNIMAGIC_GROUP},'app'),/Unsupported/);
});
test('profiles must grant required groups; unrelated profile groups are not requested for signing',()=>{
 requireProfileGroups(entitlements([UNIMAGIC_GROUP,'group.other']),[UNIMAGIC_GROUP]);
 assert.throws(()=>requireProfileGroups({},[UNIMAGIC_GROUP]),/does not grant/);
 assert.throws(()=>requireProfileGroups({'aps-environment':'development'},[]),/APNs/);
 assert.deepEqual(groupsForTarget(isolated,'app'),[]);
});
test('renewal prototype requests shared entitlements only for app and keyboard',t=>{
 const root=folder(t);provisioningProject(root,{keyboard:true,capabilities:shared});
 const spec=readFileSync(join(root,'project.yml'),'utf8');
 assert.equal(spec.match(/CODE_SIGN_ENTITLEMENTS: sharing.plist/g)?.length,2);
 assert.match(spec,/RequestsOpenAccess: true/);
 assert.match(readFileSync(join(root,'sharing.plist'),'utf8'),/group.com.clozach.amaanah.unimagic/);
 assert.throws(()=>provisioningProject(join(root,'missing-keyboard'),{capabilities:shared}),/requires its keyboard/);
});
test('macOS plist mutation preserves a literal dotted App Group entitlement key', {skip:process.platform!=='darwin'},t=>{
 const file=join(folder(t),'entitlements.plist');writeFileSync(file,'<?xml version="1.0"?><plist version="1.0"><dict/></plist>');
 const key='com\\.apple\\.security\\.application-groups';
 execFileSync('/usr/bin/plutil',['-replace',key,'-json',JSON.stringify([UNIMAGIC_GROUP]),file]);
 const parsed=JSON.parse(execFileSync('/usr/bin/plutil',['-convert','json','-o','-',file],{encoding:'utf8'}));
 assert.deepEqual(parsed,entitlements([UNIMAGIC_GROUP]));
 assert.equal(execFileSync('/usr/bin/plutil',['-extract',key+'.0','raw',file],{encoding:'utf8'}).trim(),UNIMAGIC_GROUP);
});
