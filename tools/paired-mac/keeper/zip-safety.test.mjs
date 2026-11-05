import test from 'node:test';
import assert from 'node:assert/strict';
import {requireSafeZip} from './zip-safety.mjs';
import {deflateRawSync,crc32} from 'node:zlib';
function archive(name,mode=0x8000,data=Buffer.alloc(0),compress=false,declared=data.length){const text=Buffer.from(name),packed=compress?deflateRawSync(data):data,local=Buffer.alloc(30+text.length),entry=Buffer.alloc(46+text.length),end=Buffer.alloc(22);local.writeUInt32LE(0x04034b50);local.writeUInt16LE(compress?8:0,8);local.writeUInt32LE(crc32(data),14);local.writeUInt32LE(packed.length,18);local.writeUInt32LE(declared,22);local.writeUInt16LE(text.length,26);text.copy(local,30);entry.writeUInt32LE(0x02014b50,0);entry.writeUInt16LE(compress?8:0,10);entry.writeUInt32LE(crc32(data),16);entry.writeUInt32LE(packed.length,20);entry.writeUInt32LE(declared,24);entry.writeUInt16LE(text.length,28);entry.writeUInt32LE((mode<<16)>>>0,38);text.copy(entry,46);end.writeUInt32LE(0x06054b50);end.writeUInt16LE(1,8);end.writeUInt16LE(1,10);end.writeUInt32LE(entry.length,12);end.writeUInt32LE(local.length+packed.length,16);return Buffer.concat([local,packed,entry,end]);}
test('ZIP safety accepts ordinary app file and rejects links, traversal, wrong root and corruption before extraction',()=>{
 assert.equal(requireSafeZip(archive('Unimagic.app/file'),'Unimagic.app'),1);
 for(const bytes of [archive('Unimagic.app/link',0xa000),archive('Unimagic.app/../outside'),archive('/Unimagic.app/file'),archive('Other.app/file'),Buffer.alloc(2)])assert.throws(()=>requireSafeZip(bytes,'Unimagic.app'));
});

test('ZIP rejects advertised expansion/count limits and local/central path mismatch before extraction',()=>{
 const bytes=archive('Unimagic.app/file');assert.throws(()=>requireSafeZip(bytes,'Unimagic.app',{maximumEntries:0}));
 const mismatch=Buffer.from(bytes);mismatch[30]=88;assert.throws(()=>requireSafeZip(mismatch,'Unimagic.app'),/disagree/);
 const oversized=Buffer.from(bytes),central=30+Buffer.byteLength('Unimagic.app/file');oversized.writeUInt32LE(100,central+24);assert.throws(()=>requireSafeZip(oversized,'Unimagic.app',{maximumFile:99}),/oversized/);
});

test('actual deflate expansion cannot exceed advertised size even when both headers lie',()=>{
 const bomb=archive('Unimagic.app/file',0x8000,Buffer.alloc(1000000,97),true,1);
 assert.throws(()=>requireSafeZip(bomb,'Unimagic.app'));
 assert.equal(requireSafeZip(archive('Unimagic.app/file',0x8000,Buffer.from('bounded'),true),'Unimagic.app'),1);
});
