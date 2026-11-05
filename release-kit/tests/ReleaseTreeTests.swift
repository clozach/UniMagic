import Foundation
import Darwin

/// GitHub-shaped recursive tree from real git, including directory nodes; all
/// API/signing/network surfaces are fixtures. A real public manifest is checked.
@main enum ReleaseTreeTests {
    static var assertions = 0
    static let fm = FileManager.default
    static var fixture: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["RELEASE_TREE_FIXTURE"]!) }
    static func check(_ yes: Bool,_ label:String){precondition(yes,label);assertions += 1;print("PASS \(label)")}
    static func write(_ text:String,_ file:URL)throws{try fm.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true);try text.write(to:file,atomically:true,encoding:.utf8)}
    static func refuses(_ label:String,_ action:()throws->Void){do{try action();fatalError("Accepted \(label)")}catch{assertions += 1;print("PASS \(label)")}}
    static func main()throws{
        if CommandLine.arguments.dropFirst().first=="gh"{try gh(Array(CommandLine.arguments.dropFirst(2)));return}
        let root=fm.temporaryDirectory.appendingPathComponent("release-tree-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:true);defer{try?fm.removeItem(at:root)}
        setenv("RELEASE_TREE_FIXTURE",root.path,1)
        let source=root.appendingPathComponent("source")
        try write("generator",source.appendingPathComponent("src/generator/sources/input.ts"))
        try write("browser",source.appendingPathComponent("src/hosts/macos/browser.ts"))
        try write("1.0.1\n",source.appendingPathComponent("VERSION"))
        try write("docs",source.appendingPathComponent("docs/guide.md"))
        try Command.run("/usr/bin/git",["init","-q","-b","main"],at:source)
        try Command.run("/usr/bin/git",["add","."],at:source)
        try Command.run("/usr/bin/git",["-c","user.name=Fixture","-c","user.email=fixture@example.invalid","commit","-qm","fixture"],at:source)
        try Command.run("/usr/bin/git",["tag","v1.0.1"],at:source)
        let commit=try Command.text("/usr/bin/git",["rev-parse","HEAD"],at:source),tree=try Command.text("/usr/bin/git",["rev-parse","HEAD^{tree}"],at:source)
        // Unlike ls-tree -r, -r -t preserves GitHub's intermediate tree records.
        let raw=try Command.run("/usr/bin/git",["ls-tree","-r","-t","-z","HEAD"],at:source)
        let entries:[[String:Any]]=String(decoding:raw,as:UTF8.self).split(separator:"\0").map{line in
            let pair=line.split(separator:"\t",maxSplits:1),fields=pair[0].split(separator:" ")
            return ["mode":String(fields[0]),"type":String(fields[1]),"sha":String(fields[2]),"path":String(pair[1])]
        }
        var product=PublisherProduct.current
        product.name="UniMagic";product.repository="fixture/UniMagic";product.identityAlgorithm="prefix-content-v1"
        product.identityPrefixes=["src/"];product.identityExact=["VERSION"];product.allowInitialRelease=false
        product.archiveTemplate=".build/releases/UniMagic-{version}-macOS-arm64.zip"
        PublisherProduct.current=product
        var blobs:[String:String]=[:]
        for entry in entries where entry["type"] as? String=="blob"{blobs[entry["path"] as! String]=entry["sha"] as? String}
        let fingerprint=try ContentIdentity.fingerprint(blobs),archive=ContentIdentity.sha256(Data("signed archive fixture".utf8))
        let manifest:[String:Any]=["schema":1,"algorithm":product.identityAlgorithm,"version":"1.0.1","fingerprint":fingerprint,"archiveSHA256":archive]
        let latest:[String:Any]=["id":1,"tag_name":"v1.0.1","draft":false,"prerelease":false,"html_url":"https://fixture.invalid/releases/v1.0.1","assets":[["id":1,"name":"UniMagic-1.0.1-macOS-arm64.zip","size":20,"digest":"sha256:"+archive],["id":2,"name":"UniMagic-manifest.json","size":1]]]
        try writeJSON(latest,to:root.appendingPathComponent("latest.json"));try writeJSON(manifest,to:root.appendingPathComponent("manifest.json"))
        try writeJSON(["sha":commit,"commit":["tree":["sha":tree]]],to:root.appendingPathComponent("commit.json"))
        func save(_ rows:[[String:Any]],truncated:Bool=false)throws{try writeJSON(["sha":tree,"truncated":truncated,"tree":rows],to:root.appendingPathComponent("tree.json"))}
        try save(entries)
        let bin=root.appendingPathComponent("bin/gh")
        try write("#!/bin/bash\nexec \"$RELEASE_TREE_EXECUTABLE\" gh \"$@\"\n",bin)
        try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:bin.path)
        setenv("RELEASE_TREE_EXECUTABLE",URL(fileURLWithPath:CommandLine.arguments[0]).standardizedFileURL.path,1)
        setenv("PATH",bin.deletingLastPathComponent().path+":/usr/bin:/bin:/usr/sbin:/sbin",1)
        check(entries.contains{($0["type"] as? String)=="tree" && ContentIdentity.included($0["path"] as! String)},"fixture has real selected directory records")
        let released=try PublishedRelease.latest()
        check(released.fingerprint==fingerprint && released.commit==commit && released.tree==tree,"recursive prefix release verifies exact commit/tree/fingerprint")
        check(released.archiveSHA256==archive,"published manifest and archive digest validate")
        check(sourceStatus(root:source,running:fingerprint)["kind"] as? String=="equal","maintainer status verifies published prefix source")
        for entry:[String:Any] in [["mode":"120000","type":"blob","path":"src/link","sha":String(repeating:"a",count:40)],["mode":"160000","type":"commit","path":"src/submodule","sha":String(repeating:"a",count:40)],["mode":"120000","type":"tree","path":"src/fake-tree","sha":String(repeating:"a",count:40)],["mode":"040000","type":"blob","path":"src/fake-blob","sha":String(repeating:"a",count:40)]] {
            try save(entries+[entry]);refuses("selected nonregular entry \(entry["type"]!)/\(entry["mode"]!)") {_=try PublishedRelease.latest()}
        }
        try save(entries+[["mode":"160000","type":"commit","path":"docs/submodule","sha":String(repeating:"a",count:40)]])
        check(try PublishedRelease.latest().fingerprint==fingerprint,"non-build-input submodule does not affect source fingerprint")
        try save(entries,truncated:true);refuses("truncated graph is rejected"){_=try PublishedRelease.latest()}
        try save(entries)
        var bad=manifest;bad["fingerprint"]=String(repeating:"0",count:64);try writeJSON(bad,to:root.appendingPathComponent("manifest.json"))
        refuses("manifest mismatch remains rejected after directory skip"){_=try PublishedRelease.latest()}
        try writeJSON(manifest,to:root.appendingPathComponent("manifest.json"))
        check(try PublishedRelease.latest().fingerprint==fingerprint,"valid manifest recovers without modifying source")
        print("Release recursive-tree tests passed: \(assertions) assertions; real git, mocked API")
    }
    static func gh(_ args:[String])throws {
        let name:String
        if args.first=="api",args[1].hasSuffix("/releases/latest"){name="latest.json"}
        else if args.first=="api",args[1].contains("/commits/"){name="commit.json"}
        else if args.first=="api",args[1].contains("/git/trees/"){name="tree.json"}
        else if args.prefix(2)==["release","download"]{name="manifest.json"}
        else{fatalError("Unmocked GitHub call \(args)")}
        FileHandle.standardOutput.write(try Data(contentsOf:fixture.appendingPathComponent(name)))
    }
}
