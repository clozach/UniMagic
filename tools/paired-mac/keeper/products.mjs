import {join} from 'node:path';
import {ROOT,LOCK} from './state.mjs';

export const UNIMAGIC_PRODUCT=Object.freeze({
 id:'unimagic',name:'UniMagic',bundle:'com.clozach.unimagic',team:'AD29JN9GKN',
 identity:'8570B3D50CF453628EF2656136D36C7E47D47569',appName:'Unimagic.app',
 appGroup:'group.com.clozach.unimagic.visibility',
 targets:[{key:'keyboard',suffix:'.keyboard',path:'PlugIns/UnimagicKeyboard.appex'},{key:'controls',suffix:'.controls',path:'PlugIns/UnimagicControls.appex'},{key:'app',suffix:'',path:''}],
 home:join(ROOT,'unimagic-renewal'),lockPath:LOCK,
 consentFile:'Library/Application Support/paired-mac-updates-v1.json',
});

export function requireProduct(product){
 if(!product||!/^[-a-z0-9]+$/.test(product.id)||!/^[-a-zA-Z0-9]+$/.test(product.name)||!/^([a-zA-Z0-9-]+\.)+[a-zA-Z0-9-]+$/.test(product.bundle)||!/^\w{10}$/.test(product.team)||!/^group\.[a-zA-Z0-9.-]+$/.test(product.appGroup))throw Error('Unsupported product identity');
 if(!/^[A-F0-9]{40}$/.test(product.identity)||!product.home||!product.lockPath||!/^[a-zA-Z0-9-]+\.app$/.test(product.appName))throw Error('Product signing/storage configuration missing');
 if(!Array.isArray(product.targets)||!product.targets.some(t=>t.key==='app'&&t.suffix===''&&t.path==='')||product.targets.some(t=>t.key!=='app'&&(!/^\.[a-z]+$/.test(t.suffix)||!/^PlugIns\/[a-zA-Z0-9-]+\.appex$/.test(t.path))))throw Error('Explicit product signing targets missing');
 return product;
}
