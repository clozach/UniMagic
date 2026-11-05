import SwiftUI
import Foundation

/// App-local authority. The keyboard never reads or writes this document.
struct PairedMacUpdatePolicy: Codable, Equatable {
    let schemaVersion: Int
    let product: String
    let automaticUpdates: Bool
    let revision: String
    let manualCheckRequest: String?
    static let filename = "paired-mac-updates-v1.json"
    static func decode(_ data: Data) throws -> Self {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys).isSubset(of: ["schemaVersion", "product", "automaticUpdates", "revision", "manualCheckRequest"]) else { throw CocoaError(.coderReadCorrupt) }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == 1, value.product == "com.clozach.unimagic", UUID(uuidString: value.revision) != nil,
              value.manualCheckRequest == nil || UUID(uuidString: value.manualCheckRequest!) != nil else { throw CocoaError(.coderReadCorrupt) }
        return value
    }
    static var off: Self { Self(schemaVersion: 1, product: "com.clozach.unimagic", automaticUpdates: false, revision: UUID().uuidString, manualCheckRequest: nil) }
}

@MainActor final class PairedMacUpdates: ObservableObject {
    @Published private(set) var policy = PairedMacUpdatePolicy.off
    @Published private(set) var status = "Updates stay off until you turn them on."
    private let file: URL
    private let statusFile: URL
    private struct MacStatus: Decodable { let schemaVersion: Int; let product: String; let revision: String; let state: String; let message: String }
    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]) {
        file = directory.appendingPathComponent(PairedMacUpdatePolicy.filename)
        statusFile = directory.appendingPathComponent("paired-mac-update-status-v1.json")
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let value = try PairedMacUpdatePolicy.decode(Data(contentsOf: file))
                policy = value
                status = value.automaticUpdates ? "Waiting for your paired Mac." : "Automatic updates are off."
            } catch { status = "Saved update choice unavailable. Updates are off; choose again to save a new choice." }
        }
    }
    func refreshStatus() {
        guard let data = try? Data(contentsOf: statusFile),
              let saved = try? JSONDecoder().decode(MacStatus.self, from: data),
              saved.schemaVersion == 1, saved.product == policy.product, saved.revision == policy.revision,
              ["off", "waiting", "current", "available", "installed", "error"].contains(saved.state) else { return }
        status = saved.message
    }
    func setAutomatic(_ enabled: Bool) {
        save(PairedMacUpdatePolicy(schemaVersion: 1, product: policy.product, automaticUpdates: enabled,
                                  revision: UUID().uuidString, manualCheckRequest: policy.manualCheckRequest),
             message: enabled ? "Waiting for your paired Mac." : "Automatic updates are off.")
    }
    func requestCheck() {
        save(PairedMacUpdatePolicy(schemaVersion: 1, product: policy.product, automaticUpdates: policy.automaticUpdates,
                                  revision: UUID().uuidString, manualCheckRequest: UUID().uuidString),
             message: "Check requested. Connect to your paired Mac; check its delivery status for the result.")
    }
    private func save(_ value: PairedMacUpdatePolicy, message: String) {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(value).write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
            policy = value; status = message
        } catch { status = "Could not save your update choice. Open Settings again and retry." }
    }
}

struct PairedMacUpdateSettings: View {
    @StateObject private var updates = PairedMacUpdates()
    var body: some View {
        Section("Updates through your Mac") {
            HStack(spacing: 16) {
                Text("Install updates through my paired Mac").fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("Install updates through my paired Mac", isOn: Binding(get: { updates.policy.automaticUpdates }, set: updates.setAutomatic))
                    .labelsHidden().fixedSize().accessibilityIdentifier("paired-mac-updates")
            }
            Text("Off until you choose. Your paired Mac installs verified releases when this iPhone and signing are available. Turn this off here at any time. Signing renewal keeps the same release.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Check for updates") { updates.requestCheck() }.accessibilityIdentifier("paired-mac-check")
            ScrollView(.vertical) {
                Text(updates.status).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .accessibilityIdentifier("paired-mac-status")
            }.frame(height: 72)
        }.task {
            while !Task.isCancelled { updates.refreshStatus(); try? await Task.sleep(for: .seconds(5)) }
        }
    }
}

struct AppVersionCorner: View {
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }
    var body: some View {
        Text("\(version) (\(build))").font(.caption2).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing).frame(height: 24)
            .padding(.horizontal, 20).accessibilityIdentifier("settings-version")
    }
}
