import {mkdirSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {run} from './process.mjs';
import {requireProduct} from './products.mjs';

/** Official CLI profile bootstrap. Requires the caller's shared install lock.
 * Uses the existing Xcode account; no credentials, new enrollment or installs. */
export async function requestProductProfiles(product,workspace,io={}){
 requireProduct(product);mkdirSync(workspace,{recursive:true,mode:0o700});
 writeFileSync(join(workspace,'App.swift'),'import UIKit\n@main final class App: UIResponder, UIApplicationDelegate {}\n');
 writeFileSync(join(workspace,'Keyboard.swift'),'import UIKit\nfinal class Keyboard: UIInputViewController {}\n');
 writeFileSync(join(workspace,'Controls.swift'),'import WidgetKit\nimport SwiftUI\n@main struct Controls: WidgetBundle { var body: some Widget { Dummy() } }\nstruct Dummy: Widget {var body: some WidgetConfiguration {StaticConfiguration(kind:"bootstrap",provider:Provider()){_ in Text("UniMagic profile bootstrap")}.configurationDisplayName("Bootstrap").description("Profile bootstrap")} }\nstruct Entry: TimelineEntry {let date:Date}\nstruct Provider:TimelineProvider {func placeholder(in context:Context)->Entry{Entry(date:Date())};func getSnapshot(in context:Context,completion:@escaping(Entry)->Void){completion(Entry(date:Date()))};func getTimeline(in context:Context,completion:@escaping(Timeline<Entry>)->Void){completion(Timeline(entries:[Entry(date:Date())],policy:.never))}}\n');
 writeFileSync(join(workspace,'visibility.plist'),JSON.stringify({'com.apple.security.application-groups':[product.appGroup]}));
 await(io.run??run)('/usr/bin/plutil',['-convert','xml1',join(workspace,'visibility.plist')],io);
 const targets=product.targets.map(target=>{
  const keyboard=target.key==='keyboard',app=target.key==='app',name=app?'App':keyboard?'Keyboard':'Controls';
  return `  ${name}:\n    type: ${app?'application':'app-extension'}\n    platform: iOS\n    sources: [${name}.swift]\n    settings:\n      PRODUCT_BUNDLE_IDENTIFIER: ${product.bundle+target.suffix}\n${app||keyboard?'      CODE_SIGN_ENTITLEMENTS: visibility.plist\n':''}    info:\n      path: ${name}-Info.plist\n      properties:\n        CFBundleDisplayName: UniMagic Profile Bootstrap\n${app?'':`        NSExtension:\n          NSExtensionPointIdentifier: ${keyboard?'com.apple.keyboard-service':'com.apple.widgetkit-extension'}\n${keyboard?'          NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).Keyboard\n          NSExtensionAttributes:\n            RequestsOpenAccess: false\n            PrimaryLanguage: en-US\n':''}`}${app?'    dependencies:\n'+product.targets.filter(t=>t.key!=='app').map(t=>'      - target: '+(t.key==='keyboard'?'Keyboard':'Controls')+'\n        embed: true\n').join(''):''}`;
 }).join('');
 writeFileSync(join(workspace,'project.yml'),`name: ProductProfiles\nsettings:\n  base:\n    DEVELOPMENT_TEAM: ${product.team}\n    CODE_SIGN_STYLE: Automatic\n    IPHONEOS_DEPLOYMENT_TARGET: "18.0"\n    ENABLE_DEBUG_DYLIB: NO\ntargets:\n${targets}`);
 const execute=io.run??run;await execute('/opt/homebrew/bin/xcodegen',['generate','--spec','project.yml','--quiet'],{...io,cwd:workspace});
 return execute('/usr/bin/xcodebuild',['-project','ProductProfiles.xcodeproj','-scheme','App','-destination','generic/platform=iOS','-derivedDataPath',join(workspace,'DerivedData'),'-allowProvisioningUpdates','build'],{...io,cwd:workspace,timeout:240000});
}

/** Renewal temporarily evacuates only exact matching cached profiles, retaining
 * private copies and restoring originals even when account authentication fails.
 * The caller already holds the same global lock used by builds/installations. */
export async function refreshProductProfiles(product,workspace,io={}){
 const {readdirSync,copyFileSync,renameSync,existsSync}=await import('node:fs');
 const {homedir}=await import('node:os');const {profileInfo}=await import('./artifact.mjs');
 const cache=io.profileCache??join(homedir(),'Library/Developer/Xcode/UserData/Provisioning Profiles');
 const archive=join(workspace,'original-profiles');mkdirSync(archive,{recursive:true,mode:0o700});const saved=[];
 for(const name of readdirSync(cache).filter(x=>x.endsWith('.mobileprovision'))){
  const file=join(cache,name);let info;try{info=await(io.profileInfo??profileInfo)(file,archive,io);}catch{continue;}
  if(!product.targets.some(t=>info.app===product.team+'.'+product.bundle+t.suffix))continue;
  const backup=join(archive,name);copyFileSync(file,backup);saved.push({file,backup});
 }
 try{for(const {file,backup}of saved)renameSync(file,backup+'.held');return await requestProductProfiles(product,join(workspace,'request'),io);}
 finally{for(const {file,backup}of saved)if(!existsSync(file))copyFileSync(backup,file);}
}
