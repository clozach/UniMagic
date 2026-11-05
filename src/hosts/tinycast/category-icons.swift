// Build-time native system symbols replace the unlicensed category font artwork.
import AppKit
let catalogue=URL(fileURLWithPath:CommandLine.arguments[1])
let artwork=URL(fileURLWithPath:CommandLine.arguments[2])
let output=URL(fileURLWithPath:CommandLine.arguments[3])
let root=try JSONSerialization.jsonObject(with:Data(contentsOf:catalogue)) as! [String:Any]
let artworkRoot=try JSONSerialization.jsonObject(with:Data(contentsOf:artwork)) as! [String:Any]
let map=artworkRoot["symbols"] as! [String:String]
for category in root["categories"] as! [[String:Any]] {
 let exemplar=category["defaultExemplar"] as! [String:Any]
 guard exemplar["kind"] as? String == "custom-font" else {continue}
 let id=(category["id"] as! String).replacingOccurrences(of:":",with:"-")
 let scalar=(exemplar["symbol"] as! String).unicodeScalars.first!.value
 let name=map[String(scalar,radix:16).uppercased()] ?? "square.grid.3x3"
 for dark in [false,true] {
  let image=NSImage(size:NSSize(width:64,height:64));image.lockFocus()
  let symbol=(NSImage(systemSymbolName:name,accessibilityDescription:category["title"] as? String) ?? NSImage(systemSymbolName:"square.grid.3x3",accessibilityDescription:nil)!).withSymbolConfiguration(.init(pointSize:42,weight:.regular))!
  let rect=NSRect(x:(64-symbol.size.width)/2,y:(64-symbol.size.height)/2,width:symbol.size.width,height:symbol.size.height)
  symbol.draw(in:rect);(dark ? NSColor.white:NSColor.black).set();rect.fill(using:.sourceAtop)
  image.unlockFocus()
  let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
  try bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("\(id)-\(dark ? "dark":"light").png"))
 }
}
