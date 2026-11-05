import AppKit
import SwiftUI

@MainActor final class ReleaseSettings: ObservableObject {
  let updates: UpdateController
  let publisher: PublishController
  @Published var revision = 0
  let configuration = ReleaseConfiguration(
    productName: "UniMagic", bundleIdentifier: "com.clozach.unimagic.mac",
    archiveBundleName: "UniMagic.app", infoPrefix: "UniMagic", supportFolder: "UniMagic/Updates",
    releasePage: URL(string: "https://github.com/clozach/UniMagic/releases/latest")!,
    publisherToolSuffix: "/tools/publisher.sh")
  init() {
    let fixture = ProcessInfo.processInfo.environment["UNIMAGIC_FIXTURE"] == "1"
    let productionSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[
        0
      ].appendingPathComponent("UniMagic/Updates")
    let support =
      fixture
      ? URL(
        fileURLWithPath: ProcessInfo.processInfo.environment["UNIMAGIC_LIBRARY"]
          ?? NSTemporaryDirectory()
      ).appendingPathComponent("Updates") : productionSupport
    updates = UpdateController(
      environment: .live(
        bundle: .main, support: support, configuration: configuration,
        isBusy: {
          DesktopBridge.hasPendingRequests
            || NSApp.windows.contains { $0.isVisible && $0.isKeyWindow }
        },
        saveBeforeQuit: { !DesktopBridge.hasPendingRequests && !PhoneUpdateService.isRunning },
        quit: { NSApp.terminate(nil) }))
    publisher = PublishController(
      environment: fixture
        ? .configured(info: [:], configuration: configuration)
        : .live(bundle: .main, configuration: configuration))
    updates.observe(owner: self) { [weak self] in self?.revision += 1 }
    publisher.observe(owner: self) { [weak self] _ in self?.revision += 1 }
    if ProcessInfo.processInfo.environment["UNIMAGIC_FIXTURE"] != "1" { updates.start() }
  }
  var snapshot: UpdateStatus.Snapshot {
    UpdateStatus.Snapshot(
      productName: "UniMagic", version: updates.runningVersion, availability: updates.availability,
      preference: updates.preference, phase: updates.phase, lastUpdate: updates.lastUpdate,
      canGoBack: updates.canGoBack, now: updates.now)
  }
  func perform(_ row: UpdateMenuRow) {
    switch row {
    case .check: Task { await updates.check() }
    case .install: if let error = updates.installNow() { show(error) }
    case .goBack: if let error = updates.goBack() { show(error) }
    case .getRelease: NSWorkspace.shared.open(configuration.releasePage)
    case .whatsNew: if let page = updates.lastUpdate?.page { NSWorkspace.shared.open(page) }
    default: break
    }
  }
  private func show(_ error: UpdateFailure) {
    let alert = NSAlert()
    alert.messageText = "Update could not finish"
    alert.informativeText = UpdateStatus.message(for: error, productName: "UniMagic")
    alert.runModal()
  }
}
struct ReleaseSettingsView: View {
  @ObservedObject var release: ReleaseSettings
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Updates").font(.headline)
      Text(UpdateStatus.line(release.snapshot)).font(.caption).fixedSize(
        horizontal: false, vertical: true)
      if case .available = release.updates.availability {
        if release.updates.preference == .unasked {
          Text(
            "Choose whether UniMagic should check, download, and install verified releases while idle. No update check runs before your choice."
          ).font(.caption)
          HStack {
            Button("Enable automatic updates") { release.updates.choose(.automatic) }
            Button("Keep updates manual") { release.updates.choose(.manual) }
          }
        } else {
          Toggle(
            "Automatic updates",
            isOn: Binding(
              get: { release.updates.preference == .automatic },
              set: { release.updates.choose($0 ? .automatic : .manual) })
          ).toggleStyle(.checkbox)
        }
      }
      HStack {
        ForEach(Array(UpdateStatus.rows(release.snapshot).enumerated()), id: \.offset) { _, row in
          action(row)
        }
      }
      if release.publisher.presentation.isVisible {
        Button(release.publisher.presentation.title) {
          release.publisher.performAction(presenting: NSApp.keyWindow)
        }.disabled(!release.publisher.presentation.isEnabled).help(
          release.publisher.presentation.help)
      }
    }.frame(height: 185, alignment: .top).padding(12).background(
      Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
  }
  @ViewBuilder private func action(_ row: UpdateMenuRow) -> some View {
    switch row {
    case .check(let enabled): Button("Check now") { release.perform(row) }.disabled(!enabled)
    case .install(let title), .goBack(let title), .whatsNew(let title):
      Button(title) { release.perform(row) }
    case .getRelease: Button("Get release") { release.perform(row) }
    default: EmptyView()
    }
  }
}
