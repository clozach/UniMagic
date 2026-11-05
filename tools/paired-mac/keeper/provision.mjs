import {mkdirSync,readdirSync,copyFileSync,writeFileSync,existsSync,cpSync,renameSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {homedir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {run} from './process.mjs';
import {BUNDLE,TEAM,IDENTITY,profileInfo,inspectApp,plist} from './artifact.mjs';
import {SIGNING_TARGETS,signingTargets} from './signing-targets.mjs';
import {releaseCapabilities,groupsForTarget,requireSameCapabilities,requireProfileGroups} from './release-capabilities.mjs';
const cache=join(homedir(),'Library/Developer/Xcode/UserData/Provisioning Profiles');
const requestedTargets=keyboard=>SIGNING_TARGETS.filter(target=>keyboard||target.key!=='keyboard');

/** Exact decoded identifiers only; originals remain in the attempt archive. */
export async function preserveProfiles(attempt,io={}){
 const archive=join(attempt,'original-profiles');mkdirSync(archive,{recursive:true});const saved=[];
 const identifiers=requestedTargets(io.keyboard).map(target=>TEAM+'.'+BUNDLE+target.suffix);
 for(const name of readdirSync(io.profileCache??cache).filter(x=>x.endsWith('.mobileprovision'))){
  const path=join(io.profileCache??cache,name);let info;try{info=await(io.profileInfo??profileInfo)(path,archive,io);}catch{continue;}
  if(!identifiers.includes(info.app))continue;
  copyFileSync(path,join(archive,name));saved.push({path,backup:join(archive,name)});
 }
 return {saved,evacuate:()=>{for(const item of saved)renameSync(item.path,item.backup+'.held');},restore:()=>{for(const item of saved)if(!existsSync(item.path))copyFileSync(item.backup,item.path);}};
}

/** A minimal local build requests only the shipped targets; never installed. */
export function provisioningProject(folder,{keyboard=false,capabilities}={}){
 const capability=releaseCapabilities(capabilities),sharing=capability.kind==='unimagic-sharing';
 if(sharing&&!keyboard)throw Error('Shared UniMagic release requires its keyboard');
 mkdirSync(folder,{recursive:true});
 writeFileSync(join(folder,'App.swift'),'import UIKit\n@main final class App: UIResponder, UIApplicationDelegate {}\n');
 writeFileSync(join(folder,'Service.swift'),'import UserNotifications\nfinal class Service: UNNotificationServiceExtension {}\n');
 if(keyboard)writeFileSync(join(folder,'Keyboard.swift'),'import UIKit\nfinal class Keyboard: UIInputViewController {}\n');
 writeFileSync(join(folder,'free.plist'),'<?xml version="1.0"?><plist version="1.0"><dict/></plist>');
 if(sharing)writeFileSync(join(folder,'sharing.plist'),`<?xml version="1.0"?><plist version="1.0"><dict><key>com.apple.security.application-groups</key><array><string>${capability.appGroup}</string></array></dict></plist>`);
 const keyboardTarget=keyboard?`
  ProfileKeyboard:
    type: app-extension
    platform: iOS
    sources: [Keyboard.swift]
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: ${BUNDLE}.keyboard
      APPLICATION_EXTENSION_API_ONLY: YES
      CODE_SIGN_ENTITLEMENTS: ${sharing?'sharing':'free'}.plist
    info:
      path: KeyboardInfo.plist
      properties:
        NSExtension:
          NSExtensionPointIdentifier: com.apple.keyboard-service
          NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).Keyboard
          NSExtensionAttributes:
            IsASCIICapable: false
            PrimaryLanguage: en-US
            RequestsOpenAccess: ${sharing&&capability.keyboardFullAccess}
`:'';
 writeFileSync(join(folder,'project.yml'),`name: ProfileRenewal
settings:
  base:
    DEVELOPMENT_TEAM: ${TEAM}
    CODE_SIGN_STYLE: Automatic
    REGISTER_APP_GROUPS: ${sharing?'YES':'NO'}
    CODE_SIGN_ENTITLEMENTS: free.plist
    ENABLE_DEBUG_DYLIB: NO
    IPHONEOS_DEPLOYMENT_TARGET: "27.0"
targets:
  ProfileApp:
    type: application
    platform: iOS
    sources: [App.swift]
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: ${BUNDLE}
      CODE_SIGN_ENTITLEMENTS: ${sharing?'sharing':'free'}.plist
    info:
      path: AppInfo.plist
      properties:
        CFBundleDisplayName: PowWorm Profile Request
    dependencies:
      - target: ProfileService
        embed: true
${keyboard?'      - target: ProfileKeyboard\n        embed: true\n':''}  ProfileService:
    type: app-extension
    platform: iOS
    sources: [Service.swift]
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: ${BUNDLE}.service
    info:
      path: ServiceInfo.plist
      properties:
        NSExtension:
          NSExtensionPointIdentifier: com.apple.usernotifications.service
          NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).Service
${keyboardTarget}`);
}

/** Caller owns the maintenance lock. An auth failure restores cached originals. */
export async function renewProfiles(attempt,{keyboard=false,capabilities,...io}={}){
 const capability=releaseCapabilities(capabilities);
 const execute=io.run??run,project=join(attempt,'profile-project');provisioningProject(project,{keyboard,capabilities:capability});
 const originals=await preserveProfiles(attempt,{...io,keyboard});
 try{
  originals.evacuate();
  await execute('/opt/homebrew/bin/xcodegen',['generate','--spec','project.yml','--quiet'],{...io,cwd:project});
  await execute('/usr/bin/xcodebuild',['-project','ProfileRenewal.xcodeproj','-scheme','ProfileApp','-configuration','Debug','-destination','generic/platform=iOS','-derivedDataPath',join(attempt,'DerivedData'),'-allowProvisioningUpdates','build'],{...io,cwd:project,timeout:240000});
 }finally{originals.restore();rmSync(join(attempt,'DerivedData'),{recursive:true,force:true});}
 const signing=fileURLToPath(new URL('../signing/',import.meta.url)),selector=join(attempt,'select-profiles');
 await execute('/usr/bin/swiftc',[join(signing,'SigningProfiles.swift'),join(signing,'main.swift'),'-o',selector],io);
 const selected=JSON.parse((await execute(selector,[io.profileCache??cache,...(keyboard?['--keyboard']:[]),...(capability.kind==='unimagic-sharing'?['--app-group',capability.appGroup]:[])],io)).stdout);
 const expiries=requestedTargets(keyboard).map(target=>Date.parse(selected[target.key+'_expires']));
 if(expiries.some(expiry=>!Number.isFinite(expiry)||expiry<Date.now()+6*86400000))throw Error('Apple did not issue all profiles with six days remaining');
 return selected;
}

export async function provisionAndSign(release,attempt,io={}){
 const execute=io.run??run,targets=signingTargets(release.app,{requireKeyboard:Number(release.build)>=10}),capabilities=releaseCapabilities(release.capabilities);
 const selected=await(io.renewProfiles??renewProfiles)(attempt,{...io,keyboard:targets.some(target=>target.key==='keyboard'),capabilities});
 const app=join(attempt,'PowWorm.app');cpSync(release.app,app,{recursive:true});
 for(const target of targets){
  const bundle=join(app,target.path),profile=selected[target.key+'_path'];copyFileSync(profile,join(bundle,'embedded.mobileprovision'));
  const info=await(io.profileInfo??profileInfo)(profile,attempt,io),entitlements=join(attempt,target.key+'-entitlements.plist');
  const groups=groupsForTarget(capabilities,target.key);requireProfileGroups(info.entitlements,groups);
  await execute('/usr/bin/plutil',['-extract','Entitlements','xml1','-o',entitlements,info.xml],io);
  const appID=await plist(entitlements,'application-identifier',io);
  await execute('/usr/bin/plutil',['-replace','keychain-access-groups','-json',JSON.stringify([appID]),entitlements],io);
  if(groups.length)await execute('/usr/bin/plutil',['-replace','com\\.apple\\.security\\.application-groups','-json',JSON.stringify(groups),entitlements],io);
  else if(info.entitlements?.['com.apple.security.application-groups'])await execute('/usr/bin/plutil',['-remove','com\\.apple\\.security\\.application-groups',entitlements],io);
  await execute('/usr/bin/codesign',['--force','--sign',IDENTITY,'--entitlements',entitlements,bundle],io);
 }
 const info=await(io.inspectApp??inspectApp)(app,attempt,io);requireSameCapabilities(capabilities,info.capabilities);return {app,...info};
}
