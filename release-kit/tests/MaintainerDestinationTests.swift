import Foundation

@main enum MaintainerDestinationTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let identifier = "local.codex.ClipEdge"
        func app(_ name: String, maintainer: Bool = false) throws -> URL {
            let url = root.appendingPathComponent(name + ".app")
            try fm.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            let info: [String: Any] = ["CFBundleIdentifier": identifier, "CFBundleExecutable": "ClipEdge", "ClipEdgePublisherEnabled": maintainer]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: url.appendingPathComponent("Contents/Info.plist"))
            let executable = url.appendingPathComponent("Contents/MacOS/ClipEdge")
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            return url
        }
        var trashCalls = 0
        func trash(_ url: URL) throws -> URL {
            trashCalls += 1
            let destination = root.appendingPathComponent("trash-" + UUID().uuidString + ".app")
            try fm.moveItem(at: url, to: destination)
            return destination
        }
        func rejected(_ action: () throws -> Void) {
            do { try action(); preconditionFailure("destructive operation was permitted") }
            catch { }
        }
        let protected = try app("maintainer", maintainer: true)
        let staged = try app("staged")
        let receipts = root.appendingPathComponent("receipts")
        rejected { _ = try UpdateInstaller.install(staged, over: protected, identifier: identifier, receipts: receipts, trash: trash, verify: { _ in }) }
        precondition(trashCalls == 0 && fm.fileExists(atPath: protected.path) && !fm.fileExists(atPath: receipts.path))
        let old = try app("old")
        let receipt = root.appendingPathComponent("old.json")
        try saveReceipt(InstallReceipt(target: protected, replaced: [ReplacedApp(original: protected, trashed: old)], installed: true), to: receipt)
        let originalReceipt = try Data(contentsOf: receipt)
        precondition(!UpdateInstaller.canGoBack(using: receipt, expectedTarget: protected))
        rejected { try UpdateInstaller.goBack(using: receipt, identifier: identifier, expectedTarget: protected, trash: trash) }
        let afterRejectedRollback = try Data(contentsOf: receipt)
        precondition(trashCalls == 0 && afterRejectedRollback == originalReceipt && fm.fileExists(atPath: old.path))
        let target = try app("public")
        let other = try app("other")
        try saveReceipt(InstallReceipt(target: target, replaced: [ReplacedApp(original: other, trashed: old)], installed: true), to: receipt)
        precondition(!UpdateInstaller.canGoBack(using: receipt, expectedTarget: target))
        rejected { try UpdateInstaller.goBack(using: receipt, identifier: identifier, expectedTarget: target, trash: trash) }
        try saveReceipt(InstallReceipt(target: other, replaced: [ReplacedApp(original: other, trashed: old)], installed: true), to: receipt)
        precondition(!UpdateInstaller.canGoBack(using: receipt, expectedTarget: target))
        rejected { try UpdateInstaller.goBack(using: receipt, identifier: identifier, expectedTarget: target, trash: trash) }
        precondition(trashCalls == 0 && fm.fileExists(atPath: target.path) && fm.fileExists(atPath: other.path))
        let valid = try UpdateInstaller.install(staged, over: target, identifier: identifier, receipts: receipts, trash: trash, verify: { _ in })
        precondition(trashCalls == 1 && UpdateInstaller.canGoBack(using: valid, expectedTarget: target))
        try UpdateInstaller.goBack(using: valid, identifier: identifier, expectedTarget: target, trash: trash)
        precondition(trashCalls == 2 && fm.fileExists(atPath: target.path) && !UpdateInstaller.canGoBack(using: valid, expectedTarget: target))
        print("Maintainer installer boundary tests passed")
    }
}
