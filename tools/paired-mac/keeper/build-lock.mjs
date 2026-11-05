import {takeLock} from './state.mjs';
import {run} from './process.mjs';
const lock=takeLock();
if(!lock){console.error('PowWorm signing maintenance is active; retry the device build later.');process.exitCode=75;}
else{
 const controller=new AbortController(),stop=()=>controller.abort();process.once('SIGTERM',stop);process.once('SIGINT',stop);
 try{process.env.POWWORM_SIGNING_LOCK_HELD='1';const result=await run('/bin/bash',process.argv.slice(2),{signal:controller.signal,timeout:15*60000,onChild:lock.onChild});process.stdout.write(result.stdout);process.stderr.write(result.stderr);}
 catch(error){console.error(error.message);process.exitCode=1;}
 finally{process.removeListener('SIGTERM',stop);process.removeListener('SIGINT',stop);lock.release();}
}
