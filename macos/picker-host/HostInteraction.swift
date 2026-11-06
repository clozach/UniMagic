// SPDX-License-Identifier: AGPL-3.0-or-later
import AppKit
import CoreFoundation
import Carbon

/// Tinycast can own the global shortcut while this independent nonactivating
/// panel is key. Only its foreground panel may consume that forwarded chord.
@MainActor enum HostInteraction {
    private static var port: CFMessagePort?
    static func listen() {
        let callback: CFMessagePortCallBack = { _, message, data, _ in
            let consumed = MainActor.assumeIsolated {
                let core = AppCore.shared
                guard message == 1, let data,
                      String(data: data as Data, encoding: .utf8) == "invoke",
                      core.paletteCoordinator.isVisible, NSApp.keyWindow is PalettePanel, NSApp.keyWindow?.isKeyWindow == true
                else { return false }
                core.extensionCoordinator.runExtensionCommand(entryID: SingleCommandMain.entry)
                return true
            }
            return Unmanaged.passRetained(Data((consumed ? "1" : "0").utf8) as CFData)
        }
        guard let channel = CFMessagePortCreateLocal(nil, "com.clozach.unimagic.mac.picker.invoke" as CFString,
                                                     callback, nil, nil),
              let source = CFMessagePortCreateRunLoopSource(nil, channel, 0) else { return }
        port = channel
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    /// Window-local verification channel, accessible only to the process's
    /// parent through stdin and only with an explicit disposable fixture home.
    static func handleFixture(_ command: String) {
        let env = ProcessInfo.processInfo.environment
        guard env["UNIMAGIC_FIXTURE"] == "1", env["UNIMAGIC_FIXTURE_HOME"] != nil else { return }
        let core = AppCore.shared
        let panel = NSApp.windows.compactMap { $0 as? PalettePanel }.first(where: { $0.isVisible })
        if command == "focus", let panel, let content = panel.contentView,
           let field = searchField(in: content) {
            _ = panel.makeFirstResponder(field)
        } else if command == "scrollEnd", let panel, let content = panel.contentView,
                  let scroll = scrollingGrid(in: content), let document = scroll.documentView {
            let bottom = max(0, document.bounds.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: .init(x: 0, y: document.isFlipped ? bottom : 0))
            scroll.reflectScrolledClipView(scroll.contentView)
        } else if command.hasPrefix("key "), let panel {
            sendKey(String(command.dropFirst(4)), to: panel)
        } else if command.hasPrefix("query ") {
            core.palette.query = String(command.dropFirst(6))
        } else if command == "state" {
            var state: [String: Any] = ["visible": core.paletteCoordinator.isVisible, "query": core.palette.query,
                                        "selected": core.palette.selection, "depth": core.extensions.navigationDepth]
            state["appearance"] = panel?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])?.rawValue
            if let field = panel?.firstResponder as? NSTextView {
                state["field"] = field.string
                state["range"] = [field.selectedRange().location, field.selectedRange().length]
            }
            switch core.extensions.state {
            case .rendered(let tree):
                let screen = ExtensionScreen(tree: tree, query: core.palette.query)
                state["count"] = screen.items.count
                state["title"] = screen.navigationTitle
                state["items"] = screen.items.prefix(12).map { $0.node.string("title") ?? $0.node.string("id") ?? "" }
                state["actions"] = ExtensionScreen.actions(in: screen.actionPanel(forItemAt: core.palette.selection)).map(\.title)
            case .failed(let error): state["error"] = error
            default: break
            }
            if let data = try? JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]) {
                SingleCommandMain.reply(String(decoding: data, as: UTF8.self))
            }
        } else if command.hasPrefix("capture ") {
            let url = URL(fileURLWithPath: String(command.dropFirst(8)))
            guard let view = NSApp.windows.first(where: { $0 is PalettePanel && $0.isVisible })?.contentView,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            do {
                guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
                try data.write(to: url, options: .atomic)
                SingleCommandMain.reply("captured")
            } catch { SingleCommandMain.reply("error " + error.localizedDescription) }
        }
    }
    private static func scrollingGrid(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView, let doc = scroll.documentView,
           doc.bounds.height > scroll.contentView.bounds.height * 2 { return scroll }
        for child in view.subviews {
            if let scroll = scrollingGrid(in: child) { return scroll }
        }
        return nil
    }

    private static func searchField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable, !field.isHidden { return field }
        for child in view.subviews {
            if let field = searchField(in: child) { return field }
        }
        return nil
    }

    private static func sendKey(_ name: String, to panel: PalettePanel) {
        let key: (code: Int, characters: String, flags: NSEvent.ModifierFlags)
        switch name {
        case "selectAll": key = (kVK_ANSI_A, "a", .command)
        case "right": key = (kVK_RightArrow, "\u{f703}", [.function, .numericPad])
        case "left": key = (kVK_LeftArrow, "\u{f702}", [.function, .numericPad])
        case "down": key = (kVK_DownArrow, "\u{f701}", [.function, .numericPad])
        case "up": key = (kVK_UpArrow, "\u{f700}", [.function, .numericPad])
        case "escape": key = (kVK_Escape, "\u{1B}", [])
        case "x": key = (kVK_ANSI_X, "x", [])
        default: return
        }
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: key.flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
            context: nil, characters: key.characters, charactersIgnoringModifiers: key.characters,
            isARepeat: false, keyCode: UInt16(key.code)) else { return }
        // Send only to this process's exact panel. Never post input to the WindowServer.
        if panel.performKeyEquivalent(with: event) { return }
        if !event.modifierFlags.isDisjoint(with: .command), NSApp.mainMenu?.performKeyEquivalent(with: event) == true { return }
        panel.sendEvent(event)
    }

}
