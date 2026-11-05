import AppKit
import ApplicationServices
import Carbon
import SwiftUI

@main struct UniMagicMain {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
  }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  private var status: NSStatusItem!
  private var window: NSWindow!
  private var model: PickerModel!
  private var previous: NSRunningApplication?
  private var pasteGeneration = 0
  private var hotKey: EventHotKeyRef?
  private var keyMonitor: Any?
  func applicationDidFinishLaunching(_ notification: Notification) {
    model = PickerModel()
    model.dismiss = { [weak self] in self?.window.orderOut(nil) }
    model.paste = { [weak self] text, keep in self?.insert(text, keep: keep) }
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1120, height: 680),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = "UniMagic"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: PickerView(model: model))
    window.center()
    status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    status.button?.title = "✦"
    let menu = NSMenu()
    menu.addItem(withTitle: "Open UniMagic   ⌃⌘Space", action: #selector(show), keyEquivalent: "")
    menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",")
    menu.addItem(.separator())
    menu.addItem(withTitle: "Quit UniMagic", action: #selector(quit), keyEquivalent: "q")
    for item in menu.items { item.target = self }
    status.menu = menu
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, self.window.isKeyWindow, !self.model.showingSettings else { return event }
      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      if flags.contains(.control), let key = event.charactersIgnoringModifiers,
        let delta = ["h": -1, "j": 8, "k": -8, "l": 1][key]
      {
        self.model.move(delta)
        return nil
      }
      if event.keyCode == 48, self.model.detail == nil {
        self.model.inspect()
        return nil
      }
      if event.keyCode == 36, flags.contains(.command) {
        self.model.pick(opposite: true)
        return nil
      }
      return event
    }
    if ProcessInfo.processInfo.environment["UNIMAGIC_FIXTURE"] != "1" { registerHotKey() }
    show()
    configureFixtureCapture(window: window, model: model)
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls where url.scheme == "unimagic" {
      show()
      if url.host == "settings" { model.showingSettings = true }
    }
  }
  @objc func show() { present(refresh: true) }
  private func present(refresh: Bool) {
    if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier {
      previous = NSWorkspace.shared.frontmostApplication
    }
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    if refresh {
      Task {
        await model.refreshForPresentation()
      }
    }
  }
  @objc private func settings() {
    show()
    model.showingSettings = true
  }
  @objc private func quit() {
    if let sheet = window.attachedSheet { window.endSheet(sheet) }
    NSApp.terminate(nil)
  }
  private func registerHotKey() {
    let handler: EventHandlerUPP = { _, _, context in
      guard let context else { return OSStatus(eventNotHandledErr) }
      let owner = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
      MainActor.assumeIsolated { owner.show() }
      return noErr
    }
    var type = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(), handler, 1, &type, Unmanaged.passUnretained(self).toOpaque(), nil
    )
    let result = RegisterEventHotKey(
      UInt32(kVK_Space), UInt32(controlKey | cmdKey), EventHotKeyID(signature: 0x554d_4147, id: 1),
      GetApplicationEventTarget(), 0, &hotKey)
    if result != noErr {
      model.message =
        "⌃⌘Space is in use. Release the old picker shortcut; use the menu bar icon meanwhile."
    }
  }
  private func insert(_ text: String, keep: Bool) {
    PickerModel.copy(text)
    guard ProcessInfo.processInfo.environment["UNIMAGIC_FIXTURE"] != "1" else {
      model.message = "Fixture: copied \(text)"
      return
    }
    guard AXIsProcessTrusted() else {
      model.message =
        "Copied. Allow UniMagic in Privacy & Security → Accessibility to insert directly."
      let alert = NSAlert()
      alert.messageText = "Copied — insertion needs Accessibility permission"
      alert.informativeText =
        "UniMagic sends Command-V to the app you came from. Your glyph is already on the clipboard."
      alert.addButton(withTitle: "Open Accessibility Settings")
      alert.addButton(withTitle: "Keep copied")
      if alert.runModal() == .alertFirstButtonReturn {
        NSWorkspace.shared.open(
          URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        )
      }
      return
    }
    guard let target = previous, !target.isTerminated,
      target.processIdentifier != ProcessInfo.processInfo.processIdentifier
    else {
      model.message = "Copied. The app you came from is no longer available."
      return
    }
    window.orderOut(nil)
    guard target.activate(options: []) else {
      model.message = "Copied. The intended app could not be activated."
      return
    }
    pasteGeneration += 1
    let ticket = pasteGeneration
    let destination = PasteDestination(processIdentifier: target.processIdentifier)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
      guard let self, ticket == self.pasteGeneration,
        destination.permitsPaste(
          frontmostProcessIdentifier: NSWorkspace.shared.frontmostApplication?.processIdentifier,
          targetTerminated: target.isTerminated,
          clipboard: NSPasteboard.general.string(forType: .string), expected: text)
      else {
        self?.model.message = "Copied. The destination changed before insertion."
        return
      }
      let source = CGEventSource(stateID: .combinedSessionState)
      let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
      let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
      down?.flags = .maskCommand
      up?.flags = .maskCommand
      down?.post(tap: .cghidEventTap)
      up?.post(tap: .cghidEventTap)
      if keep {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
          guard let self, ticket == self.pasteGeneration,
            NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier
          else { return }
          self.present(refresh: false)
        }
      }
    }
  }

}
