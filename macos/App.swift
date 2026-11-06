import AppKit
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
  private var settingsWindow: NSWindow?
  private let model = SettingsModel()
  private let picker = PickerProcess()
  private lazy var shortcut = InvocationShortcut { [weak self] in self?.picker.send("invoke") }

  func applicationDidFinishLaunching(_ notification: Notification) {
    picker.reportCopy = { message in
      let alert = NSAlert()
      alert.messageText = "Glyph copied"
      alert.informativeText = message
      alert.runModal()
    }
    picker.openSettings = { [weak self] in self?.settings() }
    picker.onError = { message in
      let alert = NSAlert()
      alert.messageText = "UniMagic Picker could not open"
      alert.informativeText = message
      alert.runModal()
    }
    status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    status.button?.title = "✦"
    let menu = NSMenu()
    menu.addItem(withTitle: "Open UniMagic", action: #selector(show), keyEquivalent: "")
    menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",")
    menu.addItem(.separator())
    menu.addItem(withTitle: "Quit UniMagic", action: #selector(quit), keyEquivalent: "q")
    for item in menu.items { item.target = self }
    status.menu = menu
    let main = NSMenu()
    let edit = NSMenu(title: "Edit")
    for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                 ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
      edit.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
    }
    main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
    NSApp.mainMenu = main
    if ProcessInfo.processInfo.environment["UNIMAGIC_FIXTURE"] != "1" { shortcut.start() }
    if ProcessInfo.processInfo.environment["UNIMAGIC_CAPTURE_SETTINGS"] == "1" { settings() }
    else if settingsWindow?.isVisible != true { show() }
  }

  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls where url.scheme == "unimagic" {
      if url.host == "settings" { settings() } else { show() }
    }
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
    show()
    return false
  }
  func applicationWillTerminate(_ notification: Notification) {
    shortcut.stop()
    picker.stop()
  }
  @objc private func show() {
    settingsWindow?.orderOut(nil)
    picker.send("show")
  }
  @objc private func settings() {
    picker.send("hide")
    if settingsWindow == nil {
      let root = SettingsView(model: model) { [weak self] in self?.settingsWindow?.orderOut(nil) }
      let window = NSWindow(contentViewController: NSHostingController(rootView: root))
      window.styleMask = [.titled, .closable]
      window.title = "UniMagic Settings"
      window.isReleasedWhenClosed = false
      window.center()
      settingsWindow = window
    }
    Task { await model.refreshCategories() }
    NSApp.activate(ignoringOtherApps: true)
    settingsWindow?.makeKeyAndOrderFront(nil)
    if let settingsWindow { captureSettingsFixture(settingsWindow) }
  }
  @objc private func quit() { NSApp.terminate(nil) }
}
