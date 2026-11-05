import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {checkProductUpdates} from './product-feed.mjs';
import {UNIMAGIC_PRODUCT} from './products.mjs';
const uuid='00000000-0000-4000-8000-000000000001';
function fixture(on=false,request=null){
 const product={...UNIMAGIC_PRODUCT,home:mkdtempSync(join(tmpdir(),'um-feed-'))},effects=[],policy={schemaVersion:1,product:UNIMAGIC_PRODUCT.bundle,revision:uuid,automaticUpdates:on,manualCheckRequest:request};
 const io={lock:()=>({onChild(){},release(){effects.push('unlock');}}),readConsent:async()=>({kind:'read',policy}),githubRelease:async()=>{effects.push('feed');return{version:'1.0.0'};},installedApp:async()=>({bundleVersion:'1',version:'1.0.0'}),downloadRelease:async()=>{effects.push('download');return 'candidate';},payload:async()=>{effects.push('verify');return {manifest:{version:'1.0.0',build:'2'},app:'unsigned'};},sign:async()=>{effects.push('sign');return{app:'signed'};},capture:async()=>({app:'captured',build:'2'}),install:async(a,b,c,options)=>{await options.beforeInstall();effects.push('install');return{installedURL:'installed'};},writeStatus:async(a,b,status)=>effects.push(status.state)};
 return {product,io,effects,policy};
}
test('off and no fresh request makes zero GitHub/download/sign/install/status writes',async()=>{
 const f=fixture();assert.equal((await checkProductUpdates(f.product,{trustedMacApp:'trusted',io:f.io})).kind,'off');assert.deepEqual(f.effects,['unlock']);
});
test('fresh manual request discovers and verifies but cannot install while off; repeating it does no network',async()=>{
 const f=fixture(false,uuid);assert.equal((await checkProductUpdates(f.product,{trustedMacApp:'trusted',io:f.io})).kind,'available');assert.deepEqual(f.effects,['feed','download','verify','available','unlock']);f.effects.length=0;
 assert.equal((await checkProductUpdates(f.product,{trustedMacApp:'trusted',io:f.io})).kind,'off');assert.deepEqual(f.effects,['unlock']);
});
test('automatic on performs exact authenticated signing/install chain then reports status',async()=>{
 const f=fixture(true);assert.equal((await checkProductUpdates(f.product,{trustedMacApp:'trusted',io:f.io})).kind,'installed');assert.deepEqual(f.effects,['feed','download','verify','sign','install','installed','unlock']);
});
test('fresh off before install blocks feature mutation and writes error status',async()=>{
 const f=fixture(true);let reads=0;f.io.readConsent=async()=>({kind:'read',policy:{...f.policy,automaticUpdates:++reads<3}});
 assert.equal((await checkProductUpdates(f.product,{trustedMacApp:'trusted',io:f.io})).kind,'error');assert.ok(!f.effects.includes('install'));assert.ok(f.effects.includes('error'));
});
