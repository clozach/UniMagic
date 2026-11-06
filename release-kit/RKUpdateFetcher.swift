import Foundation

/// The updater's only network use: one request for GitHub's latest release, and, when that
/// release is newer, one download. Nothing about the person or the clipboard is sent.
enum UpdateFetcher {
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 10 * 60
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    static func release(feed: URL, runningVersion: String, session: URLSession, productName: String = "ClipEdge", stableArchiveTemplate: String? = nil) async throws -> UpdateRelease {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("release-feed-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let response = try await answer { try await BoundedDownload.fetch(request(feed, runningVersion, productName), using: session, to: file, limit: UpdateFeed.metadataLimit) }
        let data = try Data(contentsOf: file)
        try expectSuccess(response)
        if let template = stableArchiveTemplate {
            let path = feed.path.split(separator: "/")
            guard feed.scheme == "https", feed.host == "api.github.com", path.count == 4,
                  path[0] == "repos", path[3] == "releases" else { throw UpdateFailure.feedUnreadable("unexpected release-list address") }
            let row = try UpdateFeed.stableRelease(data, archiveTemplate: template, repository: "\(path[1])/\(path[2])")
            let tag = row["tag_name"] as! String
            let exact = template.replacingOccurrences(of: "{version}", with: String(tag.dropFirst()))
            return try UpdateFeed.release(from: JSONSerialization.data(withJSONObject: row), assetPrefix: productName, exactName: exact).get()
        }
        return try UpdateFeed.release(from: data, allowLocal: feed.isFileURL, assetPrefix: productName).get()
    }

    /// Downloads the release into `folder` and returns the unpacked app. Nothing is run or installed.
    static func app(for release: UpdateRelease, bundleName: String, runningVersion: String,
                    in folder: URL, session: URLSession, productName: String = "ClipEdge") async throws -> URL {
        let fm = FileManager.default
        try? fm.removeItem(at: folder)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let archive = folder.appendingPathComponent("download.zip")
        let response = try await answer {
            try await BoundedDownload.fetch(request(release.archive, runningVersion, productName), using: session,
                                            to: archive, limit: UpdateFeed.archiveLimit)
        }
        try expectSuccess(response)
        let bytes = try Data(contentsOf: archive, options: .mappedIfSafe)
        guard !bytes.isEmpty else { throw UpdateFailure.archiveTooLarge(0) }
        try UpdateArchiveValidation.validate(bytes, bundleName: bundleName)
        let unpacked = folder.appendingPathComponent("unpacked")
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
        _ = try run("/usr/bin/ditto", ["--norsrc", "-x", "-k", archive.path, unpacked.path])
        try? fm.removeItem(at: archive)

        let app = unpacked.appendingPathComponent(bundleName)
        let values = try? app.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true, values?.isSymbolicLink != true else {
            throw UpdateFailure.notClipEdge("the download does not contain \(bundleName)")
        }
        return app
    }

    private static func request(_ url: URL, _ runningVersion: String, _ productName: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("\(productName)/\(runningVersion)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json, application/octet-stream", forHTTPHeaderField: "Accept")
        return request
    }

    private static func answer<T>(_ work: () async throws -> T) async throws -> T {
        do { return try await work() }
        catch let error as UpdateFailure { throw error }
        catch { throw UpdateFailure.offline(error.localizedDescription) }
    }

    private static func expectSuccess(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard http.statusCode == 200 else {
            throw UpdateFailure.feedUnreadable(http.statusCode == 404 ? "no release is published yet"
                                                                       : "GitHub answered \(http.statusCode)")
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw UpdateFailure.unsafeArchive("could not open the download") }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateFailure.unsafeArchive("the download is not a readable archive") }
        return String(decoding: data, as: UTF8.self)
    }
}
