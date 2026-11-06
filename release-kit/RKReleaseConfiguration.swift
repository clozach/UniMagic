import Foundation

enum MaintainerUpdatePolicy { case allowPublicReleases, preserveBuild }

/// Product identity and trusted maintainer capability supplied by each host.
struct ReleaseConfiguration {
    var productName: String
    var bundleIdentifier: String
    var archiveBundleName: String
    var infoPrefix: String
    var supportFolder: String
    var releasePage: URL
    /// Exact helper suffix permitted by this product's local maintainer build.
    var publisherToolSuffix: String

    /// Set only for clients reading an array of stable GitHub releases.
    var stableArchiveTemplate: String? = nil
    var maintainerUpdatePolicy: MaintainerUpdatePolicy = .allowPublicReleases

    /// This build identity survives a missing publisher helper and legacy feed metadata.
    func preservesMaintainerBuild(info: [String: Any]) -> Bool {
        maintainerUpdatePolicy == .preserveBuild && info[infoPrefix + "PublisherEnabled"] as? Bool == true
    }

    static let clipEdge = ReleaseConfiguration(productName: "ClipEdge", bundleIdentifier: "local.codex.ClipEdge",
        archiveBundleName: "ClipEdge.app", infoPrefix: "ClipEdge", supportFolder: "ClipEdge/Updates",
        releasePage: URL(string: "https://github.com/clozach/ClipEdge/releases/latest")!,
        publisherToolSuffix: "/projects/clipedge/src/tools/publisher.sh", maintainerUpdatePolicy: .preserveBuild)
}

struct PublishCapability: Equatable {
    var fingerprint: String
    var tool: URL

    static func resolve(info: [String: Any], configuration: ReleaseConfiguration = .clipEdge, fileExists: (String) -> Bool = FileManager.default.isReadableFile) -> Self? {
        guard info[configuration.infoPrefix + "PublisherEnabled"] as? Bool == true,
              info[configuration.infoPrefix + "UpdateFeed"] == nil,
              let fingerprint = info[configuration.infoPrefix + "ContentFingerprint"] as? String, Self.isFingerprint(fingerprint),
              let path = info[configuration.infoPrefix + "PublisherTool"] as? String, path.hasPrefix("/"),
              path.hasSuffix(configuration.publisherToolSuffix),
              !path.contains("/../"), !path.contains("/./"), fileExists(path) else { return nil }
        return Self(fingerprint: fingerprint, tool: URL(fileURLWithPath: path))
    }
    static func isFingerprint(_ text: String) -> Bool {
        text.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil
    }

}
