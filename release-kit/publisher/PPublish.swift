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
        guard latest.baseline == record["baseline"] as? String else {
            throw PublisherError("The public release changed after this candidate was prepared. Prepare and review a fresh candidate.", recovery: "prepare")
        }
        let tag = "v\(version)"
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("clipedge-publish-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        Telemetry.begin("clone")
        let previousHead = try PublicSource.clone(into: work)
        guard let sourceDigest = record["sourceDigest"] as? String else { throw PublisherError("The frozen candidate receipt is incomplete.") }
        let isResuming = try Candidate.treeDigest(work) == sourceDigest
        let tagged = try PublicSource.tagged(tag, at: work)
        if isResuming {
            guard let tagged, tagged == previousHead else {
                if let tagged { try PublicSource.refuseInterrupted(tag, tagged: tagged, head: previousHead, at: work) }
                throw PublisherError("The existing candidate tag does not match its frozen source. Nothing was changed.")
            }
            Command.log("Resuming this exact candidate after its source was pushed.")
        } else {
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
        // A draft stays out of Mom's latest-release feed until all assets are attached.
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
        guard try PublishedRelease.latest().baseline == latest.baseline else {
            throw PublisherError("Another release appeared. This candidate remains a draft and was not offered as an automatic update.")
        }
        Telemetry.begin("release")
        try verify(running: running, approvedDigest: approvedDigest, approvedReceipt: approvedReceipt)
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

    private func publishedResult(_ release: PublishedRelease, digest: String) -> [String: Any] {
        var result = release.json
        result["kind"] = "published"
        result["candidate"] = id
        result["archiveSHA256"] = digest
        return result
    }
}
