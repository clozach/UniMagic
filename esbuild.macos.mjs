import esbuild from "esbuild";
import {readFileSync,mkdirSync} from "node:fs";
mkdirSync("macos/build",{recursive:true});
await esbuild.build({entryPoints:["src/hosts/macos/bridge.ts"],outfile:"macos/build/bridge.cjs",bundle:true,platform:"node",format:"cjs",target:"node22",minify:true,plugins:[{name:"corpus",setup(build){build.onResolve({filter:/^unimagic-corpus-text$/},()=>({path:"corpus",namespace:"corpus"}));build.onLoad({filter:/.*/,namespace:"corpus"},()=>({contents:readFileSync("unimagic-corpus.json","utf8"),loader:"text"}));}}]});
