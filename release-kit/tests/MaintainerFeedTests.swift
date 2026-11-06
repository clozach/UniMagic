import Foundation

@main enum MaintainerFeedTests {
    @MainActor static func main() async throws {
        let feed = "https://api.github.com/repos/clozach/ClipEdge/releases/latest"
        let fingerprint = String(repeating: "a", count: 64)
        let info: [String: Any] = ["ClipEdgePublisherEnabled": true, "ClipEdgeContentFingerprint": fingerprint,
            "ClipEdgePublisherTool": "/fixture/projects/clipedge/src/tools/publisher.sh", "ClipEdgeMaintainerUpdateFeed": feed]
        func resolved(_ value: [String: Any], exists: Bool = true) -> String? {
            UpdateController.Environment.feedText(info: value, fileExists: { _ in exists })
        }
        precondition(resolved(info) == nil)
        precondition(PublishCapability.resolve(info: info, fileExists: { _ in true }) != nil)
        precondition(resolved([:]) == nil)
        precondition(resolved(["ClipEdgeMaintainerUpdateFeed": feed]) == nil)
        precondition(resolved(info, exists: false) == nil)
        var legacy = info
        legacy["ClipEdgeUpdateFeed"] = feed
        precondition(resolved(legacy) == nil)
        precondition(resolved(legacy, exists: false) == nil)
        let publicInfo: [String: Any] = ["ClipEdgeUpdateFeed": feed]
        precondition(resolved(publicInfo) == feed)
        let uni = ReleaseConfiguration(productName: "UniMagic", bundleIdentifier: "com.clozach.unimagic.mac",
            archiveBundleName: "UniMagic.app", infoPrefix: "UniMagic", supportFolder: "UniMagic/Updates",
            releasePage: URL(string: "https://github.com/clozach/UniMagic/releases/latest")!, publisherToolSuffix: "/tools/publisher.sh")
        let uniFeed = "https://api.github.com/repos/clozach/UniMagic/releases/latest"
        let uniInfo: [String: Any] = ["UniMagicPublisherEnabled": true, "UniMagicContentFingerprint": fingerprint,
            "UniMagicPublisherTool": "/fixture/tools/publisher.sh", "UniMagicMaintainerUpdateFeed": uniFeed]
        precondition(UpdateController.Environment.feedText(info: uniInfo, configuration: uni, fileExists: { _ in true }) == uniFeed)
        precondition(PublishCapability.resolve(info: uniInfo, configuration: uni, fileExists: { _ in true }) != nil)
        precondition(!uni.preservesMaintainerBuild(info: uniInfo))

        var lane = uni; lane.stableArchiveTemplate = "UniMagic-{version}-macOS-arm64.zip"
        lane.releasePage = URL(string:"https://github.com/clozach/UniMagic/releases")!
        var separated = uniInfo; separated["UniMagicMaintainerUpdateFeed"] = "https://api.github.com/repos/clozach/UniMagic/releases?per_page=12"
        precondition(UpdateController.Environment.feedText(info: separated, configuration: lane, fileExists: { _ in true }) == separated["UniMagicMaintainerUpdateFeed"] as? String)
        precondition(UpdateController.Environment.feedText(info: uniInfo, configuration: lane, fileExists: { _ in true }) == nil)
        precondition(PublishCapability.resolve(info: separated, configuration: lane, fileExists: { _ in true }) != nil)

        let listURL = URL(string:separated["UniMagicMaintainerUpdateFeed"] as! String)!
        let transport = URLSessionConfiguration.ephemeral;transport.protocolClasses = [StableListFixture.self]
        let client = URLSession(configuration:transport)
        func listed(_ v:String, draft:Bool = false, prerelease:Bool = false) -> [String:Any] {
            let zip = "UniMagic-\(v)-macOS-arm64.zip"
            let exact: [String:Any] = ["name":zip,"size":250,"state":"uploaded","browser_download_url":"https://github.com/clozach/UniMagic/releases/download/v\(v)/\(zip)"]
            let decoy: [String:Any] = ["name":"UniMagic-other.zip","size":200,"state":"uploaded","browser_download_url":"https://fixture.invalid/wrong.zip"]
            return ["tag_name":"v"+v,"draft":draft,"prerelease":prerelease,"assets":[decoy,exact]]
        }
        let valid = [listed("1.0.3"),listed("2.0.0",draft:true),listed("2.0.1",prerelease:true),listed("1.0.10"),listed("1.0.9")]
        func read(_ rows:[[String:Any]]) async throws -> UpdateRelease {
            StableListFixture.response = try JSONSerialization.data(withJSONObject:rows)
            return try await UpdateFetcher.release(feed:listURL,runningVersion:"1.0.4",session:client,productName:"UniMagic",stableArchiveTemplate:lane.stableArchiveTemplate)
        }
        let chosen = try await read(valid)
        precondition(chosen.version==AppVersion("1.0.10")! && chosen.archive.lastPathComponent=="UniMagic-1.0.10-macOS-arm64.zip")
        var invalid = listed("1.0.11");var duplicates = invalid["assets"] as! [[String:Any]]
        duplicates.append(duplicates.last!);invalid["assets"] = duplicates
        let rejected = try? await read([invalid]);precondition(rejected == nil)
        let excess = try? await read(Array(repeating:listed("1.0.3"),count:13));precondition(excess == nil)
        client.invalidateAndCancel()

        func availability(_ metadata: [String: Any]) -> UpdateAvailability {
            UpdateAvailability.resolve(bundle: URL(fileURLWithPath: "/Applications/ClipEdge.app"),
                feedText: resolved(metadata), isAdHoc: { false }, folderWritable: { true },
                preservesMaintainerBuild: ReleaseConfiguration.clipEdge.preservesMaintainerBuild(info: metadata))
        }
        precondition(availability(legacy) == .blocked(.maintainerCopy))
        precondition(availability([:]) == .blocked(.builtFromSource))
        precondition(availability(publicInfo) == .available(feed: URL(string: feed)!))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let staged = root.appendingPathComponent("release.app")
        let contents = staged.appendingPathComponent("Contents");try! FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let system = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        func requires(_ value:String, architecture:String? = nil) {
            var info:[String:Any] = ["LSMinimumSystemVersion":value]
            if let architecture {info["LSMinimumSystemVersionByArchitecture"] = ["arm64":architecture]}
            try! PropertyListSerialization.data(fromPropertyList:info,format:.xml,options:0).write(to:contents.appendingPathComponent("Info.plist"))
        }
        requires("26.0");try! UpdateVerifier.requireSupportedMac(staged,on:system)
        requires("27.0");precondition((try? UpdateVerifier.requireSupportedMac(staged,on:system)) == nil)
        requires("26.0",architecture:"26.1");precondition((try? UpdateVerifier.requireSupportedMac(staged,on:system)) == nil)
        let version = AppVersion("1.0")!
        let release = UpdateRelease(version: AppVersion("2.0")!, archive: URL(string: feed)!, archiveBytes: 1, page: nil)
        var requests = 0, downloads = 0, installs = 0, rollbacks = 0, reopens = 0, prompts = 0, saves = 0
        func environment(_ support: URL, _ available: UpdateAvailability, validReceipt: Bool = true) -> UpdateController.Environment {
            UpdateController.Environment(runningVersion: version, availability: available, support: support,
                fetchRelease: { _ in requests += 1; return release },
                fetchApp: { _, folder in downloads += 1; return folder.appendingPathComponent("ClipEdge.app") },
                verify: { _ in }, installedVersion: { _ in release.version },
                install: { _, _ in installs += 1; return support.appendingPathComponent("receipt") },
                goBack: { _ in rollbacks += 1 }, canGoBack: { _ in validReceipt }, isBusy: { false },
                secondsSinceInput: { 999 }, saveBeforeQuit: { saves += 1; return true }, reopenAndQuit: { reopens += 1 })
        }
        let record = UpdateRecord(from: "0.9", to: "1.0", date: Date(), receipt: root.appendingPathComponent("old-receipt"), page: URL(string: feed))
        for preference in [UpdatePreference.automatic, .unasked] {
            let folder = root.appendingPathComponent(preference.rawValue)
            UpdateState(preference: preference, lastUpdate: record).save(in: folder)
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("staged/ClipEdge.app"), withIntermediateDirectories: true)
            let controller = UpdateController(environment: environment(folder, availability(legacy)))
            controller.onNeedsChoice = { prompts += 1 }
            controller.start(repeating: false)
            precondition(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("staged").path))
            controller.tick()
            _ = await controller.check()
            _ = controller.installNow()
            precondition(!controller.canGoBack)
            precondition(controller.goBack() != nil)
            precondition(controller.preference == preference)
            precondition(UpdateState.load(from: folder).preference == preference)
            let snapshot = UpdateStatus.Snapshot(version: version, availability: controller.availability,
                preference: preference, phase: controller.phase, lastUpdate: record, canGoBack: true, now: Date())
            precondition(UpdateStatus.rows(snapshot) == [.status(UpdateStatus.line(snapshot))])
            precondition(UpdateStatus.line(snapshot).contains("is your maintainer copy. Rebuild it to update; public releases won’t replace it."))
        }
        precondition(requests == 0 && downloads == 0 && installs == 0 && rollbacks == 0 && reopens == 0 && prompts == 0 && saves == 0)
        let publicFolder = root.appendingPathComponent("public")
        let ordinary = UpdateController(environment: environment(publicFolder, availability(publicInfo)))
        ordinary.start(repeating: false)
        ordinary.choose(.automatic)
        _ = await ordinary.check()
        _ = ordinary.installNow()
        precondition(requests == 1 && downloads == 1 && installs == 1 && reopens == 1)
        let noReceiptFolder = root.appendingPathComponent("invalid-receipt")
        UpdateState(preference: .automatic, lastUpdate: record).save(in: noReceiptFolder)
        let noReceipt = UpdateController(environment: environment(noReceiptFolder, availability(publicInfo), validReceipt: false))
        precondition(!noReceipt.canGoBack && noReceipt.goBack() != nil)
        precondition(rollbacks == 0 && noReceipt.preference == .automatic)
        print("Maintainer update protection tests passed")
    }
}

private final class StableListFixture: URLProtocol, @unchecked Sendable {
    static var response = Data()
    override class func canInit(with request:URLRequest) -> Bool { request.url?.host=="api.github.com" }
    override class func canonicalRequest(for request:URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply=HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:nil)!
        client?.urlProtocol(self,didReceive:reply,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Self.response);client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
