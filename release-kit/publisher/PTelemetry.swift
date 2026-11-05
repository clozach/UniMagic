import Foundation
import Darwin

/// Best-effort progress for the app's Publish lozenge: one JSON object per line, appended to a
/// file the app created, one write per line so a reader never sees half an object. Nothing here
/// throws or changes a command's reply; a missing or unwritable file simply stays silent.
enum Telemetry {
    struct Step { let id: String; let label: String; let seconds: Double }

    /// Defaults come from the last real run; completed runs replace them with learned medians.
    static let plans: [String: [Step]] = [
        "prepare": [
            Step(id: "release-status", label: "Checking the latest public release", seconds: 3),
            Step(id: "freeze", label: "Freezing the source", seconds: 2),
            Step(id: "public-source", label: "Comparing with the public source", seconds: 6),
            Step(id: "test-core", label: "Running the regression checks", seconds: 150),
            Step(id: "test-install", label: "Checking a fresh install", seconds: 20),
            Step(id: "test-update", label: "Checking an update from the last release", seconds: 30),
            Step(id: "build", label: "Building the signed universal app", seconds: 65),
            Step(id: "verify-app", label: "Verifying the built app", seconds: 6),
            Step(id: "prior-signer", label: "Checking the signature matches the last release", seconds: 6),
            Step(id: "receipt", label: "Writing the release receipt", seconds: 1),
        ],
        "publish": [
            Step(id: "verify-candidate", label: "Verifying the approved candidate", seconds: 3),
            Step(id: "release-status", label: "Checking the latest public release", seconds: 3),
            Step(id: "clone", label: "Downloading the public source", seconds: 4),
            Step(id: "stage", label: "Staging the new source", seconds: 3),
            Step(id: "push", label: "Pushing the source and tag", seconds: 5),
            Step(id: "upload", label: "Uploading the app", seconds: 20),
            Step(id: "release", label: "Releasing it as the latest version", seconds: 4),
            Step(id: "confirm", label: "Confirming the public release", seconds: 4),
        ],
    ]

    private static var command = ""
    private static var steps: [Step] = []
    private static var expected: [Double] = []
    private static var current: (index: Int, started: Date)?
    private static var descriptor: Int32 = -1
    private static var history: URL?

    /// Begin a command's plan and its first step. Learning works even without a progress file.
    static func start(_ name: String, progressFile: String?, root: URL) {
        guard let plan = plans[name] else { return }
        command = name; steps = plan
        history = root.appendingPathComponent(".build/publisher/telemetry.json")
        let learned = (history.flatMap { try? jsonObject(Data(contentsOf: $0)) }?["durations"] as? [String: Any]) ?? [:]
        expected = plan.map { step in
            let samples = (learned["\(name)/\(step.id)"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }
                .filter { $0.isFinite && (0...3600).contains($0) }.suffix(5).sorted()
            guard !samples.isEmpty else { return step.seconds }
            let middle = samples.count / 2
            return samples.count % 2 == 1 ? samples[middle] : (samples[middle - 1] + samples[middle]) / 2
        }
        if let path = progressFile, valid(path) {
            // Never create, follow a final symlink, or block on a FIFO: only append to the app's own file.
            let fd = open(path, O_WRONLY | O_APPEND | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            var info = stat()
            if fd >= 0, fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG { descriptor = fd }
            else if fd >= 0 { close(fd) }
        }
        enter(0)
    }

    /// Steps a run skips are simply never begun; the fill jumps ahead and never moves back.
    static func begin(_ id: String) {
        guard let index = steps.firstIndex(where: { $0.id == id }), index > (current?.index ?? -1) else { return }
        complete()
        enter(index)
    }

    /// Success only: a failure writes nothing further, so the error reply ends the bar.
    static func finish() {
        guard !steps.isEmpty else { return }
        complete()
        write(step: "done", label: "Done", index: steps.count, start: 1, end: 1, seconds: 0)
        if descriptor >= 0 { close(descriptor); descriptor = -1 }
        steps = []
    }

    static func valid(_ path: String) -> Bool {
        path.hasPrefix("/") && path.utf8.count < 1024 && !path.contains("\0") &&
            !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    private static func enter(_ index: Int) {
        guard steps.indices.contains(index) else { return }
        current = (index, Date())
        let weights = expected.map { max($0, 0) }
        let total = weights.reduce(0, +)
        let share = { (count: Int) in total > 0 ? weights.prefix(count).reduce(0, +) / total : Double(count) / Double(weights.count) }
        write(step: steps[index].id, label: steps[index].label, index: index, start: share(index), end: share(index + 1), seconds: expected[index])
    }

    /// Record how long a step that actually finished took, keeping the last five samples.
    private static func complete() {
        guard let step = current, let history else { return }
        current = nil
        let seconds = Date().timeIntervalSince(step.started)
        guard seconds.isFinite, (0...3600).contains(seconds) else { return }
        var store = (try? jsonObject(Data(contentsOf: history))) ?? [:]
        var durations = store["durations"] as? [String: Any] ?? [:]
        let key = "\(command)/\(steps[step.index].id)"
        durations[key] = Array(((durations[key] as? [Any] ?? []) + [decimal(rounded(seconds, 100))]).suffix(5))
        store["schema"] = 1; store["durations"] = durations
        try? FileManager.default.createDirectory(at: history.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? writeJSON(store, to: history)
    }

    private static func write(step: String, label: String, index: Int, start: Double, end: Double, seconds: Double) {
        guard descriptor >= 0 else { return }
        let first = min(max(rounded(start, 10_000), 0), 1)
        let object: [String: Any] = ["schema": 1, "command": command, "step": step, "label": label, "index": index,
                                     "count": steps.count, "start": decimal(first), "end": decimal(max(min(rounded(end, 10_000), 1), first)),
                                     "expectedSeconds": decimal(min(max(rounded(seconds, 100), 0), 3600))]
        guard var line = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), line.count < 1024 else { return }
        line.append(10)
        _ = line.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
    }

    private static func rounded(_ value: Double, _ scale: Double) -> Double { (value * scale).rounded() / scale }

    /// JSONSerialization prints a Double's full binary expansion; a decimal prints as written (0.0012).
    private static func decimal(_ value: Double) -> NSNumber { NSDecimalNumber(string: "\(value)") }
}
