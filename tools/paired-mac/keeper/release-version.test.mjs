import test from 'node:test';
import assert from 'node:assert/strict';
import {compareRelease} from './release-version.mjs';
test('stable semantic version precedes build; new patch with reset build upgrades, older version with larger build cannot downgrade',()=>{
 assert.equal(compareRelease({version:'1.0.1',build:'1'},{version:'1.0.0',bundleVersion:'999'}),1);
 assert.equal(compareRelease({version:'1.0.0',build:'999'},{version:'1.0.1',bundleVersion:'1'}),-1);
 assert.equal(compareRelease({version:'1.0.0',build:'2'},{version:'1.0.0',bundleVersion:'1'}),1);
 for(const version of ['1.0','01.0.0','1.0.0-beta','1.0.0+meta'])assert.throws(()=>compareRelease({version,build:'1'},{version:'1.0.0',build:'1'}));
});
