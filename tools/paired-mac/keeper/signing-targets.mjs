import {existsSync,readdirSync} from 'node:fs';
import {join} from 'node:path';

// Frozen releases before build 10 have only the service. Never add an extension
// during renewal, drop a shipped extension, or silently leave a sibling unsigned.
export const SIGNING_TARGETS = [
 {key:'service',suffix:'.service',path:'PlugIns/AgentAlertsService.appex'},
 {key:'keyboard',suffix:'.keyboard',path:'PlugIns/UnimagicKeyboard.appex'},
 {key:'app',suffix:'',path:''},
];
export function signingTargets(app,{requireKeyboard=false}={}) {
 const plugins=join(app,'PlugIns'), names=existsSync(plugins)?readdirSync(plugins).filter(name=>name.endsWith('.appex')):[];
 if(names.some(name=>!SIGNING_TARGETS.some(target=>target.path==='PlugIns/'+name)))throw Error('Unsupported extension in frozen release; preserve its signing lane');
 if(!existsSync(join(app,SIGNING_TARGETS[0].path)))throw Error('Notification service extension missing');
 const targets=SIGNING_TARGETS.filter(target=>target.key!=='keyboard'||existsSync(join(app,target.path)));
 if(requireKeyboard&&!targets.some(target=>target.key==='keyboard'))throw Error('UniMagic keyboard extension missing from build 10 or later');
 return targets;
}
