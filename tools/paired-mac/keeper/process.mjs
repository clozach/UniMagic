import {spawn} from 'node:child_process';
const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const groupAlive=pid=>{try{process.kill(-pid,0);return true;}catch(error){return error.code==='EPERM';}};
/** Own process group only. Cancellation drains children before releasing ownership. */
export function run(command,args,{cwd,signal,timeout=120000,onChild=()=>{}}={}){
 return new Promise((resolve,reject)=>{
  signal?.throwIfAborted();
  const child=spawn(command,args,{cwd,detached:true,stdio:['ignore','pipe','pipe'],env:{...process.env,CI:'1'}});
  let stdout='',stderr='',stopped=false,killTimer;
  const kill=sig=>{try{process.kill(-child.pid,sig);}catch{}};
  const stop=()=>{if(stopped)return;stopped=true;kill('SIGTERM');killTimer=setTimeout(()=>kill('SIGKILL'),5000);};
  const timer=setTimeout(stop,timeout);signal?.addEventListener('abort',stop,{once:true});
  child.once('spawn',()=>onChild(child.pid));
  child.stdout.on('data',x=>{stdout=(stdout+x).slice(-2*1024*1024);});child.stderr.on('data',x=>{stderr=(stderr+x).slice(-2*1024*1024);});
  const cleanup=safe=>{clearTimeout(timer);clearTimeout(killTimer);signal?.removeEventListener('abort',stop);if(safe)onChild(null);};
  child.once('error',error=>{cleanup(true);reject(error);});
  child.once('close',async code=>{
   if(groupAlive(child.pid)){
    kill('SIGTERM');const grace=Date.now()+5000;while(groupAlive(child.pid)&&Date.now()<grace)await pause(50);
    if(groupAlive(child.pid)){kill('SIGKILL');const final=Date.now()+2000;while(groupAlive(child.pid)&&Date.now()<final)await pause(50);}
   }
   const safe=!groupAlive(child.pid);cleanup(safe);
   if(code===0&&!stopped&&safe)resolve({stdout,stderr});
   else reject(Object.assign(Error(!safe?'Owned child did not drain; maintenance lock retained':stopped?'maintenance command cancelled or timed out':`${command} failed: ${(stderr+'\n'+stdout).split('\n').filter(x=>/error:|No Accounts|sign.in|authentication|provision|certificate|locked|unreachable|failed/i.test(x)).slice(-3).join(' ').slice(0,1000)}`),{stdout,stderr,code,cancelled:stopped}));
  });
 });
}
