// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import Carbon

/// Runs one bundled extension in Tinycast's own runtime, native palette and action system.
/// The outer app owns the menu bar, global shortcut, settings and updates.
@main @MainActor
enum SingleCommandMain {
    static let entry = "extension:unimagic/unimagic"
    static let chord = KeyShortcut(carbonKeyCode: kVK_Space, carbonModifiers: controlKey | cmdKey)

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = SingleCommandDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    nonisolated static var commandDirectory: URL {
        // Contents/Helpers/PickerHost.app → outer Contents/Resources/TinycastExtension.
        Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/TinycastExtension", isDirectory: true)
    }

    static func reply(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    static func requestPaste(_ text: String, keeping: Bool, target: NSRunningApplication?) {
        var request: [String: Any] = ["text": text, "keep": keeping]
        if let target { request["pid"] = Int(target.processIdentifier) }
        if let data = try? JSONSerialization.data(withJSONObject: request) {
            reply("paste " + String(decoding: data, as: UTF8.self))
        }
    }

    static func installEditMenu() {
        let main = NSMenu()
        let editItem = main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                      ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
        }
        editItem.submenu = edit
        NSApp.mainMenu = main
    }
}

@MainActor private final class SingleCommandDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        SingleCommandMain.installEditMenu()
        Task {
            let core = AppCore.shared
            core.settings.extensionsEnabled = true
            core.extensions.start(appIndex: core.appIndex, coordinator: core.extensionCoordinator)
            await core.extensions.setEnabled(true)
            guard core.extensions.launcherEntry(forEntryID: SingleCommandMain.entry) != nil else {
                SingleCommandMain.reply("error Missing bundled UniMagic command.")
                NSApp.terminate(nil)
                return
            }
            if let mode = ProcessInfo.processInfo.environment["UNIMAGIC_APPEARANCE"],
               ProcessInfo.processInfo.environment["UNIMAGIC_FIXTURE"] == "1" {
                NSApp.appearance = NSAppearance(named: mode == "dark" ? .darkAqua : .aqua)
            }
            if ProcessInfo.processInfo.environment["UNIMAGIC_FIXTURE"] != "1" { HostInteraction.listen() }
            SingleCommandMain.reply("ready")
            do {
                for try await command in FileHandle.standardInput.bytes.lines {
                    switch command {
                    case "show":
                        if !core.paletteCoordinator.isVisible,
                           let entry = core.extensions.launcherEntry(forEntryID: SingleCommandMain.entry) {
                            // Finder/menu opening is distinct from the untouched first press of the global shortcut.
                            core.extensionCoordinator.runExtensionCommand(entry)
                        }
                    case "invoke":
                        core.extensionCoordinator.runExtensionCommand(entryID: SingleCommandMain.entry)
                    case "hide":
                        if core.paletteCoordinator.isVisible { core.paletteCoordinator.hidePalette() }
                    default: HostInteraction.handleFixture(command)
                    }
                }
            } catch {
                SingleCommandMain.reply("error Controller disconnected.")
            }
            // The controller closed the pipe, either on quit/update or if it crashed.
            NSApp.terminate(nil)
        }
    }
}
