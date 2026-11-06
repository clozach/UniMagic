import Foundation

/// A dotted release number. Missing parts count as zero, so 2.1 equals 2.1.0 and v2.1.0.
struct AppVersion: Comparable, Hashable, CustomStringConvertible {
    let parts: [Int]

    init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") { trimmed.removeFirst() }
        let pieces = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard !pieces.isEmpty, pieces.count <= 4 else { return nil }
        var parts: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.count <= 9, piece.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(piece) else { return nil }
            parts.append(value)
        }
        while parts.count > 1, parts.last == 0 { parts.removeLast() }
        self.parts = parts
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    var description: String {
        (parts.count == 1 ? parts + [0] : parts).map(String.init).joined(separator: ".")
    }
}

/// The owner's one standing answer. `unasked` makes no network request at all.
enum UpdatePreference: String, Codable { case unasked, automatic, manual }

struct UpdateRelease: Equatable {
    let version: AppVersion
    let archive: URL
    let archiveBytes: Int
    let page: URL?
}

/// Why this copy cannot replace itself. Each has its own sentence in UpdateStatus.
enum UpdateBlocker: Equatable {
    case maintainerCopy
    case builtFromSource
    case unsigned
    case movedByMacOS
    case folderLocked(String)
}

enum UpdateAvailability: Equatable {
    case available(feed: URL)
    case blocked(UpdateBlocker)

    /// Only a release build names a feed; only a certificate-signed copy can be matched by a later one.
    static func resolve(bundle: URL, feedText: String?, isAdHoc: () -> Bool, folderWritable: () -> Bool, preservesMaintainerBuild: Bool = false) -> UpdateAvailability {
        if preservesMaintainerBuild { return .blocked(.maintainerCopy) }
        guard let feedText, let feed = URL(string: feedText), feed.scheme == "https" || feed.isFileURL else {
            return .blocked(.builtFromSource)
        }
        if isAdHoc() { return .blocked(.unsigned) }
        if bundle.path.contains("/AppTranslocation/") { return .blocked(.movedByMacOS) }
        if !folderWritable() { return .blocked(.folderLocked(bundle.deletingLastPathComponent().path)) }
        return .available(feed: feed)
    }
}

enum UpdateFailure: Error, Equatable, Codable {
    case offline(String)
    case feedUnreadable(String)
    case noArchive
    case archiveTooLarge(Int)
    case unsafeArchive(String)
    case notClipEdge(String)
    case signatureMismatch(String)
    case versionMismatch(expected: String, found: String)
    case historyNotSaved
    case installFailed(String)
    case cannotGoBack(String)
}

/// How the most recent check ended; `nil` means none has run yet.
enum UpdateCheck: Equatable, Codable {
    case current(Date)
    case failed(Date, UpdateFailure)

    var date: Date {
        switch self { case .current(let date), .failed(let date, _): return date }
    }
}

/// A downloaded release that has already passed the signature and version checks.
struct StagedUpdate: Equatable {
    let release: UpdateRelease
    let app: URL
}

enum UpdatePhase: Equatable {
    case resting(UpdateCheck?)
    case checking
    case downloading(UpdateRelease)
    case ready(StagedUpdate)
}

/// The last update installed on this Mac: what "What's New" and "Go Back" act on.
struct UpdateRecord: Codable, Equatable {
    let from: String
    let to: String
    let date: Date
    let receipt: URL
    let page: URL?
}

enum UpdateFeed {
    static let archiveLimit = 100 * 1024 * 1024

    static let listQuery = "?per_page=12"
    static let metadataLimit = 1_048_576

    /// Select one bounded page by numeric version. Drafts, prereleases, and releases for
    /// other platforms do not belong to this feed. Fail closed on an incomplete archive.
    static func stableRelease(_ data: Data, archiveTemplate: String, repository: String) throws -> [String: Any] {
        guard data.count <= metadataLimit,
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              rows.count <= 12 else { throw UpdateFailure.feedUnreadable("invalid stable release list") }
        var selected: (version: AppVersion, row: [String: Any])?
        for row in rows {
            guard row["draft"] as? Bool == false, row["prerelease"] as? Bool == false,
                  let tag = row["tag_name"] as? String,
                  tag.range(of: #"^v(0|[1-9][0-9]{0,7})\.(0|[1-9][0-9]{0,7})\.(0|[1-9][0-9]{0,7})$"#,
                            options: .regularExpression) != nil, let version = AppVersion(tag),
                  let assets = row["assets"] as? [[String: Any]] else { continue }
            let name = archiveTemplate.replacingOccurrences(of: "{version}", with: String(tag.dropFirst()))
            let matches = assets.filter { $0["name"] as? String == name }
            guard !matches.isEmpty else { continue }
            guard matches.count == 1, let asset = matches.first,
                  asset["state"] as? String == "uploaded",
                  let size = asset["size"] as? Int, (1...archiveLimit).contains(size),
                  asset["browser_download_url"] as? String == "https://github.com/\(repository)/releases/download/\(tag)/\(name)"
            else { throw UpdateFailure.feedUnreadable("invalid or ambiguous stable app archive") }
            if selected == nil || selected!.version < version {
                // Preserve the full asset list for the publisher's manifest and archive readback.
                selected = (version, row)
            }
        }
        guard let selected else { throw UpdateFailure.noArchive }
        return selected.row
    }

    /// Reads GitHub's "latest release" answer. A local feed (tests) may name local archives.
    static func release(from data: Data, allowLocal: Bool = false, assetPrefix: String = "ClipEdge", exactName: String? = nil) -> Result<UpdateRelease, UpdateFailure> {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure(.feedUnreadable("the release list was not readable"))
        }
        guard let tag = object["tag_name"] as? String, let version = AppVersion(tag) else {
            return .failure(.feedUnreadable("the release has no version number"))
        }
        func link(_ value: Any?) -> URL? {
            guard let text = value as? String, let url = URL(string: text) else { return nil }
            return url.scheme == "https" || (allowLocal && url.isFileURL) ? url : nil
        }
        let assets = object["assets"] as? [[String: Any]] ?? []
        for asset in assets {
            guard let name = asset["name"] as? String, name.hasPrefix(assetPrefix), name.hasSuffix(".zip"), exactName == nil || name == exactName,
                  let archive = link(asset["browser_download_url"]) else { continue }
            let bytes = asset["size"] as? Int ?? 0
            guard bytes <= archiveLimit else { return .failure(.archiveTooLarge(bytes)) }
            return .success(UpdateRelease(version: version, archive: archive, archiveBytes: bytes,
                                          page: link(object["html_url"])))
        }
        return .failure(.noArchive)
    }
}

enum UpdateArchive {
    /// The first entry that would land outside the app's own folder, if any.
    static func unsafeEntry(in entries: [String], bundleName: String) -> String? {
        entries.first { entry in
            let parts = entry.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if entry.hasPrefix("/") || entry.contains("\\") || parts.contains("..") { return true }
            return parts.first != bundleName && parts.first != "__MACOSX"
        }
    }
}

enum UpdateSchedule {
    static let checkEvery: TimeInterval = 24 * 60 * 60
    static let retryAfter: TimeInterval = 60 * 60
    /// Input must have been still this long before an update replaces the running app.
    static let quietSeconds: TimeInterval = 120

    static func isDue(last: UpdateCheck?, now: Date) -> Bool {
        guard let last else { return true }
        let elapsed = now.timeIntervalSince(last.date)
        if elapsed < 0 { return true }
        switch last {
        case .current: return elapsed >= checkEvery
        case .failed: return elapsed >= retryAfter
        }
    }
}
