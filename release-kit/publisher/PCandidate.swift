import Foundation

struct Candidate {
    let folder: URL
    let record: [String: Any]

    var id: String { record["candidate"] as! String }
    var version: String { record["version"] as! String }
    var fingerprint: String { record["fingerprint"] as! String }
    var archiveSHA256: String { record["archiveSHA256"] as! String }
    var archive: URL { folder.appendingPathComponent(URL(fileURLWithPath: PublisherProduct.current.archive(version)).lastPathComponent) }
    var source: URL { folder.appendingPathComponent("source") }
    var app: URL { folder.appendingPathComponent(PublisherProduct.current.bundleName) }
    var manifest: URL { folder.appendingPathComponent("candidate.json") }

    var json: [String: Any] {
        ["kind": "ready", "candidate": id, "version": version, "fingerprint": fingerprint,
         "archiveSHA256": archiveSHA256, "changes": record["changes"]!, "previousVersion": record["previousVersion"]!,
         "appPath": app.path, "candidateManifest": manifest.path, "receiptSHA256": (try? digest(manifest)) ?? ""]
    }

    static func load(_ id: String, under root: URL, approvedReceipt: String) throws -> Candidate {
        guard safeIdentifier(id) else { throw PublisherError("The candidate identifier is invalid.") }
        let folder = root.appendingPathComponent(".build/publish-candidates/\(id)")
        guard try digest(folder.appendingPathComponent("candidate.json")) == approvedReceipt else {
            throw PublisherError("The candidate receipt changed after review. Prepare and review a fresh candidate.", recovery: "prepare")
        }
        let record = try jsonObject(Data(contentsOf: folder.appendingPathComponent("candidate.json")))
        for key in ["candidate", "version", "fingerprint", "archiveSHA256", "changes", "previousVersion", "baseline", "sourceDigest", "appDigest", "manifestDigest", "notesDigest", "signerRequirement"] {
            guard record[key] is String else { throw PublisherError("The frozen candidate receipt is incomplete.") }
        }
        guard record["candidate"] as? String == id, safeIdentifier(record["version"] as! String) else { throw PublisherError("The candidate receipt does not match its folder.") }
        return Candidate(folder: folder, record: record)
    }

    /// Full frozen tree integrity includes docs and tests, unlike the runtime content identity.
    static func treeDigest(_ root: URL) throws -> String {
        var entries = try ContentIdentity.files(at: root)
        let ignored = root.appendingPathComponent(".gitignore")
        if FileManager.default.fileExists(atPath: ignored.path) { entries[".gitignore"] = ignored }
        let text = try entries.keys.sorted().map { "\($0)\t\(try digest(entries[$0]!))\n" }.joined()
        return ContentIdentity.sha256(Data(text.utf8))
    }

