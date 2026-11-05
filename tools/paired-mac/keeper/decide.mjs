// Fixed renewal policy. Healthy checks do not contact the phone or Apple.
export const HOUR=3600000,RENEW_WITHIN=48*HOUR,PROMPT_WITHIN=24*HOUR,RETRY_RENEW_AFTER=6*HOUR,UNREACHABLE_GRACE=30*60000;
export function plan(state,now,{force=false}={}){
 if(!state.release)return 'unconfigured';
 if(!force&&state.kind==='needs_auth')return 'authentication';
 if(!force&&state.kind==='needs_review')return 'review';
 if(!force&&!state.pending&&state.release.expiresAt>now+RENEW_WITHIN)return 'healthy';
 if(!force&&state.retryAt>now)return 'backoff';
 return 'probe';
}
export const phoneReady=(phone,force=false)=>phone.reachable&&(phone.locked||force);
export const needsConnectionNotice=(state,now,since)=>state.release.expiresAt<now+PROMPT_WITHIN&&now-since>UNREACHABLE_GRACE;
export function describeExpiry(expiresAt,now=Date.now()){
 if(!Number.isFinite(expiresAt))return 'unknown';
 return new Date(expiresAt).toLocaleString('en-US',{timeZone:'America/Los_Angeles',month:'short',day:'numeric',hour:'numeric',minute:'2-digit'})+(expiresAt<=now?' (expired)':' Pacific');
}
