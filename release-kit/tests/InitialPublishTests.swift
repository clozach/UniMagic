import Foundation
import Darwin

/// Full first-publication flow: real local git commits/pushes, mocked GitHub and
/// signing. No candidate/app/receipt is modified during any publication attempt.
@main enum InitialPublishTests {
    static var checks = 0
    static var root: URL { URL(fileURLWithPath: ProcessInfo.processInfo.environment["INITIAL_ROOT"]!) }
    static let fm = FileManager.default
    static func check(_ condition: Bool, _ name: String) { precondition(condition,name); checks += 1; print("PASS \(name)") }
    static func write(_ text: String,_ file: URL) throws { try fm.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true);try text.write(to:file,atomically:true,encoding:.utf8) }
    static func executable(_ text:String,_ file:URL)throws {try write(text,file);try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:file.path)}
    static func flag(_ name:String)throws {try write("fixture",root.appendingPathComponent(name))}
    static func exists(_ name:String)->Bool {fm.fileExists(atPath:root.appendingPathComponent(name).path)}
    static func refuses(_ name:String,_ action:()throws->Void){do {try action();fatalError("Accepted \(name)")}catch {checks += 1;print("PASS \(name)")}}
    static func main() throws {
        setvbuf(stdout,nil,_IONBF,0)
        PublisherProduct.current.allowInitialRelease = true
        let arguments=Array(CommandLine.arguments.dropFirst())
        if arguments.first=="identity" {print(try ContentIdentity.local(URL(fileURLWithPath:arguments[1])));return}
        if arguments.first=="gh" {try gh(Array(arguments.dropFirst()));return}
        let temp=fm.temporaryDirectory.appendingPathComponent("initial-publish-"+UUID().uuidString)
        try fm.createDirectory(at:temp,withIntermediateDirectories:true);defer{try?fm.removeItem(at:temp)}
        setenv("INITIAL_TEST_EXECUTABLE",URL(fileURLWithPath:CommandLine.arguments[0]).standardizedFileURL.path,1)
        setenv("GIT_CONFIG_GLOBAL","/dev/null",1)
        for key in ["GIT_AUTHOR_NAME","GIT_COMMITTER_NAME"]{setenv(key,"Initial publisher fixture",1)}
        for key in ["GIT_AUTHOR_EMAIL","GIT_COMMITTER_EMAIL"]{setenv(key,"fixture@example.invalid",1)}
        let bin=temp.appendingPathComponent("bin")
        try executable("#!/bin/bash\nexec \"$INITIAL_TEST_EXECUTABLE\" gh \"$@\"\n",bin.appendingPathComponent("gh"))
        try executable("""
        #!/bin/bash
        if [[ $1 == clone ]]; then exec /usr/bin/git clone --quiet "$INITIAL_ROOT/public.git" "${@: -1}"; fi
        if [[ $1 == push ]]; then
          /usr/bin/git "$@" || exit $?
          if [[ -f "$INITIAL_ROOT/pause-push" ]]; then rm "$INITIAL_ROOT/pause-push"; exit 42; fi
          exit 0
        fi
        exec /usr/bin/git "$@"
        """,bin.appendingPathComponent("git"))
        try executable("#!/bin/bash\nif [[ $1 == -d ]]; then echo 'Authority=Fixture certificate' >&2; echo 'designated => identifier \"local.codex.ClipEdge\"' >&2; fi\nexit 0\n",bin.appendingPathComponent("codesign"))
        setenv("PATH",bin.path+":/usr/bin:/bin:/usr/sbin:/sbin",1)
        for scenario in ["first","resume","contributor-before","contributor-after","tag-after","hidden-resume","retag-resume","empty-retag-resume","new-release"] {
            let state=temp.appendingPathComponent(scenario);try fm.createDirectory(at:state,withIntermediateDirectories:true);setenv("INITIAL_ROOT",state.path,1)
            let source=try makeSource(),running=try ContentIdentity.local(source)
            let candidate=try Candidate.prepare(root:source,running:running),receipt=try digest(candidate.manifest)
            let frozen=try Data(contentsOf:candidate.manifest),archive=try digest(candidate.archive),sourceDigest=try Candidate.treeDigest(candidate.source)
            func publish()throws->[String:Any]{try candidate.publish(root:source,running:running,approvedDigest:archive,approvedReceipt:receipt)}
            switch scenario {
            case "first": check(try publish()["kind"] as? String == "published","initial self-push publishes without false competing-baseline failure")
            case "resume":
                try flag("pause-push");refuses("interrupted own push stops before upload"){_ = try publish()}
                check(!exists("draft.json"),"no draft before interrupted push returns")
                check(try publish()["kind"] as? String == "published","own initial main/tag resumes same frozen candidate")
            case "contributor-before":
                try advance(hidden:false);refuses("contributor advance before push is refused"){_ = try publish()};check(!exists("draft.json"),"contributor refusal uploads nothing")
            case "contributor-after","tag-after","new-release":
                try flag(scenario);refuses("\(scenario) before release is refused"){_ = try publish()};check(!exists("edited"),"\(scenario) never exposes own draft")
            case "hidden-resume","retag-resume","empty-retag-resume":
                try flag("pause-push");refuses("pause after actual source push"){_ = try publish()}
                if scenario=="hidden-resume" {try advance(hidden:true)}
                else if scenario=="empty-retag-resume" {try emptyRetagAdvance()}
                else {try retag()}
                refuses("\(scenario) cannot masquerade as owned initial source"){_ = try publish()};check(!exists("draft.json"),"\(scenario) uploads nothing")
            default:break
            }
            check(try Data(contentsOf:candidate.manifest)==frozen,"\(scenario) immutable receipt unchanged")
            check(try digest(candidate.archive)==archive && Candidate.treeDigest(candidate.source)==sourceDigest,"\(scenario) immutable archive/source unchanged")
        }
        print("Initial publisher tests passed: \(checks) assertions; GitHub/signing mocked, real git")
    }
    static func makeSource()throws->URL {
        let source=root.appendingPathComponent("source"),seed=root.appendingPathComponent("seed")
        try write("bootstrap\n",seed.appendingPathComponent("README.md"))
        try Command.run("/usr/bin/git",["init","-q","-b","main"],at:seed)
        try Command.run("/usr/bin/git",["add","."],at:seed);try Command.run("/usr/bin/git",["commit","-qm","bootstrap"],at:seed)
        try Command.run("/usr/bin/git",["clone","--bare","-q",seed.path,root.appendingPathComponent("public.git").path])
        try write("// original source\n",source.appendingPathComponent("App.swift"));try write("1.0.0\n",source.appendingPathComponent("VERSION"))
        try write("# Changes\n\n## Unreleased\n\nFirst reviewed release.\n",source.appendingPathComponent("CHANGES.md"));try write(".build/\n",source.appendingPathComponent(".gitignore"))
        try write("icon",source.appendingPathComponent("Resources/AppIcon.icns"));try write("#!/bin/bash\ntrue\n",source.appendingPathComponent("tools/build.sh"))
        for file in ["test.sh","test-install.sh","test-update.sh"]{try write("#!/bin/bash\ntrue\n",source.appendingPathComponent("tools/"+file))}
        try write("#!/bin/bash\nset -eu\nmkdir -p \"$1/tools\" \"$1/Resources\"\ncp App.swift VERSION CHANGES.md .gitignore \"$1/\"\ncp tools/*.sh \"$1/tools/\"\ncp Resources/AppIcon.icns \"$1/Resources/\"\n",source.appendingPathComponent("tools/export-source.sh"))
        try write("""
        #!/bin/bash
        set -eu
        version=$(cat VERSION)
        fingerprint=$("$INITIAL_TEST_EXECUTABLE" identity "$PWD")
        app=".build/releases/ClipEdge-$version.app"
        mkdir -p "$app/Contents/MacOS"
        cat > "$app/Contents/Info.plist" <<PLIST
        <?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>local.codex.ClipEdge</string><key>CFBundleShortVersionString</key><string>$version</string><key>ClipEdgeContentFingerprint</key><string>$fingerprint</string><key>ClipEdgeUpdateFeed</key><string>https://api.github.com/repos/clozach/ClipEdge/releases/latest</string></dict></plist>
        PLIST
        echo "$fingerprint" > "$app/Contents/MacOS/ClipEdge"
        stage=$(mktemp -d);cp -R "$app" "$stage/ClipEdge.app"
        /usr/bin/ditto -c -k --norsrc --keepParent "$stage/ClipEdge.app" ".build/releases/ClipEdge-$version-macOS-universal.zip"
        rm -rf "$stage"
        """,source.appendingPathComponent("tools/release.sh"))
        return source
    }
    static func advance(hidden:Bool)throws {
        let clone=root.appendingPathComponent("contribution-"+UUID().uuidString)
        try Command.run("/usr/bin/git",["clone","-q",root.appendingPathComponent("public.git").path,clone.path])
        try write("independent",clone.appendingPathComponent(hidden ? ".github/private.txt" : "contributor.txt"))
        try Command.run("/usr/bin/git",["add","."],at:clone);try Command.run("/usr/bin/git",["commit","-qm","contributor"],at:clone);try Command.run("/usr/bin/git",["push","-q"],at:clone)
    }
    static func emptyRetagAdvance() throws {
        let clone=root.appendingPathComponent("empty-contribution")
        try Command.run("/usr/bin/git",["clone","-q",root.appendingPathComponent("public.git").path,clone.path])
        // Even a contributor copying our message and frozen tree must not be
        // mistaken for the publisher's one commit directly after its baseline.
        try Command.run("/usr/bin/git",["commit","--allow-empty","-qm","ClipEdge 1.0.0"],at:clone)
        try Command.run("/usr/bin/git",["tag","-f","v1.0.0","HEAD"],at:clone)
        try Command.run("/usr/bin/git",["push","-q","origin","HEAD:main","+refs/tags/v1.0.0:refs/tags/v1.0.0"],at:clone)
    }
    static func retag()throws {
        let repo=root.appendingPathComponent("public.git").path
        let head=try Command.text("/usr/bin/git",["--git-dir",repo,"rev-parse","main^1"])
        try Command.run("/usr/bin/git",["--git-dir",repo,"tag","-f","v1.0.0",head])
    }
    static func gh(_ args:[String])throws {
        if args.first=="api",args[1].hasSuffix("/releases/latest") {
            if !exists("latest.json"){emit(["status":"404"]);exit(1)}
            FileHandle.standardOutput.write(try Data(contentsOf:root.appendingPathComponent("latest.json")));return
        }
        if args.first=="api",args[1].contains("/commits/") {
            let ref=String(args[1].components(separatedBy:"/commits/")[1]),repo=root.appendingPathComponent("public.git").path
            let sha=try Command.text("/usr/bin/git",["--git-dir",repo,"rev-parse",ref+"^{commit}"])
            let tree=try Command.text("/usr/bin/git",["--git-dir",repo,"rev-parse",ref+"^{tree}"]);emit(["sha":sha,"commit":["tree":["sha":tree]]]);return
        }
        if args.first=="api",args[1].contains("/git/trees/") {
            let sha=String(args[1].components(separatedBy:"/git/trees/")[1].split(separator:"?")[0]),repo=root.appendingPathComponent("public.git").path
            let list=try Command.text("/usr/bin/git",["--git-dir",repo,"ls-tree","-r",sha])
            let entries=list.split(separator:"\n").map{line->[String:Any] in let pair=line.split(separator:"\t",maxSplits:1);let fields=pair[0].split(separator:" ");return ["mode":String(fields[0]),"type":String(fields[1]),"sha":String(fields[2]),"path":String(pair[1])]}
            emit(["sha":sha,"truncated":false,"tree":entries]);return
        }
        if args.first=="api",args[1].contains("/releases/tags/"){if !exists("draft.json"){exit(1)};FileHandle.standardOutput.write(try Data(contentsOf:root.appendingPathComponent("draft.json")));return}
        if args.prefix(2)==["release","download"]{FileHandle.standardOutput.write(try Data(contentsOf:root.appendingPathComponent("uploaded-manifest.json")));return}
        if args.prefix(2)==["release","create"] || args.prefix(2)==["release","upload"] {
            let archive=URL(fileURLWithPath:args[3]),version=String(args[2].dropFirst()),digest=try digest(archive)
            let draft:[String:Any]=["id":1,"tag_name":args[2],"draft":true,"prerelease":false,"html_url":"https://fixture.invalid/release","published_at":"2026-11-05","assets":[["id":1,"name":archive.lastPathComponent,"size":try Data(contentsOf:archive).count,"digest":"sha256:"+digest],["id":2,"name":"ClipEdge-manifest.json","size":1]]]
            try writeJSON(draft,to:root.appendingPathComponent("draft.json"));try Data(contentsOf:URL(fileURLWithPath:args[5])).write(to:root.appendingPathComponent("draft-manifest.json"))
            if exists("contributor-after"){try advance(hidden:false)}
            if exists("tag-after"){try retag()}
            if exists("new-release") {
                var other=draft;other["draft"]=false;other["tag_name"]="v9.0.0"
                var assets=other["assets"] as! [[String:Any]];assets[0]["name"]="ClipEdge-9.0.0-macOS-universal.zip";other["assets"]=assets
                var manifest=try jsonObject(Data(contentsOf:root.appendingPathComponent("draft-manifest.json")));manifest["version"]="9.0.0"
                try writeJSON(other,to:root.appendingPathComponent("latest.json"));try writeJSON(manifest,to:root.appendingPathComponent("uploaded-manifest.json"))
                try Command.run("/usr/bin/git",["--git-dir",root.appendingPathComponent("public.git").path,"tag","v9.0.0","main"])
            }
            _ = version;return
        }
        if args.prefix(2)==["release","edit"]{var latest=try jsonObject(Data(contentsOf:root.appendingPathComponent("draft.json")));latest["draft"]=false;try writeJSON(latest,to:root.appendingPathComponent("latest.json"));try Data(contentsOf:root.appendingPathComponent("draft-manifest.json")).write(to:root.appendingPathComponent("uploaded-manifest.json"));try flag("edited");return}
        fatalError("Unmocked GitHub command \(args)")
    }
}
