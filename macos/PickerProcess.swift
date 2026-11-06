import AppKit

/// The separately signed picker renders the command. Its input pipe is also a
/// lifetime lease: closing it stops the helper, including when this app crashes.
@MainActor final class PickerProcess {
  static private(set) var isBusy = false
  private let destination = DesktopPaste()
  var reportCopy: ((String) -> Void)?
  var openSettings: (() -> Void)?
  var onError: ((String) -> Void)?
  private var child: Process?
  private var input: FileHandle?
  private var pendingOpen = false
  private static var lastHide: TimeInterval = 0
  static var safeToUpdate: Bool {
    !isBusy && ProcessInfo.processInfo.systemUptime - lastHide > 3
  }

  func send(_ command: String) {
    do {
      if child == nil {
        guard command != "hide" else { return }
        try start()
      }
      guard let input else { throw CocoaError(.fileWriteUnknown) }
      if command != "hide" {
        if !Self.isBusy { destination.begin() }
        pendingOpen = true
        Self.isBusy = true
      }
      try input.write(contentsOf: Data((command + "\n").utf8))
    } catch { handleError(error.localizedDescription) }
  }

  func stop() {
    try? input?.close()
    input = nil
  }

  private func start() throws {
    let task = Process()
    task.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/PickerHost.app/Contents/MacOS/PickerHost")
    let commands = Pipe(), replies = Pipe()
    task.standardInput = commands
    task.standardOutput = replies
    task.terminationHandler = { [weak self] exited in
      Task { @MainActor in
        guard let self, self.child === exited else { return }
        self.child = nil
        self.stop()
        Self.isBusy = false
        if self.pendingOpen { self.onError?("UniMagic Picker stopped before it could show the command.") }
        self.pendingOpen = false
      }
    }
    try task.run()
    child = task
    input = commands.fileHandleForWriting
    Task { @MainActor [weak self] in
      do {
        for try await line in replies.fileHandleForReading.bytes.lines {
          guard let self, self.child === task else { return }
          switch line {
          case "visible": self.pendingOpen = false; Self.isBusy = true
          case "hidden":
            self.pendingOpen = false
            Self.isBusy = false
            Self.lastHide = ProcessInfo.processInfo.systemUptime
          case "settings": self.openSettings?()
          default:
            if line.hasPrefix("paste "), let data = String(line.dropFirst(6)).data(using: .utf8),
               let request = try? JSONDecoder().decode(PasteRequest.self, from: data) {
              self.destination.perform(text: request.text, keepOpen: request.keep, observedPID: request.pid) { [weak self] message in
                self?.reportCopy?(message)
              }
            }
            if line.hasPrefix("error ") { self.handleError(String(line.dropFirst(6))) }
          }
        }
      } catch { self?.handleError(error.localizedDescription) }
    }
  }
  private func handleError(_ message: String) {
    pendingOpen = false
    Self.isBusy = false
    onError?(message)
  }
}

private struct PasteRequest: Decodable { let text: String; let keep: Bool; let pid: Int32? }
