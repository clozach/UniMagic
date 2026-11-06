import Foundation
import Darwin

struct PublisherError: Error, CustomStringConvertible {
    let description: String
    let recovery: String?
    init(_ message: String, recovery: String? = nil) { description = message; self.recovery = recovery }
}

private var publisherChildPID: Int32 = 0

enum Command {
    static var logPath: URL?
    static func installCancellation() {
        signal(SIGTERM) { _ in
            if publisherChildPID > 0 { kill(publisherChildPID, SIGTERM) }
            _exit(143)
        }
        signal(SIGINT) { _ in
            if publisherChildPID > 0 { kill(publisherChildPID, SIGTERM) }
            _exit(130)
        }
    }

    /// Capture stdout in a file, avoiding pipe deadlocks for git/gh output. Never include raw
    /// subprocess stderr in JSON: gh diagnostics can include account or network details.
    @discardableResult
    static func run(_ executable: String, _ arguments: [String], at root: URL? = nil,
                    quiet: Bool = false) throws -> Data {
        let (status, data) = try attempt(executable, arguments, at: root, quiet: quiet)
        guard status == 0 else {
            throw PublisherError("\(URL(fileURLWithPath: executable).lastPathComponent) did not complete (exit \(status)). No release was confirmed.")
        }
        return data
    }

    /// Like `run`, but returns a nonzero exit status instead of throwing: some Git checks
    /// answer through their status (a merge conflict, a commit that is not an ancestor).
    static func attempt(_ executable: String, _ arguments: [String], at root: URL? = nil,
                        quiet: Bool = false, outputLimit: Int? = nil) throws -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.currentDirectoryURL = root
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("clipedge-command-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: output)
        let errors = output.appendingPathExtension("stderr")
        FileManager.default.createFile(atPath: errors.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let errorHandle = try FileHandle(forWritingTo: errors)
        defer {
            try? handle.close(); try? errorHandle.close()
            try? FileManager.default.removeItem(at: output); try? FileManager.default.removeItem(at: errors)
        }
        process.standardOutput = handle
        process.standardError = quiet ? FileHandle.nullDevice : errorHandle
        try process.run()
        publisherChildPID = process.processIdentifier
        process.waitUntilExit()
        publisherChildPID = 0
        if let limit = outputLimit, let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > limit {
            throw PublisherError("The public release metadata exceeded the size limit.")
        }
        let data = try Data(contentsOf: output)
        if !quiet {
            let errorData = (try? Data(contentsOf: errors)) ?? Data()
            if let path = logPath {
                var existing = (try? Data(contentsOf: path)) ?? Data()
                existing.append(Data((executable + " " + arguments.joined(separator: " ") + "\n").utf8))
                existing.append(data); existing.append(errorData)
                try existing.write(to: path, options: .atomic)
            }
            FileHandle.standardError.write(errorData)
        }
        return (process.terminationStatus, data)
    }

    static func text(_ executable: String, _ arguments: [String], at root: URL? = nil, quiet: Bool = false) throws -> String {
        String(decoding: try run(executable, arguments, at: root, quiet: quiet), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func log(_ text: String) { FileHandle.standardError.write(Data((text + "\n").utf8)) }
}

func jsonObject(_ data: Data) throws -> [String: Any] {
    guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PublisherError("The reply was not a JSON object.") }
    return value
}

func writeJSON(_ object: [String: Any], to url: URL) throws {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
}

func emit(_ object: [String: Any]) {
    let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{\"kind\":\"error\",\"message\":\"Invalid response.\"}".utf8)
    FileHandle.standardOutput.write(data + Data([10]))
}

func digest(_ url: URL) throws -> String { ContentIdentity.sha256(try Data(contentsOf: url)) }

func safeIdentifier(_ value: String) -> Bool {
    !value.isEmpty && value.count < 120 && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_") }
}

func validFingerprint(_ value: String) -> Bool { value.count == 64 && value.allSatisfy { $0.isHexDigit && !$0.isUppercase } }
