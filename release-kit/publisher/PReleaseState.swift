import Foundation

struct PublishedRelease {
    static var repository: String { PublisherProduct.current.repository }
    static var feed: String { "https://api.github.com/repos/\(repository)/releases/latest" }
    let version: String
    let tag: String
    let fingerprint: String
    let commit: String
    let tree: String
    let baseline: String
    let page: String
    let archiveSHA256: String?
    let archiveName: String

    static func latest() throws -> PublishedRelease {
        let answer = try Command.attempt("gh", ["api", "repos/\(repository)/releases/latest"], quiet: true)
        if answer.status != 0 {
            let error = (try? jsonObject(answer.output)) ?? [:]
            guard PublisherProduct.current.allowInitialRelease, error["status"] as? String == "404" || error["status"] as? Int == 404 else {
                throw PublisherError("The latest public release could not be verified.")
            }
            let head = try jsonObject(Command.run("gh", ["api", "repos/\(repository)/commits/main"], quiet: true))
            guard let commit = head["sha"] as? String, isObjectID(commit),
                  let tree = ((head["commit"] as? [String: Any])?["tree"] as? [String: Any])?["sha"] as? String, isObjectID(tree) else {
                throw PublisherError("The initial public source baseline could not be verified.")
            }
            return PublishedRelease(version: "0.0.0", tag: "", fingerprint: String(repeating: "0", count: 64), commit: commit,
                tree: tree, baseline: "unreleased:" + commit, page: "https://github.com/\(repository)", archiveSHA256: nil, archiveName: "")
        }
        let release = try jsonObject(answer.output)
        guard let tag = release["tag_name"] as? String, safeIdentifier(tag),
              let id = release["id"] as? Int,
              let page = release["html_url"] as? String,
              release["draft"] as? Bool == false, release["prerelease"] as? Bool == false else {
            throw PublisherError("The latest public release could not be verified.")
        }
        let version = String(tag.hasPrefix("v") ? tag.dropFirst() : Substring(tag))
        _ = try VersionNumber(version)
        // Asked by tag name, GitHub's trees endpoint answers with the tagged *commit's* id in "sha".
        // Resolve the commit and its real tree explicitly, then list that tree by its own id.
        let tagged = try jsonObject(Command.run("gh", ["api", "repos/\(repository)/commits/\(tag)"], quiet: true))
        guard let commitSHA = tagged["sha"] as? String, isObjectID(commitSHA),
              let treeSHA = ((tagged["commit"] as? [String: Any])?["tree"] as? [String: Any])?["sha"] as? String,
              isObjectID(treeSHA) else { throw PublisherError("The public release's source commit could not be read.") }
        let tree = try jsonObject(Command.run("gh", ["api", "repos/\(repository)/git/trees/\(treeSHA)?recursive=1"], quiet: true))
        guard tree["truncated"] as? Bool == false, tree["sha"] as? String == treeSHA,
              let entries = tree["tree"] as? [[String: Any]] else { throw PublisherError("The public source listing was incomplete.") }
        var blobs: [String: String] = [:]
        for entry in entries {
            guard let path = entry["path"] as? String, ContentIdentity.included(path) else { continue }
            guard entry["type"] as? String == "blob", entry["mode"] as? String != "120000",
                  let sha = entry["sha"] as? String else { throw PublisherError("A public build input was not a regular file.") }
            blobs[path] = sha
        }
        // Download counts are activity, not a competing release.
        let assets = (release["assets"] as? [[String: Any]] ?? []).map { asset in
            asset.filter { ["id", "name", "size", "digest", "updated_at"].contains($0.key) }
        }
        let baselineData: [String: Any] = ["release": id, "tag": tag, "commit": commitSHA, "tree": treeSHA,
                                         "publishedAt": release["published_at"] ?? "", "assets": assets]
        let baseline = ContentIdentity.sha256(try JSONSerialization.data(withJSONObject: baselineData, options: [.sortedKeys]))
        let releaseAssets = release["assets"] as? [[String: Any]] ?? []
        let archives = releaseAssets.filter { ($0["name"] as? String ?? "").hasPrefix(PublisherProduct.current.name) && ($0["name"] as? String ?? "").hasSuffix(".zip") }
        guard archives.count == 1, let archive = archives.first, (archive["size"] as? Int ?? 0) > 0 else {
            throw PublisherError("The public release must have exactly one complete app archive.")
        }
        let archiveDigest = archive["digest"] as? String
        let fingerprint = try ContentIdentity.fingerprint(blobs)
        if releaseAssets.contains(where: { $0["name"] as? String == PublisherProduct.current.manifestName }) {
            let manifest = try jsonObject(Command.run("gh", ["release", "download", tag, "--repo", repository,
                                                            "--pattern", PublisherProduct.current.manifestName, "--output", "-"], quiet: true))
            guard manifest["schema"] as? Int == 1, manifest["algorithm"] as? String == ContentIdentity.algorithm,
                  manifest["version"] as? String == version, manifest["fingerprint"] as? String == fingerprint,
                  let digest = manifest["archiveSHA256"] as? String, validFingerprint(digest),
                  archiveDigest == "sha256:\(digest)", archive["name"] as? String == URL(fileURLWithPath: PublisherProduct.current.archive(version)).lastPathComponent else {
                throw PublisherError("The public release manifest, source and app archive do not agree.")
            }
        } else {
            guard ["v2.0.0", "v2.1.0", "v2.3.0"].contains(tag) else {
                throw PublisherError("The public release has no content manifest. A match cannot be established.")
            }
        }
        return PublishedRelease(version: version, tag: tag, fingerprint: fingerprint,
                                commit: commitSHA, tree: treeSHA, baseline: baseline, page: page,
                                archiveSHA256: archiveDigest?.hasPrefix("sha256:") == true ? String(archiveDigest!.dropFirst(7)) : nil,
                                archiveName: archive["name"] as! String)
    }

