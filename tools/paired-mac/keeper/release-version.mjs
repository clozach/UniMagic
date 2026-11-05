/** Strict stable semantic versions plus the integer Apple build counter. */
export function releaseTuple(version,build){
 if(typeof version!=='string'||!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(version)||!/^\d+$/.test(String(build)))throw Error('Invalid stable release version/build');
 const tuple=[...version.split('.').map(BigInt),BigInt(build)];return tuple;
}
export function compareRelease(a,b){
 const left=releaseTuple(a.version,a.build??a.bundleVersion),right=releaseTuple(b.version,b.build??b.bundleVersion);
 for(let i=0;i<left.length;i++){if(left[i]>right[i])return 1;if(left[i]<right[i])return -1;}return 0;
}
