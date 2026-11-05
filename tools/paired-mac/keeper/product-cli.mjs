#!/usr/bin/env node
import {readFileSync,mkdirSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {UNIMAGIC_PRODUCT,requireProduct} from './products.mjs';
import {readMaintenance} from './state.mjs';
import {withProductLock,installProduct,deliverPublishedProduct,renewProduct} from './product-delivery.mjs';
import {signProduct} from './product-signing.mjs';
import {checkProductUpdates} from './product-feed.mjs';
import {requestProductProfiles} from './product-provision.mjs';
import {readUpdateConsent} from './update-consent.mjs';
import {inspectMigration,exportMigration,importMigration,readMigration} from './migration.mjs';
const [command,...args]=process.argv.slice(2),flags=new Map();
for(let i=0;i<args.length;i++){const key=args[i];if(!key.startsWith('--'))throw Error('Expected named option');flags.set(key,args[i+1]&&!args[i+1].startsWith('--')?args[++i]:true);}
const get=key=>{const value=flags.get('--'+key);if(typeof value!=='string')throw Error('Missing --'+key);return value;};
const product=requireProduct(flags.has('--config')?JSON.parse(readFileSync(get('config'),'utf8')):UNIMAGIC_PRODUCT);
const io=flags.has('--phone')?{phone:get('phone')}:{};
try{
 let result;
 if(command==='check-updates')result=await checkProductUpdates(product,{trustedMacApp:get('trusted-app'),manual:flags.has('--manual'),io});
 else if(command==='status')result=readMaintenance(product.home);
 else if(command==='provision-profiles')result=await withProductLock(product,(attempt,commandIO)=>requestProductProfiles(product,join(attempt,'profile-bootstrap'),commandIO),io);
 else if(command==='sign')result=await withProductLock(product,(attempt,commandIO)=>signProduct(product,get('app'),join(attempt,'signed'),commandIO),io);
 else if(command==='install')result=await installProduct(product,get('app'),{bootstrap:flags.has('--bootstrap'),operator:flags.has('--operator'),io});
 else if(command==='deliver')result=await deliverPublishedProduct(product,{trustedMacApp:get('trusted-mac'),candidateMacApp:get('candidate-mac'),...(flags.has('--mac-bundle')?{macBundle:get('mac-bundle')}:{})},io);
 else if(command==='renew')result=await renewProduct(product,{force:flags.has('--force'),io});
 else if(command==='check')result=await withProductLock(product,(attempt,commandIO)=>readUpdateConsent(product,join(attempt,'check'),commandIO),io);
 else if(command==='migration-inspect')result=await inspectMigration(resolve(get('out')),{side:flags.has('--destination')?'destination':'source',io});
 else if(command==='migration-export')result=await exportMigration(resolve(get('out')),{io});
 else if(command==='migration-verify')result=readMigration(resolve(get('snapshot')));
 else if(command==='migration-import')result=await importMigration(resolve(get('snapshot')),{workspace:resolve(get('out')),expected:flags.has('--expected')?JSON.parse(readFileSync(get('expected'),'utf8')):undefined,io});
 else throw Error('Use status | provision-profiles | sign --app <app> | install --app <signed> --bootstrap|--operator | deliver --trusted-mac <installed> --candidate-mac <candidate> | renew [--force] | check | migration-inspect --out <new> [--destination] | migration-export --out <new> | migration-verify --snapshot <export> | migration-import --snapshot <export> --out <new> [--expected <destination-manifest>]');
 console.log(JSON.stringify(result,null,2));
}catch(error){console.error(JSON.stringify({error:error.message}));process.exitCode=1;}
