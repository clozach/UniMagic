/** Persistent JSON-lines adapter: the native host uses the exact desktop engine. */
import artwork from "../../../ios/Resources/CategoryArtwork.json";
import { createInterface } from "node:readline";
import * as fs from "node:fs";
import * as path from "node:path";
import { loadIndex } from "../tinycast/corpus";
import { tileText } from "../tinycast/browse";
import { readShared, mutateShared } from "../tinycast/shared-store";
import { ensureMacLibrary } from "../tinycast/shared-mac-store";
import { DesktopBrowse, historyRecord, viewKey, type DesktopRecord, categoryDisplayTitle, historyDescription } from "../shared/desktop-browse";
import { personalizationFileProvider } from "../shared/personalization-file";
import { emptyData, search, frequentlyUsed, recordUsage, upVote, teach, unlearn, aliasesFor } from "../../core";
import { recordFor, skinVariants, ESCAPE_LABELS, componentName } from "../../core/glyphs";
import { escapes, hexList, codePoints, utf8Bytes, utf16Units } from "../../core/encodings";

async function boot() {
const fixture = process.env.UNIMAGIC_LIBRARY;
if (fixture) fs.mkdirSync(fixture, {recursive:true});
const file = fixture ? path.join(fixture, "data.json") : ensureMacLibrary(process.env.UNIMAGIC_LEGACY_DATA);
const index = loadIndex();
const browse = new DesktopBrowse(index, personalizationFileProvider(path.join(path.dirname(file), "personalization-v1.json"), "shared-read-write"));
const records = new Map<string, DesktopRecord>();
const data = () => { const state = readShared(file); if (state.kind !== "ready") throw new Error(state.kind === "unreadable" ? state.reason : "Library missing"); return state.data; };
const pack = (r: DesktopRecord) => { records.set(viewKey(r), r); return {id:viewKey(r), hexseq:r.hexseq, symbol:r.symbol, display:tileText(r), name:r.name}; };
const categoryInfo = (c: ReturnType<DesktopBrowse["categories"]>[number]) => {const exemplar=browse.exemplar(c.id);return {id:c.id,title:categoryDisplayTitle(c),enabled:browse.enabled(c.id),icon:exemplar.kind!=="custom-font"?exemplar.symbol:null,systemIcon:exemplar.kind==="custom-font"?(artwork.symbols as Record<string,string>)[exemplar.symbol.codePointAt(0)!.toString(16).toUpperCase()]??"square.grid.3x3":null};};
const get = (id: string) => { const r = records.get(id) ?? recordFor(index,id); if (!r) throw new Error("Glyph unavailable"); return r; };
const ready = (async () => {await browse.refresh(); if (!fixture) await browse.importLegacyUsage(data().usage);})();

async function dispatch(request: any): Promise<unknown> {
  const q = String(request.query ?? "");
  switch (request.op) {
    case "categories": await browse.refresh(); return browse.categories().map(categoryInfo);
    case "exemplar": await browse.setExemplar(request.category,request.symbol??null);return true;
    case "visibility": await browse.setEnabled(request.category,request.enabled); return true;
    case "list": {
      await browse.refresh(); let list: DesktopRecord[]; let cursor: string | null = null;
      if (q.trim()) list = search({index,data:data()},q).map(h=>h.record);
      else if (request.category === "utility:recents" || request.category === "recents") {const page = await browse.history(request.cursor); list=page.events.map(e=>historyRecord(e,index));cursor=page.nextCursor;}
      else if (request.category === "utility:frequent" || request.category === "frequent") list=frequentlyUsed(data(),1000).flatMap(id=>{const r=recordFor(index,id);return r?[r]:[];});
      else list = browse.members(request.category ?? browse.categories(true).find(c=>c.source.kind!=="utility")?.id ?? "");
      const offset = Number(request.offset ?? 0), limit=240;
      return {records:list.slice(offset,offset+limit).map(pack), total:list.length, nextOffset:offset+limit<list.length?offset+limit:null,cursor};
    }
    case "details": {
      const r=get(request.id), e=escapes(r.symbol,r.name), canonical=index.byId.get(r.hexseq);
      return {record:pack(r), values:[...(historyDescription(r)?[{label:"History",value:historyDescription(r)!}]:[]),{label:"Name",value:r.name},{label:"Code points",value:hexList(r.symbol).join(" ")},{label:"UTF-8",value:utf8Bytes(r.symbol)},{label:"UTF-16",value:utf16Units(r.symbol)},...ESCAPE_LABELS.map(([key,label])=>({label,value:e[key]})),...r.entities.map(value=>({label:"HTML entity",value:`&${value};`}))],notes:r.annotations??[],components:codePoints(r.symbol).map(cp=>`U+${cp.toString(16).toUpperCase()} ${componentName(cp,index)}`),classification:[r.block,r.set,r.script,r.age?`Unicode ${r.age}`:null].filter(Boolean).join(" · "),aliases:aliasesFor(data(),r.hexseq),keywords:[...new Set(r.keywords.map(k=>k.token))],variants:[...new Set([...skinVariants({...r,symbol:canonical?.symbol??r.symbol}),...(r.textPresentation?[r.symbol.replace(/[\uFE0E\uFE0F]/g,"")+"\uFE0E",r.symbol.replace(/[\uFE0E\uFE0F]/g,"")+"\uFE0F"]:[])])],twins:r.twins.flatMap(id=>{const x=recordFor(index,id);return x?[pack(x)]:[];}),related:[...r.related,...(r.genderVariants??[])].flatMap(id=>{const x=recordFor(index,id);return x?[pack(x)]:[];}),contexts:browse.contexts(r).map(c=>categoryInfo(c.category))};
    }
    case "pick": { const r=get(request.id), symbol=String(request.symbol??r.symbol); const identity=String([...symbol].map(c=>c.codePointAt(0)!.toString(16).toUpperCase()).filter(cp=>cp!=="FE0F").join(" ")); const state=mutateShared(file,d=>q.trim()?upVote(recordUsage(d,identity),q,identity):recordUsage(d,identity)); if(state.kind!=="ready") throw new Error(state.kind==="unreadable"?state.reason:"Library missing"); await browse.picked({...r,hexseq:identity},symbol,"native-app",request.action==="copy"?"copy":"insert"); return true; }
    case "teach": case "unlearn": { const r=get(request.id); const state=mutateShared(file,d=>request.op==="teach"?teach(d,request.term,r.hexseq):unlearn(d,request.term,r.hexseq)); if(state.kind!=="ready") throw new Error("Learning could not be saved"); return true; }
    default: throw new Error("Unknown operation");
  }
}
async function main() {
await ready;
const lines=createInterface({input:process.stdin});
for await (const line of lines) {
  let request: any;
  try {request=JSON.parse(line);const result=await dispatch(request);process.stdout.write(JSON.stringify({id:request.requestID,result})+"\n");}
  catch(error){process.stdout.write(JSON.stringify({id:request?.requestID,error:String(error)})+"\n");}
}

}
await main();
}
void boot().catch(error=>{process.stderr.write(String(error).slice(0,2000)+"\n");process.exitCode=1;});
