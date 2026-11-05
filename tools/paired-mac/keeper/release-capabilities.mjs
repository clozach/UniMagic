// Supported signing capabilities are part of a frozen release, not a global
// upgrade switch. Renewing an older release must never add shared containers.
export const UNIMAGIC_GROUP = 'group.com.clozach.amaanah.unimagic';
export const ISOLATED_CAPABILITIES = Object.freeze({kind:'isolated'});

export function releaseCapabilities(value=ISOLATED_CAPABILITIES,appGroup=UNIMAGIC_GROUP) {
 if(value?.kind==='isolated'&&Object.keys(value).length===1)return ISOLATED_CAPABILITIES;
 if(value?.kind==='unimagic-sharing'&&value.appGroup===appGroup&&typeof value.keyboardFullAccess==='boolean'&&Object.keys(value).length===3)return value;
 throw Error('Unsupported release capabilities; preserve its signing lane');
}

export function groupsForTarget(capabilities,key,appGroup=UNIMAGIC_GROUP) {
 const value=releaseCapabilities(capabilities,appGroup);
 return value.kind==='unimagic-sharing'&&['app','keyboard'].includes(key)?[value.appGroup]:[];
}

/** Inputs come from actual signed entitlements, never from project settings. */
export function inspectCapabilities(targets,appGroup=UNIMAGIC_GROUP) {
 const groups=new Map();let keyboardFullAccess=false;
 for(const {key,entitlements,fullAccess} of targets){
  if(!entitlements||typeof entitlements!=='object'||Array.isArray(entitlements))throw Error('Invalid signed entitlements');
  if(Object.hasOwn(entitlements,'aps-environment'))throw Error('APNs requires a different signing lane; preserve it');
  const values=entitlements['com.apple.security.application-groups']??[];
  if(!Array.isArray(values)||values.length>1||values.some(group=>group!==appGroup))throw Error('Unsupported App Group; preserve its signing lane');
  if(key==='service'&&values.length)throw Error('Notification service must not join the UniMagic App Group');
  groups.set(key,values);
  if(key==='keyboard'){
   if(typeof fullAccess!=='boolean')throw Error('Invalid keyboard Full Access declaration');
   keyboardFullAccess=fullAccess;
  }
 }
 const app=groups.get('app')??[],keyboard=groups.get('keyboard')??[];
 if(JSON.stringify(app)!==JSON.stringify(keyboard))throw Error('App and keyboard App Groups differ');
 if(!app.length){
  if(keyboardFullAccess)throw Error('Full Access requires the verified UniMagic sharing lane');
  return ISOLATED_CAPABILITIES;
 }
 return {kind:'unimagic-sharing',appGroup,keyboardFullAccess};
}

export function requireSameCapabilities(expected,actual,appGroup=UNIMAGIC_GROUP) {
 const a=releaseCapabilities(expected,appGroup),b=releaseCapabilities(actual,appGroup);
 if(a.kind!==b.kind||a.appGroup!==b.appGroup||a.keyboardFullAccess!==b.keyboardFullAccess)throw Error('Renewal changed frozen release capabilities');
}

export function requireProfileGroups(entitlements,groups) {
 const granted=entitlements?.['com.apple.security.application-groups']??[];
 if(!Array.isArray(granted)||groups.some(group=>!granted.includes(group)))throw Error('Provisioning profile does not grant the frozen App Group');
 if(entitlements&&Object.hasOwn(entitlements,'aps-environment'))throw Error('APNs profile requires a different signing lane');
}
