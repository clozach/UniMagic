import Foundation

@main
struct PublisherMain {
    static func main() {
        Command.installCancellation()
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            var options: [String: String] = [:]
            var command: String?
            var approved = false
            var index = 0
            while index < arguments.count {
                let word = arguments[index]
                if word == "--approve" { approved = true }
                else if word.hasPrefix("--") {
                    guard index + 1 < arguments.count else { throw PublisherError("Missing value for \(word).") }
                    options[word] = arguments[index + 1]
                    index += 1
                } else if command == nil { command = word }
                else { throw PublisherError("Unexpected publisher argument.") }
                index += 1
            }
            let root = URL(fileURLWithPath: options["--source"] ?? FileManager.default.currentDirectoryPath).standardizedFileURL
            try PublisherProduct.configure(root: root)
            if command == "identity" { emit(["kind": "identity", "fingerprint": try ContentIdentity.local(root)]); return }
            guard let running = options["--running-fingerprint"], validFingerprint(running) else { throw PublisherError("A valid running-build fingerprint is required.") }
            switch command {
            case "status": emit(sourceStatus(root: root, running: running))
            case "prepare":
                Telemetry.start("prepare", progressFile: options["--progress-file"], root: root)
                let reply = try Candidate.prepare(root: root, running: running).json
                Telemetry.finish()
                emit(reply)
            case "publish":
                guard approved, let id = options["--candidate"], let digest = options["--archive-sha256"], validFingerprint(digest),
                      let receipt = options["--receipt-sha256"], validFingerprint(receipt) else {
                    throw PublisherError("Publishing requires explicit approval of a candidate and both its archive and receipt SHA-256.")
                }
                Telemetry.start("publish", progressFile: options["--progress-file"], root: root)
                let reply = try Candidate.load(id, under: root, approvedReceipt: receipt).publish(root: root, running: running, approvedDigest: digest, approvedReceipt: receipt)
                Telemetry.finish()
                emit(reply)
            default: throw PublisherError("Use status, prepare, or publish with an explicitly approved frozen candidate.")
            }
        } catch {
            var result: [String: Any] = ["kind": "error", "message": String(describing: error)]
            if let log = Command.logPath { result["logPath"] = log.path }
            if let recovery = (error as? PublisherError)?.recovery { result["recovery"] = recovery }
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(failure.code) {
                result["message"] = "A frozen candidate file is missing. Prepare and review a fresh candidate."
                result["recovery"] = "prepare"
            }
            emit(result)
            exit(1)
        }
    }
}