    static func prepare(root: URL, running: String) throws -> Candidate {
        guard try ContentIdentity.local(root) == running else {
            throw PublisherError("The source changed after this app was built. Rebuild and try it before preparing a release.")
        }
        let latest = try PublishedRelease.latest()
        guard latest.fingerprint != running else { throw PublisherError("This running app already matches the latest published content.") }
        let current = try VersionNumber(String(contentsOf: root.appendingPathComponent("VERSION"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines))
        let prior = try VersionNumber(latest.version)
        let version = current > prior ? current.description : prior.nextPatch
        let changes = try releaseNotes(root: root, version: version)
        Telemetry.begin("freeze")
        let id = "\(version)-\(UUID().uuidString.lowercased())"
        let folder = root.appendingPathComponent(".build/publish-candidates/\(id)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let snapshot = folder.appendingPathComponent("source")
        Command.logPath = folder.appendingPathComponent("checks-and-build.log")
        Command.log("Freezing \(PublisherProduct.current.name) \(version). Nothing is being published.")
        try Command.run("/bin/bash", [PublisherProduct.current.exportScript, snapshot.path], at: root)
        guard try ContentIdentity.local(snapshot) == running else { throw PublisherError("The source changed while it was being frozen. Rebuild and prepare again.") }
        try (version + "\n").write(to: snapshot.appendingPathComponent("VERSION"), atomically: true, encoding: .utf8)
        let oldNotes = try String(contentsOf: snapshot.appendingPathComponent("CHANGES.md"), encoding: .utf8)
        let publishedNotes = oldNotes.replacingOccurrences(of: "## Unreleased", with: "## \(version)")
        try publishedNotes.write(to: snapshot.appendingPathComponent("CHANGES.md"), atomically: true, encoding: .utf8)
        let sourceDigest = try treeDigest(snapshot)
        // Reuse needs the exact frozen bytes, not only the runtime identity: a candidate missing a
        // documentation fix would otherwise be reused, and refused by publication, indefinitely.
        if let existing = reusable(root: root, running: running, latest: latest, version: version, changes: changes, sourceDigest: sourceDigest) {
            Command.logPath = nil
            try? FileManager.default.removeItem(at: folder)
            // Public main can gain commits without a release, which the reuse test cannot see.
            Telemetry.begin("public-source")
            Command.log("Checking that the reused candidate contains every public change since \(latest.tag).")
            try PublicSource.checkEarly(existing.source, sourceDigest: sourceDigest, release: latest, tag: "v\(version)")
            Command.log("Reusing the tested frozen candidate. Publishing still requires your explicit approval.")
            return existing
        }
        Telemetry.begin("public-source")
        Command.log("Checking that the candidate contains every public change since \(latest.tag).")
        try PublicSource.checkEarly(snapshot, sourceDigest: sourceDigest, release: latest, tag: "v\(version)")
        let testLog = folder.appendingPathComponent("tests.log")
        // The GUI remains running while preparing. Give every fixture its own
        // temporary preview directory instead of clearing the live app's cache.
        let testRuntime = snapshot.appendingPathComponent(".build/test-runtime", isDirectory: true)
        try FileManager.default.createDirectory(at: testRuntime, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var log = Data()
        for (index, test) in PublisherProduct.current.testScripts.enumerated() {
            let step = ["test-core", "test-install", "test-update"][min(index, 2)]
            Telemetry.begin(step)
            Command.log("Checking frozen candidate: \(test)")
            log.append(try Command.run("/usr/bin/env", ["TMPDIR=" + testRuntime.path + "/", "CLIPEDGE_TEST_PREVIEW_ROOT=" + testRuntime.path, "/bin/bash", test], at: snapshot))
        }
        try log.write(to: testLog)
        guard try treeDigest(snapshot) == sourceDigest else { throw PublisherError("A check changed the frozen source. Prepare again after fixing the check.") }
        Telemetry.begin("build")
        Command.log("Building the signed release once.")
        try Command.run("/usr/bin/env", ["CLIPEDGE_UPDATE_FEED=\(PublishedRelease.feed)", "RELEASE_KIT_UPDATE_FEED=\(PublishedRelease.feed)", "/bin/bash", PublisherProduct.current.releaseScript], at: snapshot)
        guard try treeDigest(snapshot) == sourceDigest else { throw PublisherError("The build changed the frozen source. Nothing was published.") }
        Telemetry.begin("verify-app")
        let name = URL(fileURLWithPath: PublisherProduct.current.archive(version)).lastPathComponent
        let archive = folder.appendingPathComponent(name)
        try FileManager.default.copyItem(at: snapshot.appendingPathComponent(".build/releases/\(name)"), to: archive)
        try FileManager.default.copyItem(at: snapshot.appendingPathComponent(PublisherProduct.current.app(version)), to: folder.appendingPathComponent(PublisherProduct.current.bundleName))
        let app = folder.appendingPathComponent(PublisherProduct.current.bundleName)
        try validateApp(app, version: version, fingerprint: running)
        let unpacked = folder.appendingPathComponent("archive-check")
        try checkArchivePaths(archive)
        try Command.run("ditto", ["--norsrc", "-x", "-k", archive.path, unpacked.path])
        try validateApp(unpacked.appendingPathComponent(PublisherProduct.current.bundleName), version: version, fingerprint: running)
        guard try treeDigest(unpacked.appendingPathComponent(PublisherProduct.current.bundleName)) == treeDigest(app) else {
            throw PublisherError("The release archive and review app differ. Nothing was published.")
        }
        try FileManager.default.removeItem(at: unpacked)
        Telemetry.begin("prior-signer")
        let signer = try checkPriorSigner(latest: latest, candidateApp: app, folder: folder)
        Telemetry.begin("receipt")
        let archiveDigest = try digest(archive)
        try "\(archiveDigest)  \(name)\n".write(to: folder.appendingPathComponent("SHA256SUMS"), atomically: true, encoding: .utf8)
        try changes.write(to: folder.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        let publicManifest: [String: Any] = ["schema": 1, "algorithm": ContentIdentity.algorithm, "version": version,
                                            "fingerprint": running, "archiveSHA256": archiveDigest, "sourceDigest": sourceDigest]
        try writeJSON(publicManifest, to: folder.appendingPathComponent(PublisherProduct.current.manifestName))
        let record: [String: Any] = ["candidate": id, "version": version, "fingerprint": running, "archiveSHA256": archiveDigest,
                                    "changes": changes, "previousVersion": latest.version, "baseline": latest.baseline,
                                    "sourceDigest": sourceDigest, "appDigest": try treeDigest(app),
                                    "signerRequirement": signer,
                                    "manifestDigest": try digest(folder.appendingPathComponent(PublisherProduct.current.manifestName)),
                                    "notesDigest": try digest(folder.appendingPathComponent("notes.md"))]
        try writeJSON(record, to: folder.appendingPathComponent("candidate.json"))
        return Candidate(folder: folder, record: record)
    }

    func verify(running: String, approvedDigest: String, approvedReceipt: String) throws {
        guard try digest(manifest) == approvedReceipt else { throw PublisherError("The candidate receipt changed after review. Nothing was published.", recovery: "prepare") }
        guard fingerprint == running else { throw PublisherError("This candidate belongs to a different running build. Prepare the app you are using.") }
        guard archiveSHA256 == approvedDigest, try digest(archive) == approvedDigest,
              try String(contentsOf: folder.appendingPathComponent("SHA256SUMS"), encoding: .utf8) == "\(approvedDigest)  \(archive.lastPathComponent)\n",
              try Self.treeDigest(source) == record["sourceDigest"] as? String,
              try Self.treeDigest(app) == record["appDigest"] as? String,
              try digest(folder.appendingPathComponent(PublisherProduct.current.manifestName)) == record["manifestDigest"] as? String,
              try digest(folder.appendingPathComponent("notes.md")) == record["notesDigest"] as? String,
              try ContentIdentity.local(source) == running else { throw PublisherError("The frozen candidate changed after preparation. It cannot be published; prepare a new one.", recovery: "prepare") }
        try Self.validateApp(app, version: version, fingerprint: running)
        guard let signer = record["signerRequirement"] as? String else { throw PublisherError("The candidate has no verified prior signer.") }
        try Command.run("codesign", ["--verify", "--strict", "--all-architectures", "-R", "=" + signer, app.path], quiet: true)
    }

    static func validateApp(_ app: URL, version: String, fingerprint: String) throws {
        guard let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == PublisherProduct.current.bundleIdentifier,
              info["CFBundleShortVersionString"] as? String == version,
              info[PublisherProduct.current.infoPrefix + "ContentFingerprint"] as? String == fingerprint,
              info[PublisherProduct.current.infoPrefix + "UpdateFeed"] as? String == PublishedRelease.feed,
              info[PublisherProduct.current.infoPrefix + "PublisherEnabled"] == nil, info[PublisherProduct.current.infoPrefix + "PublisherTool"] == nil else {
            throw PublisherError("The candidate's app identity or release settings did not match the frozen source.")
        }
        try Command.run("codesign", ["--verify", "--strict", app.path], quiet: true)
    }

    static func releaseNotes(root: URL, version: String) throws -> String {
        let lines = try String(contentsOf: root.appendingPathComponent("CHANGES.md"), encoding: .utf8).components(separatedBy: "\n")
        for heading in ["## \(version)", "## Unreleased"] {
            guard let start = lines.firstIndex(of: heading) else { continue }
            let content = lines.dropFirst(start + 1).prefix { !$0.hasPrefix("## ") }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { continue }
            // Refused here, before any testing or building, rather than by the app after both.
            guard content.count <= PublishLimits.releaseNotes, content.utf8.count <= PublishLimits.releaseNoteBytes else {
                throw PublisherError("The release notes under '\(heading)' in CHANGES.md are \(PublishLimits.counted(content.count)) characters; a release can carry at most \(PublishLimits.counted(PublishLimits.releaseNotes)). Shorten them before preparing.")
            }
            return content
        }
        throw PublisherError("Add release notes under '## Unreleased' in CHANGES.md before preparing this candidate.")
    }

    private static func checkPriorSigner(latest: PublishedRelease, candidateApp: URL, folder: URL) throws -> String {
        if latest.tag.isEmpty {
            guard PublisherProduct.current.allowInitialRelease else { throw PublisherError("Initial publication is not configured.") }
            try Command.run("codesign", ["--verify", "--strict", candidateApp.path], quiet: true)
            let description = try Command.text("/bin/bash", ["-c", "codesign -d -vv -r- \"$1\" 2>&1", "codesign", candidateApp.path], quiet: true)
            guard let line = description.components(separatedBy: "\n").first(where: { $0.hasPrefix("designated => ") }),
                  !description.contains("Signature=adhoc"), description.contains("Authority=") else { throw PublisherError("The initial release requires a stable signing certificate.") }
            return String(line.dropFirst("designated => ".count))
        }
        guard let expected = latest.archiveSHA256, validFingerprint(expected) else {
            throw PublisherError("The preceding release's archive digest is unavailable; its signing identity could not be verified.")
        }
        let archive = folder.appendingPathComponent("previous-release.zip")
        try Command.run("gh", ["release", "download", latest.tag, "--repo", PublishedRelease.repository,
                                "--pattern", latest.archiveName, "--output", archive.path], quiet: true)
        guard try digest(archive) == expected else { throw PublisherError("The preceding release download failed its integrity check.") }
        let unpacked = folder.appendingPathComponent("previous-release")
        defer { try? FileManager.default.removeItem(at: archive); try? FileManager.default.removeItem(at: unpacked) }
        try checkArchivePaths(archive)
        try Command.run("ditto", ["--norsrc", "-x", "-k", archive.path, unpacked.path])
        let previousApp = unpacked.appendingPathComponent(PublisherProduct.current.bundleName)
        try Command.run("codesign", ["--verify", "--strict", previousApp.path], quiet: true)
        let description = try Command.text("/bin/bash", ["-c", "codesign -d -vv -r- \"$1\" 2>&1", "codesign", previousApp.path], quiet: true)
        guard let line = description.components(separatedBy: "\n").first(where: { $0.hasPrefix("designated => ") }) else {
            throw PublisherError("The preceding release's signing requirement could not be read.")
        }
        let requirement = String(line.dropFirst("designated => ".count))
        do { try Command.run("codesign", ["--verify", "--strict", "--all-architectures", "-R", "=" + requirement, candidateApp.path], quiet: true) }
        catch { throw PublisherError("The candidate is not signed by the preceding release's developer. It would be refused by existing copies, so publication was stopped.") }
        return requirement
    }

    static func checkArchivePaths(_ archive: URL) throws {
        let bytes = try Data(contentsOf: archive, options: .mappedIfSafe)
        guard bytes.count <= UpdateFeed.archiveLimit else { throw PublisherError("The archive exceeds the compressed download limit.") }
        do { try UpdateArchiveValidation.validate(bytes, bundleName: PublisherProduct.current.bundleName) }
        catch { throw PublisherError("The archive failed pre-extraction safety checks: \(error)") }
    }

    private static func reusable(root: URL, running: String, latest: PublishedRelease, version: String, changes: String, sourceDigest: String) -> Candidate? {
        let directory = root.appendingPathComponent(".build/publish-candidates")
        let candidates = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for folder in candidates.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let receipt = try? digest(folder.appendingPathComponent("candidate.json")),
                  let candidate = try? load(folder.lastPathComponent, under: root, approvedReceipt: receipt),
                  candidate.version == version, candidate.fingerprint == running,
                  candidate.record["sourceDigest"] as? String == sourceDigest,
                  candidate.record["baseline"] as? String == latest.baseline,
                  candidate.record["changes"] as? String == changes else { continue }
            do {
                try candidate.verify(running: running, approvedDigest: candidate.archiveSHA256, approvedReceipt: receipt)
                return candidate
            } catch { continue }
        }
        return nil
    }
}
