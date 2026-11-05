import Foundation

/// The public repository is a distribution snapshot; the vault holds the canonical source.
/// Public main may carry commits after the latest release tag (a merged contributor PR), but
/// only when the frozen candidate already contains every change they make, so a release never
/// silently discards public work. Prepare runs this early; publication repeats it authoritatively.
enum PublicSource {
    static var reconcile: String { "Apply them to the \(PublisherProduct.current.name) source in the vault, rebuild, and prepare again." }

    /// Clone public main into a fresh folder and return its HEAD commit.
    static func clone(into work: URL) throws -> String {
        try Command.run("git", ["clone", "--quiet", "https://github.com/\(PublishedRelease.repository).git", work.path])
        return try Command.text("git", ["rev-parse", "HEAD"], at: work)
    }

    /// Replace the clone's tree with the frozen source and check the staged bytes before Git sees them.
    /// Returns the staged tree, ready for `git commit` or `git commit-tree`.
    @discardableResult
    static func stage(_ source: URL, into work: URL, sourceDigest: String) throws -> String {
        try Command.run("git", ["rm", "-rq", "--ignore-unmatch", "."], at: work)
        var files = try ContentIdentity.files(at: source)
        let ignore = source.appendingPathComponent(".gitignore")
        if FileManager.default.fileExists(atPath: ignore.path) { files[".gitignore"] = ignore }
        for (relative, file) in files {
            let destination = work.appendingPathComponent(relative)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: file, to: destination)
        }
        guard try Candidate.treeDigest(work) == sourceDigest else {
            throw PublisherError("The staged public source does not match the frozen candidate.")
        }
        try Command.run("git", ["add", "-A"], at: work)
        return try Command.text("git", ["write-tree"], at: work)
    }

    /// Prepare's read-only check: a throwaway clone and commit, never pushed, so a candidate that
    /// would discard public work is refused in seconds rather than after the slow checks.
    static func checkEarly(_ source: URL, sourceDigest: String, release: PublishedRelease, tag: String) throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("clipedge-public-check-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        let head = try clone(into: work)
        let tree = try stage(source, into: work, sourceDigest: sourceDigest)
        // Publication resumes this version's tag only while public main ends at it with exactly this source.
        if let tagged = try tagged(tag, at: work),
           try tagged != head || Command.text("git", ["rev-parse", "\(head)^{tree}"], at: work) != tree {
            try refuseInterrupted(tag, tagged: tagged, head: head, at: work)
        }
        // Explicit identity: this commit only feeds the merge check, and must not depend on Git config.
        let commit = try Command.text("git", ["-c", "user.name=\(PublisherProduct.current.name) publisher", "-c", "user.email=publisher@clipedge.invalid",
                                              "commit-tree", tree, "-p", head, "-m", "Candidate containment check"], at: work)
        try requireContained(candidate: commit, head: head, release: release, at: work)
    }

    /// Refuse unless public main still descends from the release tag and merging its later commits
    /// into the candidate changes nothing: every public change is already in the candidate.
    static func requireContained(candidate: String, head: String, release: PublishedRelease, at work: URL) throws {
        if release.tag.isEmpty {
            guard head == release.commit else { throw PublisherError("Public main changed while the initial candidate was prepared.", recovery: "prepare") }
            return
        }
        let found = try Command.attempt("git", ["rev-parse", "--verify", "--quiet", "refs/tags/\(release.tag)^{commit}"], at: work, quiet: true)
        let tagCommit = String(decoding: found.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard found.status == 0, tagCommit == release.commit,
              try Command.text("git", ["rev-parse", "\(tagCommit)^{tree}"], at: work) == release.tree else {
            throw PublisherError("The public \(release.tag) tag no longer matches its published release. Nothing was changed.")
        }
        guard try Command.attempt("git", ["merge-base", "--is-ancestor", tagCommit, head], at: work).status == 0 else {
            throw PublisherError("Public main no longer contains the \(release.tag) release; its history was rewritten. Nothing was changed.")
        }
        if tagCommit == head { return }
        let candidateTree = try Command.text("git", ["rev-parse", "\(candidate)^{tree}"], at: work)
        guard try merged(base: tagCommit, ours: candidate, theirs: head, at: work) == candidateTree else {
            let listed = try unreconciled(tag: tagCommit, head: head, candidate: candidate, candidateTree: candidateTree, at: work)
            // This candidate can never be published; only a fresh one can carry the reconciled source.
            throw PublisherError(try refusal(listed: listed, base: tagCommit, candidate: candidate, candidateTree: candidateTree,
                                             head: head, at: work), recovery: "prepare")
        }
    }

    /// The commit a tag names in the clone, or nil when public main has no such tag.
    static func tagged(_ tag: String, at work: URL) throws -> String? {
        let found = try Command.attempt("git", ["rev-parse", "--verify", "--quiet", "refs/tags/\(tag)^{commit}"], at: work, quiet: true)
        let commit = String(decoding: found.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return found.status == 0 && !commit.isEmpty ? commit : nil
    }

    /// An earlier publish pushed this version's tag, then stopped before releasing it. A candidate at
    /// that version cannot be published over the tag, whatever the vault now holds.
    static func refuseInterrupted(_ tag: String, tagged: String, head: String, at work: URL) throws -> Never {
        let place: String
        if tagged == head { place = "on different source" }
        else if try Command.attempt("git", ["merge-base", "--is-ancestor", tagged, head], at: work, quiet: true).status == 0 {
            place = "behind newer public commits"
        } else { place = "outside public main" }
        throw PublisherError("An interrupted publish left the \(tag) tag \(place). Delete that tag and any draft release for it, or raise VERSION, then prepare again.",
                             recovery: "prepare")
    }

    /// Name the paths the candidate lacks: the remedy depends on whether the export can carry them.
    private static func refusal(listed: String, base: String, candidate: String, candidateTree: String,
                                head: String, at work: URL) throws -> String {
        // A conflicted merge still writes a tree, with markers in each conflicted file; a Git failure
        // falls back to every public change since the release.
        let result = try Command.attempt("git", ["merge-tree", "--write-tree", "--no-messages", "--merge-base=\(base)", candidate, head], at: work, quiet: true)
        let mergedTree = String(decoding: result.output, as: UTF8.self).split(separator: "\n").first.map(String.init) ?? ""
        let usable = result.status <= 1 && !mergedTree.isEmpty && mergedTree.allSatisfy(\.isHexDigit)
        let paths = try names(Command.run("git", ["diff", "--no-renames", "--name-only", "-z"] + (usable ? [candidateTree, mergedTree] : [base, head]), at: work, quiet: true))
        let exported = Set(try names(Command.run("git", ["ls-tree", "-r", "-z", "--name-only", candidateTree], at: work, quiet: true)))
        // Staging copies no hidden file except the top-level .gitignore, so no export can carry one.
        let hidden = { (path: String) in path != ".gitignore" && path.split(separator: "/").contains { $0.hasPrefix(".") } }
        let carried = paths.filter { !hidden($0) && exported.contains($0) }
        let unexported = paths.filter { !hidden($0) && !exported.contains($0) }
        let invisible = paths.filter(hidden)
        var text = "Public main has changes that are not in this candidate: \(listed)."
        if unexported.isEmpty && invisible.isEmpty { return text + " " + reconcile }
        if !carried.isEmpty { text += " Apply the changes to \(list(carried)) to the \(PublisherProduct.current.name) source in the vault, and rebuild." }
        if !unexported.isEmpty {
            text += " These paths are not part of the exported \(PublisherProduct.current.name) source: \(list(unexported)). Revert them on public main, or add them to the vault source and have tools/export-source.sh copy them."
        }
        if !invisible.isEmpty { text += " Hidden paths are never exported: \(list(invisible)). Revert them on public main." }
        return text + " Then prepare again."
    }

    private static func names(_ data: Data) -> [String] {
        String(decoding: data, as: UTF8.self).split(separator: "\0").map(String.init)
    }

    private static func list(_ paths: [String]) -> String {
        paths.prefix(5).joined(separator: ", ") + (paths.count > 5 ? " and \(paths.count - 5) more" : "")
    }

    /// The clean three-way merge result, or nil on a conflict or Git failure (both refuse).
    private static func merged(base: String, ours: String, theirs: String, at work: URL) throws -> String? {
        let result = try Command.attempt("git", ["merge-tree", "--write-tree", "--merge-base=\(base)", ours, theirs], at: work)
        guard result.status == 0 else { return nil }
        return String(decoding: result.output, as: UTF8.self).split(separator: "\n").first.map(String.init)
    }

    /// Name up to five public commits, preferring those whose own change the candidate lacks.
    private static func unreconciled(tag: String, head: String, candidate: String, candidateTree: String, at work: URL) throws -> String {
        let commits = try Command.text("git", ["rev-list", "--reverse", "\(tag)..\(head)"], at: work)
            .split(separator: "\n").map(String.init)
        // Checking each commit alone is cheap for a handful; a long run is simply listed.
        var missing = commits
        if commits.count <= 50 {
            missing = try commits.filter { commit in
                let parent = try Command.attempt("git", ["rev-parse", "--verify", "--quiet", "\(commit)^1"], at: work, quiet: true)
                guard parent.status == 0 else { return true }
                let base = String(decoding: parent.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                return try merged(base: base, ours: candidate, theirs: commit, at: work) != candidateTree
            }
            // Changes can be missing only in combination; then every later commit is suspect.
            if missing.isEmpty { missing = commits }
        }
        var names = try missing.prefix(5).map { commit -> String in
            let line = try Command.text("git", ["log", "-1", "--format=%h %s", commit], at: work)
            return line.count > 72 ? String(line.prefix(71)) + "…" : line
        }
        if missing.count > 5 { names.append("and \(missing.count - 5) more") }
        return names.joined(separator: "; ")
    }
}