    var json: [String: Any] {
        ["latestVersion": version, "latestFingerprint": fingerprint, "releaseURL": page, "baseline": baseline]
    }
}

struct VersionNumber: Comparable {
    let parts: [Int]
    init(_ text: String) throws {
        let values = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(values.count), values.allSatisfy({ !$0.isEmpty && $0.count <= 8 && $0.allSatisfy(\.isNumber) }),
              values.allSatisfy({ Int($0) != nil }) else { throw PublisherError("Version numbers must contain two or three numeric parts.") }
        parts = values.map { Int($0)! } + (values.count == 2 ? [0] : [])
    }
    static func < (left: Self, right: Self) -> Bool { left.parts.lexicographicallyPrecedes(right.parts) }
    var description: String { parts.map(String.init).joined(separator: ".") }
    var nextPatch: String { "\(parts[0]).\(parts[1]).\(parts[2] + 1)" }
}

func sourceStatus(root: URL, running: String) -> [String: Any] {
    do {
        let local = try ContentIdentity.local(root)
        let latest = try PublishedRelease.latest()
        var value = latest.json
        value["runningFingerprint"] = running
        value["sourceMatchesRunning"] = local == running
        // Equality answers what is running. Unbuilt edits do not make the running copy different.
        value["kind"] = latest.fingerprint == running ? "equal" : (local == running ? "different" : "rebuildRequired")
        if local != running { value["message"] = "The source changed after this app was built. Rebuild and try it before preparing a release." }
        return value
    } catch {
        return ["kind": "unknown", "message": "The published version could not be checked. No match has been established.",
                "sourceMatchesRunning": (try? ContentIdentity.local(root)) == running]
    }
}

/// A full 40-hex Git object id, as GitHub reports commits and trees.
func isObjectID(_ value: String) -> Bool { value.count == 40 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase } }
