import {inflateRawSync,crc32} from 'node:zlib';
/** Validate extraction geometry before ditto sees an authenticated archive.
 * No ZIP64, multi-disk, encryption, links, duplicate/traversal paths or bombs. */
export function requireSafeZip(bytes,root,{maximumEntries=20000,maximumFile=250*1024*1024,maximumTotal=750*1024*1024}={}){
 let end=-1;
 for(let i=bytes.length-22;i>=Math.max(0,bytes.length-65557);i--)if(bytes.readUInt32LE(i)===0x06054b50){end=i;break;}
 if(end<0||bytes.readUInt16LE(end+4)!==0||bytes.readUInt16LE(end+6)!==0||end+22+bytes.readUInt16LE(end+20)!==bytes.length)throw Error('Unsupported ZIP layout');
 const count=bytes.readUInt16LE(end+10),size=bytes.readUInt32LE(end+12),offset=bytes.readUInt32LE(end+16);
 if(count===0xffff||size===0xffffffff||offset===0xffffffff||count>maximumEntries||offset+size!==end||bytes.readUInt16LE(end+8)!==count)throw Error('Invalid, oversized or ZIP64 archive');
 let cursor=offset,total=0;const paths=new Set(),ranges=[];
 for(let index=0;index<count;index++){
  if(cursor+46>offset+size||bytes.readUInt32LE(cursor)!==0x02014b50)throw Error('Invalid ZIP central entry');
  const checksum=bytes.readUInt32LE(cursor+16),flags=bytes.readUInt16LE(cursor+8),method=bytes.readUInt16LE(cursor+10),compressed=bytes.readUInt32LE(cursor+20),expanded=bytes.readUInt32LE(cursor+24),length=bytes.readUInt16LE(cursor+28),extra=bytes.readUInt16LE(cursor+30),comment=bytes.readUInt16LE(cursor+32),attributes=bytes.readUInt32LE(cursor+38),local=bytes.readUInt32LE(cursor+42);
  if(cursor+46+length+extra+comment>offset+size||flags&0x2041||![0,8].includes(method)||compressed===0xffffffff||expanded===0xffffffff||local===0xffffffff||expanded>maximumFile||(total+=expanded)>maximumTotal)throw Error('Unsupported or oversized ZIP entry');
  const name=bytes.subarray(cursor+46,cursor+46+length).toString('utf8'),mode=(attributes>>>16)&0xf000;
  if((mode&&![0x8000,0x4000].includes(mode))||name.includes('\\')||name.includes('\0')||name.startsWith('/')||name.split('/').some(p=>p==='..'||p==='.')||!(name===root+'/'||name.startsWith(root+'/'))||paths.has(name))throw Error('Unsafe or duplicate iOS archive entry');
  if(local+30>offset||bytes.readUInt32LE(local)!==0x04034b50)throw Error('Missing ZIP local header');
  const localLength=bytes.readUInt16LE(local+26),localExtra=bytes.readUInt16LE(local+28),dataStart=local+30+localLength+localExtra;
  if(dataStart+compressed>offset||bytes.subarray(local+30,local+30+localLength).toString('utf8')!==name||bytes.readUInt16LE(local+6)!==flags||bytes.readUInt16LE(local+8)!==method)throw Error('ZIP local and central entries disagree');
  if(!(flags&8)&&(bytes.readUInt32LE(local+14)!==checksum||bytes.readUInt32LE(local+18)!==compressed||bytes.readUInt32LE(local+22)!==expanded))throw Error('ZIP local sizes/checksum differ');
  let endOfEntry=dataStart+compressed;
  if(flags&8){const signed=bytes.readUInt32LE(endOfEntry)===0x08074b50,start=endOfEntry+(signed?4:0);if(start+12>offset||bytes.readUInt32LE(start)!==checksum||bytes.readUInt32LE(start+4)!==compressed||bytes.readUInt32LE(start+8)!==expanded)throw Error('Invalid ZIP data descriptor');endOfEntry=start+12;}
  const packed=bytes.subarray(dataStart,dataStart+compressed),unpacked=method===0?packed:inflateRawSync(packed,{maxOutputLength:Math.max(1,expanded)});
  if(unpacked.length!==expanded||crc32(unpacked)!==checksum)throw Error('ZIP actual expansion/checksum differs');
  for(const [extraStart,extraEnd]of [[cursor+46+length,cursor+46+length+extra],[local+30+localLength,dataStart]])for(let position=extraStart;position<extraEnd;){if(position+4>extraEnd)throw Error('Invalid ZIP extra field');const kind=bytes.readUInt16LE(position),fieldLength=bytes.readUInt16LE(position+2);if([1,0x7075].includes(kind)||position+4+fieldLength>extraEnd)throw Error('ZIP64, alternate path or invalid ZIP extra field');position+=4+fieldLength;}
  paths.add(name);ranges.push([local,endOfEntry]);cursor+=46+length+extra+comment;
 }
 ranges.sort((a,b)=>a[0]-b[0]);if(ranges.some((range,index)=>index&&range[0]<ranges[index-1][1]))throw Error('Overlapping ZIP entries');
 if(cursor!==offset+size||!paths.size)throw Error('Invalid ZIP directory size');
 return paths.size;
}
