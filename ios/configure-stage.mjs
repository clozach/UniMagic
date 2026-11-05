#!/usr/bin/env node
// Explicit per-build App Group selection; signing must verify the same choice.
import {readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
const [stage,group]=process.argv.slice(2);
if(!stage||!/^group\.[a-zA-Z0-9.-]+$/.test(group??''))throw Error('Expected staged project and explicit App Group');
for(const file of ['project.yml','App/Unimagic.entitlements','Keyboard/UnimagicKeyboard.entitlements']){
 const path=join(stage,file);writeFileSync(path,readFileSync(path,'utf8').replaceAll('group.com.clozach.unimagic.visibility',group));
}
