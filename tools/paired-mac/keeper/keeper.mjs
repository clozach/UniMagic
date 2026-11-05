#!/usr/bin/env node
// Compatibility entry point. The vault scheduler is the only automatic clock.
import {fileURLToPath} from 'node:url';
import {maintain,adoptInstalled,installRelease} from './maintenance.mjs';
import {readMaintenance,legacyState,inProgress,saveMaintenance} from './state.mjs';
import {device,probePhone} from './device.mjs';
import {BUNDLE} from './artifact.mjs';
export const readState=()=>legacyState();
export const renewInProgress=()=>inProgress();
export const renew=options=>maintain(options);
export const tick=options=>maintain(options);
export async function status(){const maintenance=readMaintenance();return {state:readState(),maintenance,next:maintenance.release?new Date(maintenance.release.expiresAt-48*3600000).toISOString():null};}
export async function relaunch({explicit=false}={}){if(!explicit)return {kind:'manual-required'};return device(['process','launch','--no-activate',BUNDLE]);}
if(process.argv[1]===fileURLToPath(import.meta.url)){
 try{
  const [command,...args]=process.argv.slice(2);let result;
  if(command==='status')result=await status();
  else if(command==='adopt'&&args[0]==='--app'&&args.length===2)result=await adoptInstalled(args[1]);
  else if(command==='install'&&args[0]==='--app'&&args.length===2)result=await installRelease(args[1]);
  else if(command==='renew')result=await maintain({force:args.includes('--force')});
  else if(command==='tick')result=await maintain();
  else if(command==='resume-auth'){const state=readMaintenance();if(state.kind!=='needs_auth')throw Error('No authentication hold');saveMaintenance({...state,kind:'healthy',retryAt:0,error:null});result={resumed:true};}
  else if(command==='relaunch')result=await relaunch({explicit:true});
  else throw Error('Use status | adopt/install --app <app> | renew [--force] | tick | resume-auth | relaunch');
  console.log(JSON.stringify(result,null,2));
 }catch(error){console.error(JSON.stringify({error:error.message}));process.exitCode=1;}
}
export {probePhone};
