import AppKit
import ApplicationServices
import Carbon

/// Paste from the same signed controller that owns UniMagic's Accessibility grant.
@MainActor final class DesktopPaste {
  private var lastExternal: NSRunningApplication?
  private var target: NSRunningApplication?
  private var generation = 0
  private var observer: NSObjectProtocol?
  init() {
    remember(NSWorkspace.shared.frontmostApplication)
    observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
        object: nil, queue: .main) { [weak self] note in
      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      MainActor.assumeIsolated { self?.remember(app) }
    }
  }
  func begin() {
    remember(NSWorkspace.shared.frontmostApplication)
    target = lastExternal
  }
  private func remember(_ app: NSRunningApplication?) {
    guard let app, app.activationPolicy != .prohibited, isExternal(app) else { return }
    lastExternal = app
  }
  func perform(text: String, keepOpen: Bool, observedPID: Int32?, report: @escaping (String) -> Void) {
    let fixture = ProcessInfo.processInfo.environment["UNIMAGIC_FIXTURE"] == "1"
    let board = fixture ? NSPasteboard(name: .init("UniMagic-fixture-\(ProcessInfo.processInfo.processIdentifier)")) : .general
    board.clearContents()
    board.setString(text, forType: .string)
    guard !fixture else { return }
    // Favor the target the palette itself saw. If it covered our own settings
    // window or helper, retain the external app seen before it was opened.
    if let observedPID, let observed = NSRunningApplication(processIdentifier: observedPID),
       isExternal(observed) { target = observed }
    guard let target, isExternal(target) else { report("Copied. The original app is no longer available."); return }
    guard AXIsProcessTrusted() else {
      report("Copied. To insert directly, allow UniMagic in System Settings → Privacy & Security → Accessibility.")
      return
    }
    guard keepOpen || target.activate() else { report("Copied. The original app could not be activated."); return }
    generation += 1
    let ticket = generation
    DispatchQueue.main.asyncAfter(deadline: .now() + (keepOpen ? 0.05 : 0.15)) { [weak self] in
      guard let self, self.generation == ticket, !target.isTerminated,
            board.string(forType: .string) == text,
            keepOpen || NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
      else { return }
      let source = CGEventSource(stateID: .combinedSessionState)
      for down in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
        event?.flags = .maskCommand
        event?.postToPid(target.processIdentifier)
      }
    }
  }
  private func isExternal(_ app: NSRunningApplication) -> Bool {
    !app.isTerminated && app.processIdentifier != ProcessInfo.processInfo.processIdentifier
      && app.bundleIdentifier != "com.clozach.unimagic.mac.picker"
      && app.bundleIdentifier != "com.tinycast.app"
      && app.bundleIdentifier?.hasPrefix("com.tinycast.app.") != true
  }
}
