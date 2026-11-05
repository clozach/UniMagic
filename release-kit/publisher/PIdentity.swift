import Foundation
import CryptoKit
import Darwin

/// Content identity is independent of the release label, local paths, documentation and tests.
/// Git's blob hashes let the same recipe read an older public tag that has no build manifest.
enum ContentIdentity {
    static var algorithm: String { PublisherProduct.current.identityAlgorithm }

    static func included(_ path: String) -> Bool {
        if !path.contains("/") && path.hasSuffix(".swift") { return true }
        let product = PublisherProduct.current
        return product.identityExact.contains(path) || product.identityPrefixes.contains { path.hasPrefix($0) }
    }

    static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    static func blob(_ data: Data) -> String {
        let header = Data("blob \(data.count)\0".utf8)
        return Insecure.SHA1.hash(data: header + data).map { String(format: "%02x", $0) }.joined()
    }

    static func fingerprint(_ blobs: [String: String]) throws -> String {
        let selected = blobs.filter { included($0.key) }
        guard !selected.isEmpty, PublisherProduct.current.name != "ClipEdge" || (selected.keys.contains(where: { !$0.contains("/") && $0.hasSuffix(".swift") }) && selected["tools/build.sh"] != nil) else { throw IdentityError.incomplete }
        let record = selected.keys.sorted().map { "\($0)\t\(selected[$0]!)\n" }.joined()
        return sha256(Data((algorithm + "\n" + record).utf8))
    }

    static func files(at root: URL, excludingBuild: Bool = true) throws -> [String: URL] {
        guard let canonical = realpath(root.path, nil) else { throw IdentityError.incomplete }
        defer { free(canonical) }
        let root = URL(fileURLWithPath: String(cString: canonical), isDirectory: true)
        let manager = FileManager.default
        guard let iterator = manager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                                                 options: [.skipsHiddenFiles]) else { throw IdentityError.incomplete }
        var result: [String: URL] = [:]
        for case let file as URL in iterator {
            let relative = String(file.path.dropFirst(root.path.count + 1))
            if (PublisherProduct.current.excludePrefixes ?? []).contains(where: { relative == $0 || relative.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }) {
                iterator.skipDescendants(); continue
            }
            let normalized = file
            guard normalized.path.hasPrefix(root.path + "/") else { throw IdentityError.incomplete }
            if excludingBuild && (relative == ".build" || relative.hasPrefix(".build/")) { iterator.skipDescendants(); continue }
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { throw IdentityError.symlink(relative) }
            if values.isRegularFile == true { result[relative] = normalized }
        }
        // Canonical builds compile the shared kit; exports freeze those exact files
        // under their portable root names, yielding the identical content identity.
        let shared = root.appendingPathComponent("../../unimagic/src/release-kit").standardizedFileURL
        if PublisherProduct.current.name == "ClipEdge", FileManager.default.fileExists(atPath: shared.appendingPathComponent("RKReleaseConfiguration.swift").path) {
            for file in try manager.contentsOfDirectory(at: shared, includingPropertiesForKeys: nil) where file.pathExtension == "swift" {
                result[String(file.lastPathComponent.dropFirst(2))] = file
            }
            let publisher = shared.appendingPathComponent("publisher")
            for file in try manager.contentsOfDirectory(at: publisher, includingPropertiesForKeys: nil) where file.pathExtension == "swift" {
                let name = file.lastPathComponent == "ProductSpec.swift" ? file.lastPathComponent : String(file.lastPathComponent.dropFirst())
                result["tools/publisher/" + name] = file
            }
        }
        if manager.fileExists(atPath: root.appendingPathComponent("release-product.json").path) {
            for (relative, fallback) in PublisherProduct.current.sourceMappings ?? [:] {
                guard !relative.hasPrefix("/"), !relative.split(separator: "/").contains(".."), !fallback.hasPrefix("/") else { throw IdentityError.incomplete }
                let exported = root.appendingPathComponent(relative)
                guard !manager.fileExists(atPath: exported.path) else { continue }
                let original = root.appendingPathComponent(fallback)
                guard try original.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw IdentityError.symlink(relative) }
                guard let mappedPath = realpath(original.path, nil) else { throw IdentityError.incomplete }
                let source = URL(fileURLWithPath: String(cString: mappedPath))
                free(mappedPath)
                let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw IdentityError.symlink(relative) }
                if values.isRegularFile == true { result[relative] = source; continue }
                guard values.isDirectory == true,
                      let mapped = manager.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { throw IdentityError.incomplete }
                for case let file as URL in mapped {
                    let tail = String(file.path.dropFirst(source.path.count + 1))
                    let virtual = relative + "/" + tail
                    if (PublisherProduct.current.excludePrefixes ?? []).contains(where: { virtual == $0 || virtual.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }) {
                        mapped.skipDescendants(); continue
                    }
                    let attributes = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard attributes.isSymbolicLink != true else { throw IdentityError.symlink(file.path) }
                    if attributes.isRegularFile == true {
                        result[virtual] = file
                    }
                }
            }
        }
        return result
    }

    static func local(_ root: URL) throws -> String {
        var blobs: [String: String] = [:]
        for (path, file) in try files(at: root) where included(path) { blobs[path] = blob(try Data(contentsOf: file)) }
        return try fingerprint(blobs)
    }
}

enum IdentityError: Error, CustomStringConvertible {
    case incomplete
    case symlink(String)
    var description: String {
        switch self {
        case .incomplete: return "The source content could not be identified completely."
        case .symlink(let path): return "Source contains a symbolic link: \(path)."
        }
    }
}
