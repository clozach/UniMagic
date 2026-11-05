import Foundation

extension Candidate {
    /// Publication never invokes test/build/export scripts: only the approved frozen bytes.
    func publish(root: URL, running: String, approvedDigest: String, approvedReceipt: String) throws -> [String: Any] {
        try verify(running: running, approvedDigest: approvedDigest, approvedReceipt: approvedReceipt)
        Command.logPath = folder.appendingPathComponent("publication.log")
        Telemetry.begin("release-status")
        let latest = try PublishedRelease.latest()
        if latest.tag == "v\(version)", latest.fingerprint == running {
            guard latest.archiveSHA256 == approvedDigest else {
                throw PublisherError("That version is already public with different or unverified archive bytes. Nothing was overwritten.")
            }
            return publishedResult(latest, digest: approvedDigest)
        }
        guard let preparedBaseline = record["baseline"] as? String else { throw PublisherError("The candidate has no publication baseline.") }
        let isInitial = PublisherProduct.current.allowInitialRelease && latest.tag.isEmpty &&
            preparedBaseline.hasPrefix("unreleased:") && isObjectID(String(preparedBaseline.dropFirst("unreleased:".count)))
        // Only an initial resume may provisionally cross a changed main baseline;
        // the clone/tag/frozen-tree proof below must then establish its ownership.
        guard latest.baseline == preparedBaseline || isInitial else {
            throw PublisherError("The public release changed after this candidate was prepared. Prepare and review a fresh candidate.", recovery: "prepare")
        }
        let tag = "v\(version)"
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("clipedge-publish-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        Telemetry.begin("clone")
        let previousHead = try PublicSource.clone(into: work)
        guard let sourceDigest = record["sourceDigest"] as? String else { throw PublisherError("The frozen candidate receipt is incomplete.") }
        let headTree = try Command.text("git", ["rev-parse", "HEAD^{tree}"], at: work)
        let isResuming = try Candidate.treeDigest(work) == sourceDigest && matchesFrozenGitTree(at: work)
        let tagged = try PublicSource.tagged(tag, at: work)
        if isResuming {
            guard let tagged, tagged == previousHead else {
                if let tagged { try PublicSource.refuseInterrupted(tag, tagged: tagged, head: previousHead, at: work) }
                throw PublisherError("The existing candidate tag does not match its frozen source. Nothing was changed.")
            }
            if isInitial {
                let ancestry = try Command.text("git", ["rev-list", "--parents", "-n", "1", "HEAD"], at: work)
                    .split(separator: " ").map(String.init)
                let message = try Command.text("git", ["log", "-1", "--format=%B"], at: work)
                guard ancestry == [previousHead, String(preparedBaseline.dropFirst("unreleased:".count))],
                      message == "\(PublisherProduct.current.name) \(version)" else {
                    throw PublisherError("The public source is not this initial publication's single owned source commit.", recovery: "prepare")
                }
            }
            let baselineMatches = latest.baseline == preparedBaseline ? true :
                try latest.matchesInitialCandidate(preparedBaseline: preparedBaseline, tag: tag, commit: previousHead, tree: headTree)
            guard baselineMatches else {
                throw PublisherError("The public source changed after preparation; it is not this frozen initial candidate.", recovery: "prepare")
            }
            Command.log("Resuming this exact candidate after its source was pushed.")
        } else {
        guard latest.baseline == preparedBaseline else {
            throw PublisherError("The public source changed after preparation; it is not this frozen initial candidate.", recovery: "prepare")
        }
        // Only a resume may find this version's tag already public; anything else is an interrupted publish.
        if let tagged { try PublicSource.refuseInterrupted(tag, tagged: tagged, head: previousHead, at: work) }
        Telemetry.begin("stage")
        // The commit sits on the current public HEAD, so contributor commits stay in history.
        try PublicSource.stage(source, into: work, sourceDigest: sourceDigest)
        try Command.run("git", ["commit", "--quiet", "-m", "\(PublisherProduct.current.name) \(version)"], at: work)
        try PublicSource.requireContained(candidate: "HEAD", head: previousHead, release: latest, at: work)
        try Command.run("git", ["tag", tag], at: work)
        try verify(running: running, approvedDigest: approvedDigest, approvedReceipt: approvedReceipt)
        guard try PublishedRelease.latest().baseline == latest.baseline else {
            throw PublisherError("Another release appeared. Nothing was pushed; prepare a fresh candidate.", recovery: "prepare")
        }
        Telemetry.begin("push")
        Command.log("Publishing the approved frozen \(PublisherProduct.current.name) \(version) candidate.")
        try Command.run("git", ["push", "--atomic", "--force-with-lease=refs/heads/main:\(previousHead)", "origin",
                                 "HEAD:refs/heads/main", "refs/tags/\(tag):refs/tags/\(tag)"], at: work)
        }
        let pushedCommit = try Command.text("git", ["rev-parse", "HEAD"], at: work)
        let pushedTree = try Command.text("git", ["rev-parse", "HEAD^{tree}"], at: work)
        // A draft stays out of the latest-release feed until all assets are attached.
        Telemetry.begin("upload")
        let existing = try? jsonObject(Command.run("gh", ["api", "repos/\(PublishedRelease.repository)/releases/tags/\(tag)"], quiet: true))
        if let existing {
            guard existing["draft"] as? Bool == true else {
                throw PublisherError("A public release already uses this candidate's version. Nothing was overwritten.")
            }
            let extraArchives = (existing["assets"] as? [[String: Any]] ?? []).filter {
                let name = $0["name"] as? String ?? ""
                return name.hasPrefix(PublisherProduct.current.name) && name.hasSuffix(".zip") && name != archive.lastPathComponent
            }
            guard extraArchives.isEmpty else { throw PublisherError("The draft contains an unexpected app archive. Review that draft before publishing; no public release was changed.") }
            try Command.run("gh", ["release", "upload", tag, archive.path, folder.appendingPathComponent("SHA256SUMS").path,
                                   folder.appendingPathComponent(PublisherProduct.current.manifestName).path, "--repo", PublishedRelease.repository, "--clobber"])
        } else {
        try Command.run("gh", ["release", "create", tag, archive.path, folder.appendingPathComponent("SHA256SUMS").path,
                                folder.appendingPathComponent(PublisherProduct.current.manifestName).path, "--repo", PublishedRelease.repository,
                                "--verify-tag", "--draft", "--title", "\(PublisherProduct.current.name) \(version)",
                                "--notes-file", folder.appendingPathComponent("notes.md").path])
        }
        Telemetry.begin("release")
        try verify(running: running, approvedDigest: approvedDigest, approvedReceipt: approvedReceipt)
        let beforeRelease = try PublishedRelease.latest()
        let unchanged: Bool
        if isInitial {
            unchanged = try beforeRelease.matchesInitialCandidate(preparedBaseline: preparedBaseline, tag: tag,
                                                                  commit: pushedCommit, tree: pushedTree)
        } else { unchanged = beforeRelease.baseline == latest.baseline }
        guard unchanged else {
            throw PublisherError("Another release or source advance appeared. This candidate remains a draft and was not offered as an automatic update.")
        }
        try Command.run("gh", ["release", "edit", tag, "--repo", PublishedRelease.repository, "--draft=false", "--latest",
                                "--title", "\(PublisherProduct.current.name) \(version)", "--notes-file", folder.appendingPathComponent("notes.md").path])
        Telemetry.begin("confirm")
        let confirmed: PublishedRelease
        do { confirmed = try PublishedRelease.latest() }
        catch { throw PublisherError("Publishing completed, but the public result could not be checked. Recheck status before trying to publish again.") }
        guard confirmed.tag == tag, confirmed.fingerprint == running, confirmed.archiveSHA256 == approvedDigest else {
            throw PublisherError("The public result did not match the approved candidate. Recheck the release before taking another action.")
        }
        return publishedResult(confirmed, digest: approvedDigest)
    }

    /// treeDigest omits hidden build state by design. A resume additionally
    /// compares EVERY tracked git path, mode and blob so hidden/contributor files
    /// cannot make a different commit masquerade as the frozen candidate.
    private func matchesFrozenGitTree(at work: URL) throws -> Bool {
        var expected: [String: String] = [:]
        var files = try ContentIdentity.files(at: source)
        let ignore = source.appendingPathComponent(".gitignore")
        if FileManager.default.fileExists(atPath: ignore.path) { files[".gitignore"] = ignore }
        for (path, file) in files {
            let permissions = (try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
            let mode = permissions & 0o111 == 0 ? "100644" : "100755"
            expected[path] = mode + " blob " + ContentIdentity.blob(try Data(contentsOf: file))
        }
        let listing = try Command.run("git", ["ls-tree", "-r", "-z", "--full-tree", "HEAD"], at: work)
        var actual: [String: String] = [:]
        for record in String(decoding: listing, as: UTF8.self).split(separator: "\0") {
            let parts = record.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return false }
            actual[String(parts[1])] = String(parts[0])
        }
        return actual == expected
    }

    private func publishedResult(_ release: PublishedRelease, digest: String) -> [String: Any] {
        var result = release.json
        result["kind"] = "published"
        result["candidate"] = id
        result["archiveSHA256"] = digest
        return result
    }
}
