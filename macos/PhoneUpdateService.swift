import Foundation
import SwiftUI

/// Feature consent stays on the phone. Renewal uses only the already registered frozen release.
@MainActor final class PhoneUpdateService: ObservableObject {
  static private(set) var isRunning = false
  enum Operation { case idle, checking }
  @Published private(set) var operation = Operation.idle
  @Published private(set) var message =
    "Choose paired-Mac updates on your iPhone. This Mac follows that choice while UniMagic is running."
  @Published private(set) var renewalMessage =
    "Signing renewal checks the registered frozen release every six hours, including when feature updates are off."
  private var timer: Timer?
  private var lastRenewalAttempt = Date.distantPast
  private var renewalNeedsRetry = false
  init() {
    guard ProcessInfo.processInfo.environment["UNIMAGIC_FIXTURE"] != "1" else { return }
    timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.check() }
    }
  }
  func check(manual: Bool = false) {
    guard case .idle = operation else { return }
    let resources = Bundle.main.resourceURL!
    let executable = resources.appendingPathComponent("node")
    let script = resources.appendingPathComponent("paired-mac/keeper/product-cli.mjs")
    guard FileManager.default.isReadableFile(atPath: script.path) else {
      message =
        "This build has no paired-Mac helper. Install the complete UniMagic release to check your iPhone."
      return
    }
    let renewalDue =
      Date().timeIntervalSince(lastRenewalAttempt) >= 6 * 3600 || (manual && renewalNeedsRetry)
    if renewalDue { lastRenewalAttempt = Date() }
    operation = .checking
    Self.isRunning = true
    let app = Bundle.main.bundleURL.path
    let environment = ProcessInfo.processInfo.environment.filter {
      !$0.key.hasPrefix("NODE_") && !$0.key.hasPrefix("DYLD_")
    }
    Task {
      let results = await Task.detached(priority: .utility) {
        () -> (KeeperCommandResult?, KeeperCommandResult) in
        let renewal: KeeperCommandResult? =
          renewalDue
          ? await executeKeeper(
            executable: executable, script: script, arguments: ["renew"], renewal: true,
            environment: environment) : nil
        let check = await executeKeeper(
          executable: executable, script: script,
          arguments: ["check-updates", "--trusted-app", app] + (manual ? ["--manual"] : []),
          renewal: false, environment: environment)
        return (renewal, check)
      }.value
      if let renewal = results.0 {
        renewalMessage = renewal.message
        renewalNeedsRetry = !renewal.succeeded
      }
      message = results.1.message
      operation = .idle
      Self.isRunning = false
    }
  }
}
struct PhoneUpdateSettingsView: View {
  @ObservedObject var service: PhoneUpdateService
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("iPhone updates").font(.headline)
      Text(service.message).font(.caption).frame(height: 40, alignment: .top).lineLimit(3).help(
        service.message)
      Text(service.renewalMessage).font(.caption).foregroundStyle(.secondary).frame(
        height: 40, alignment: .top
      ).lineLimit(3).help(service.renewalMessage)
      Text(
        "Automatic feature installs require the current choice on your iPhone. A manual check does not turn automatic updates on. Keep this Mac awake and the phone paired for delivery and signing renewal."
      ).font(.caption).foregroundStyle(.secondary)
      Button(service.operation == .checking ? "Checking iPhone…" : "Check iPhone updates") {
        service.check(manual: true)
      }.disabled(service.operation == .checking)
    }.frame(height: 210, alignment: .top).padding(12)
  }
}
