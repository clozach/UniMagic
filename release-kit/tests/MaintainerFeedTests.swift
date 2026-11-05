import Foundation
@main enum MaintainerFeedTests {
    static func main() {
        let feed="https://api.github.com/repos/clozach/ClipEdge/releases/latest"
        let fingerprint=String(repeating:"a",count:64)
        let info:[String:Any]=["ClipEdgePublisherEnabled":true,"ClipEdgeContentFingerprint":fingerprint,
            "ClipEdgePublisherTool":"/fixture/projects/clipedge/src/tools/publisher.sh","ClipEdgeMaintainerUpdateFeed":feed]
        func resolved(_ value:[String:Any],exists:Bool=true)->String? {UpdateController.Environment.feedText(info:value,fileExists:{_ in exists})}
        precondition(resolved(info)==feed)
        precondition(PublishCapability.resolve(info:info,fileExists:{_ in true}) != nil)
        precondition(resolved([:]) == nil)
        precondition(resolved(["ClipEdgeMaintainerUpdateFeed":feed]) == nil)
        precondition(resolved(info,exists:false)==nil)
        for (key,value) in [("ClipEdgePublisherEnabled",false as Any),("ClipEdgeContentFingerprint","bad" as Any),
                            ("ClipEdgePublisherTool","/untrusted/publisher.sh" as Any),("ClipEdgeMaintainerUpdateFeed","https://evil.invalid/feed" as Any)] {
            var altered=info;altered[key]=value;precondition(resolved(altered)==nil)
        }
        var release=info;release["ClipEdgeUpdateFeed"]=feed
        precondition(resolved(release)==feed)
        precondition(PublishCapability.resolve(info:release,fileExists:{_ in true})==nil)
        let uni=ReleaseConfiguration(productName:"UniMagic",bundleIdentifier:"com.clozach.unimagic.mac",archiveBundleName:"UniMagic.app",infoPrefix:"UniMagic",supportFolder:"UniMagic/Updates",releasePage:URL(string:"https://github.com/clozach/UniMagic/releases/latest")!,publisherToolSuffix:"/tools/publisher.sh")
        let uniFeed="https://api.github.com/repos/clozach/UniMagic/releases/latest"
        let uniInfo:[String:Any]=["UniMagicPublisherEnabled":true,"UniMagicContentFingerprint":fingerprint,"UniMagicPublisherTool":"/fixture/tools/publisher.sh","UniMagicMaintainerUpdateFeed":uniFeed]
        precondition(UpdateController.Environment.feedText(info:uniInfo,configuration:uni,fileExists:{_ in true})==uniFeed)
        precondition(PublishCapability.resolve(info:uniInfo,configuration:uni,fileExists:{_ in true}) != nil)
        print("Maintainer feed tests passed: 13 assertions")
    }
}
