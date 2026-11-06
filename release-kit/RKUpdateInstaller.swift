import Foundation

/// Puts a verified copy in place of the running one, reusing the installer's transaction:
/// the old copy goes to the Trash with a receipt, and the receipt can bring it back.
enum UpdateInstaller {
    static func trash(_ url: URL) throws -> URL {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        guard let result else { throw installationError("Trash did not return an undo location") }
        return result as URL
    }

    /// Returns the receipt that undoes this install. On failure the previous copy is put back.
    static func install(_ staged: URL, over target: URL, identifier: String, receipts: URL,
                        configuration: ReleaseConfiguration = .clipEdge,
                        trash: (URL) throws -> URL = UpdateInstaller.trash,
                        verify: (URL) throws -> Void) throws -> URL {
        try requireReplaceable(target, configuration: configuration)
        let fm = FileManager.default
        try fm.createDirectory(at: receipts, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let receipt = receipts.appendingPathComponent("update-\(UUID().uuidString).json")
        do {
            try prepareInstall(target: target, candidates: [], receiptURL: receipt, identifier: identifier, trash: trash)
            try finishInstall(source: staged, receiptURL: receipt, identifier: identifier, verify: verify)
        } catch {
            var detail = error.localizedDescription
            if fm.fileExists(atPath: receipt.path) {
                do {
                    try restoreInstall(receiptURL: receipt, identifier: identifier, trash: trash)
                    try? fm.removeItem(at: receipt)
                } catch {
                    detail += "; the previous copy is in the Trash and could not be put back: \(error.localizedDescription)"
                }
            }
            throw UpdateFailure.installFailed(detail)
        }
        return receipt
    }

    /// Reads current bytes rather than Bundle's cached metadata at the destructive boundary.
    private static func requireReplaceable(_ target: URL, configuration: ReleaseConfiguration) throws {
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        let data = try Data(contentsOf: target.appendingPathComponent("Contents/Info.plist"))
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw installationError("Cannot read destination app metadata: \(target.path)")
        }
        guard !configuration.preservesMaintainerBuild(info: info) else {
            throw installationError("This is your maintainer copy. Rebuild it to update; public releases won’t replace it.")
        }
    }

    private static func rollbackReceipt(_ receipt: URL, expectedTarget: URL?, configuration: ReleaseConfiguration) throws -> InstallReceipt {
        let decoded = try JSONDecoder().decode(InstallReceipt.self, from: Data(contentsOf: receipt))
        if let target = expectedTarget?.resolvingSymlinksInPath().standardizedFileURL.path {
            // URL equality also compares directory hints, which can change after
            // installing a bundle. Bind the normalized filesystem location.
            guard decoded.target.resolvingSymlinksInPath().standardizedFileURL.path == target,
                  decoded.replaced.allSatisfy({ $0.original.resolvingSymlinksInPath().standardizedFileURL.path == target }) else {
                throw installationError("This receipt belongs to a different app location")
            }
        }
        try requireReplaceable(decoded.target, configuration: configuration)
        for app in decoded.replaced { try requireReplaceable(app.original, configuration: configuration) }
        return decoded
    }

    /// True while the copy this receipt replaced is still in the Trash and its destinations are permitted.
    static func canGoBack(using receipt: URL, expectedTarget: URL? = nil,
                          configuration: ReleaseConfiguration = .clipEdge) -> Bool {
        guard let decoded = try? rollbackReceipt(receipt, expectedTarget: expectedTarget, configuration: configuration) else { return false }
        return decoded.installed && !decoded.replaced.isEmpty
            && decoded.replaced.allSatisfy { FileManager.default.fileExists(atPath: $0.trashed.path) }
    }

    static func goBack(using receipt: URL, identifier: String, expectedTarget: URL? = nil,
                       configuration: ReleaseConfiguration = .clipEdge,
                       trash: (URL) throws -> URL = UpdateInstaller.trash) throws {
        do {
            _ = try rollbackReceipt(receipt, expectedTarget: expectedTarget, configuration: configuration)
            try restoreInstall(receiptURL: receipt, identifier: identifier, trash: trash)
        }
        catch { throw UpdateFailure.cannotGoBack(error.localizedDescription) }
    }

    /// Opens `app` once this process has exited. ClipEdge keeps one running copy (the oldest wins),
    /// so the new copy has to start after this one is gone. Gives up waiting after a minute.
    static func reopenAfterExit(_ app: URL, pid: Int32 = ProcessInfo.processInfo.processIdentifier) {
        let script = #"i=0; while kill -0 "$1" 2>/dev/null && [ "$i" -lt 600 ]; do sleep 0.1; i=$((i+1)); done; exec /usr/bin/open "$2""#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "clipedge-reopen", String(pid), app.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }
}
