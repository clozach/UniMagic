import Foundation

/// Only a local maintainer wrapper supplies this file; candidates freeze it with
/// source. Script hooks are relative executable paths, never shell expressions.
struct PublisherProduct: Decodable {
    var name: String
    var repository: String
    var bundleIdentifier: String
    var infoPrefix: String
    var identityAlgorithm: String
    var identityPrefixes: [String]
    var identityExact: [String]
    var exportScript: String
    var testScripts: [String]
    var releaseScript: String
    var archiveTemplate: String
    var appTemplate: String
    var allowInitialRelease: Bool
    var excludePrefixes: [String]? = nil
    var sourceMappings: [String: String]? = nil
    static var current = PublisherProduct(name: "ClipEdge", repository: "clozach/ClipEdge", bundleIdentifier: "local.codex.ClipEdge",
        infoPrefix: "ClipEdge", identityAlgorithm: "clipedge-content-v1", identityPrefixes: [],
        identityExact: ["Resources/AppIcon.icns", "tools/build.sh", "tools/publisher/Identity.swift", "tools/publisher/IdentityMain.swift", "tools/publisher/ProductSpec.swift", "tools/release-kit-sources.sh"],
        exportScript: "tools/export-source.sh", testScripts: ["tools/test.sh", "tools/test-install.sh", "tools/test-update.sh"],
        releaseScript: "tools/release.sh", archiveTemplate: ".build/releases/ClipEdge-{version}-macOS-universal.zip",
        appTemplate: ".build/releases/ClipEdge-{version}.app", allowInitialRelease: false)

    static func configure(root: URL) throws {
        let file = root.appendingPathComponent("release-product.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let product = try JSONDecoder().decode(Self.self, from: Data(contentsOf: file))
        let scripts = [product.exportScript, product.releaseScript] + product.testScripts
        guard !product.name.isEmpty, !product.repository.isEmpty,
              scripts.allSatisfy({ !$0.hasPrefix("/") && !$0.split(separator: "/").contains("..") && !$0.contains("\\") }),
              !product.archiveTemplate.hasPrefix("/"), !product.appTemplate.hasPrefix("/"),
              !product.archiveTemplate.split(separator: "/").contains(".."), !product.appTemplate.split(separator: "/").contains("..") else {
            throw NSError(domain: "Release product", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid release product configuration."])
        }
        current = product
    }
    func archive(_ version: String) -> String { archiveTemplate.replacingOccurrences(of: "{version}", with: version) }
    func app(_ version: String) -> String { appTemplate.replacingOccurrences(of: "{version}", with: version) }
    var bundleName: String { name + ".app" }
    var manifestName: String { name + "-manifest.json" }
}
