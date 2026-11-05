import SwiftUI

struct PickerHelp: View {
    let host: PickerHost
    @State private var testText = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("Use Unimagic") {
                    Text(host.inserts ? "Search with the keys below. Tap a character to insert it in your text." : "Search, then tap a character to copy it. Return to your app and paste.")
                    Text("Hold a character for details, skin tones and learned words. VoiceOver users can choose its Details action. Show in category opens the character beside its neighbors; Back returns to your previous view.")
                    Text("Use as category symbol changes a category's symbol. Reset default restores its original symbol. Choose visible categories in Category settings.")
                }
                Section("Control Center") {
                    Text("Open Control Center, touch and hold an empty area, tap Add a Control → Shortcut → Choose → Open-Unimagic.")
                    if let shortcut = Bundle.main.url(forResource: "Open-Unimagic", withExtension: "shortcut") {
                        ShareLink("Add shortcut", item: shortcut)
                        Text("Open the shared shortcut in Shortcuts and add it before choosing it in Control Center.")
                    }
                }
                Section("Add the keyboard") {
                    Text("Open Settings → General → Keyboard → Keyboards → Add New Keyboard → \(host == .agentAlerts ? "PowWorm!" : "Unimagic"). Then hold the globe key in any text field and choose \(host == .agentAlerts ? "UniMagic" : "Unimagic").")
                    Text("Full Access is not required. Secure password fields, phone fields and apps that disable custom keyboards use Apple's keyboard.")
                }
                if !host.inserts {
                    Section("Try the keyboard") {
                        TextField("Try Unimagic here", text: $testText, axis: .vertical)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .accessibilityIdentifier("keyboard-test-field")
                    }
                }
                Section("Privacy") {
                    Text(host == .agentAlerts
                        ? "Unimagic search works offline. History, learned words and category symbols stay separately in this app and its keyboard on this device. The app shares only your visible-category choices with its keyboard. Your Unimagic queries and learning are not sent to PowWorm or synced with Obsidian or Tinycast."
                        : "Search works offline. Unimagic has no network access and does not read your surrounding text. History, learned words and category symbols stay separately in the app and keyboard. They do not sync with each other, Obsidian or Tinycast.")
                }
                Section("Sources") {
                    NavigationLink("Full licenses and notices") { NoticesView() }
                    Text("Unicode character data © Unicode, Inc., Unicode License v3. Emoji names and keywords: emojibase, MIT license. HTML entity names: WHATWG. Curated glyph data: Glyphfinder. Full source notices are included with this app.")
                }
            }.navigationTitle("Unimagic help").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}


private struct NoticesView: View {
    private var notices: String {
        guard let url = Bundle.main.url(forResource: "Notices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "Notices unavailable in this build."
        }
        return text
    }
    var body: some View {
        ScrollView {
            Text(notices).font(.body).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading).padding()
        }.navigationTitle("Licenses and notices").navigationBarTitleDisplayMode(.inline)
    }
}
