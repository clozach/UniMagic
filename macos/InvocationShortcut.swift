import AppKit
import Carbon

/// Tinycast may already own the command shortcut. Release before a configured
/// launcher starts, and reclaim after it exits. Never rewrite either app's preferences.
@MainActor final class InvocationShortcut {
  private let invoke: () -> Void
  private var key: EventHotKeyRef?
  private var port: CFMessagePort?
  private var handler: EventHandlerRef?
  private var observers: [NSObjectProtocol] = []
  private let preference = "hotkey.extensionCommand.extension:unimagic/unimagic"
  init(invoke: @escaping () -> Void) { self.invoke = invoke }

  func start() {
    var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let callback: EventHandlerUPP = { _, _, context in
      guard let context else { return OSStatus(eventNotHandledErr) }
      let owner = Unmanaged<InvocationShortcut>.fromOpaque(context).takeUnretainedValue()
      MainActor.assumeIsolated { owner.invoke() }
      return noErr
    }
    InstallEventHandler(GetApplicationEventTarget(), callback, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
    let workspace = NSWorkspace.shared
    for name in [NSWorkspace.willLaunchApplicationNotification, NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
      observers.append(workspace.notificationCenter.addObserver(forName: name, object: nil, queue: .main) {
        [weak self] note in
        let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
        guard let id, Self.isTinycast(id) else { return }
        MainActor.assumeIsolated {
          self?.refresh(starting: name == NSWorkspace.didTerminateApplicationNotification ? nil : id)
        }
      })
    }
    listenForIntegratedRebinding()
    refresh()
  }

  private func listenForIntegratedRebinding() {
    let callback: CFMessagePortCallBack = { _, id, data, context in
      guard let data, let context else { return nil }
      let owner = Unmanaged<InvocationShortcut>.fromOpaque(context).takeUnretainedValue()
      let message = String(data: data as Data, encoding: .utf8)
      let handled = MainActor.assumeIsolated {
        switch (id, message) {
        case (2, "release"):
          guard NSWorkspace.shared.runningApplications.contains(where: { app in
            guard let id = app.bundleIdentifier, InvocationShortcut.isTinycast(id), !app.isTerminated else { return false }
            return owner.ownsChord(id)
          }) else { return false }
          owner.release()
        case (3, "recheck"):
          // Receive after the caller has unregistered and flushed its preference.
          owner.refresh()
        default: return false
        }
        return true
      }
      return Unmanaged.passRetained(Data((handled ? "1" : "0").utf8) as CFData)
    }
    var context = CFMessagePortContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
      retain: nil, release: nil, copyDescription: nil)
    guard let channel = CFMessagePortCreateLocal(nil, "com.clozach.unimagic.mac.shortcut" as CFString,
      callback, &context, nil), let source = CFMessagePortCreateRunLoopSource(nil, channel, 0) else { return }
    port = channel
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
  }
  private func release() {
    if let key { UnregisterEventHotKey(key); self.key = nil }
  }

  nonisolated static func isTinycast(_ id: String) -> Bool {
    id == "com.tinycast.app" || id == "com.tinycast.app.clozach"
  }
  private func ownsChord(_ id: String) -> Bool {
    CFPreferencesAppSynchronize(id as CFString)
    guard let value = CFPreferencesCopyAppValue(preference as CFString, id as CFString) as? String,
          let data = value.data(using: .utf8),
          let binding = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let combo = (binding["combo"] as? [String: Any])?["_0"] as? [String: Int] else { return false }
    return combo["carbonKeyCode"] == kVK_Space && combo["carbonModifiers"] == (controlKey | cmdKey)
  }

  private func refresh(starting: String? = nil) {
    let candidates = NSWorkspace.shared.runningApplications.filter { !$0.isTerminated }.compactMap(\.bundleIdentifier) + [starting].compactMap { $0 }
    if candidates.contains(where: { Self.isTinycast($0) && ownsChord($0) }) {
      release()
    } else if key == nil {
      RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | cmdKey), EventHotKeyID(signature: 0x554D4147, id: 1),
        GetApplicationEventTarget(), 0, &key)
    }
  }
  func stop() {
    if let port { CFMessagePortInvalidate(port) }
    release()
    if let handler { RemoveEventHandler(handler) }
    for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
  }
}
