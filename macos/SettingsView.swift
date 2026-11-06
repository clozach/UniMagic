import AppKit
import SwiftUI

struct SettingsView: View {
  @ObservedObject var model: SettingsModel
  let dismiss: () -> Void
  @State private var filter = ""
  @State private var selectedTab =
    ProcessInfo.processInfo.environment["UNIMAGIC_CAPTURE_SETTINGS_CATEGORIES"] == "1"
    ? "categories" : "updates"
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("UniMagic Settings").font(.title2)
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      HStack {
        tab("Categories & controls", "categories")
        tab("Updates", "updates")
      }
      Group {
        if selectedTab == "categories" {
          VStack(alignment: .leading, spacing: 12) {
            TextField("Find a category", text: $filter)
            ScrollView {
              LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(
                  model.categories.filter {
                    filter.isEmpty || $0.title.localizedCaseInsensitiveContains(filter)
                  }
                ) { category in
                  Toggle(
                    category.title,
                    isOn: Binding(get: { category.enabled }, set: { _ in model.toggle(category) }))
                }
              }
            }
            if !model.message.isEmpty { Text(model.message).font(.caption) }
            Button("Install optional Tinycast command…") { installTinycast() }
            Text(
              "⌃⌘Space opens the picker. Return inserts the selected glyph. Press ⌘K for its actions, including copying, details and skin tones."
            )
            .font(.caption).foregroundStyle(.secondary)
          }.padding(12)
        } else {
          ScrollView {
            VStack(alignment: .leading, spacing: 12) {
              ReleaseSettingsView(release: model.release)
              PhoneUpdateSettingsView(service: model.phoneUpdates)
              Spacer(minLength: 0)
            }.padding(12)
          }
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
      HStack {
        Text("Mac library: ~/Library/Application Support/UniMagic/Library").font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Text(version).font(.caption.monospaced()).foregroundStyle(.secondary).frame(
          width: 125, alignment: .trailing)
      }.frame(height: 28)
    }.padding(20).frame(width: 650, height: 600).background(Color(nsColor: .windowBackgroundColor))
  }
  private func tab(_ title: String, _ id: String) -> some View {
    Button {
      selectedTab = id
    } label: {
      Text(title).frame(maxWidth: .infinity).padding(8).background(
        selectedTab == id ? Color.accentColor.opacity(0.16) : Color.clear,
        in: RoundedRectangle(cornerRadius: 6))
    }.buttonStyle(.plain)
  }
  private func installTinycast() {
    guard let folder = Bundle.main.resourceURL?.appendingPathComponent("TinycastExtension"),
      FileManager.default.fileExists(atPath: folder.path)
    else {
      model.message = "Build the optional Tinycast extension first."
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting([folder])
    let alert = NSAlert()
    alert.messageText = "Import the bundled command in Tinycast"
    alert.informativeText =
      "In Tinycast Settings → Extensions, choose Import Extension Folder and select the revealed TinycastExtension folder. Its default library is shared with this app. Keep only one global ⌃⌘Space binding."
    alert.runModal()
  }
  private var version: String {
    let info = Bundle.main.infoDictionary ?? [:]
    return
      "v\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
  }
}
