import Foundation

/// Only category visibility crosses app → keyboard; local history/exemplars do not.
public enum NativeVisibilityAccess: Sendable {
    case local, appPublisher(URL), keyboardReader(URL)
    public static func production(for host: HistoryHost) -> Self {
        #if os(iOS)
        guard let group = Bundle.main.object(forInfoDictionaryKey: "UniMagicVisibilityAppGroup") as? String,
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return .local }
        let file = NativePersonalizationPaths.sharedDirectory(inGroupRoot: root).appendingPathComponent("browse-visibility-v1.json")
        return host == .nativeKeyboard ? .keyboardReader(file) : .appPublisher(file)
        #else
        return .local
        #endif
    }
    public var canPublish: Bool { if case .appPublisher = self { return true }; return false }
    public var isReader: Bool { if case .keyboardReader = self { return true }; return false }
}

struct NativeVisibilityDocument: Codable {
    var schemaVersion = 1
    let catalogueRevision: String
    let categoryVisibility: [String: Bool]
    init(_ preferences: BrowsePreferences) { catalogueRevision = preferences.catalogueRevision; categoryVisibility = preferences.categoryVisibility }
}

func effectiveVisibility(_ local: BrowsePreferences, access: NativeVisibilityAccess) throws -> BrowsePreferences {
    guard case .keyboardReader(let file) = access, FileManager.default.fileExists(atPath: file.path) else { return local }
    let shared = try JSONDecoder().decode(NativeVisibilityDocument.self, from: Data(contentsOf: file))
    guard shared.schemaVersion == 1 else { throw NativeStoreError.unsupportedVersion(shared.schemaVersion) }
    var result = local
    result.categoryVisibility = shared.categoryVisibility
    return result
}

func publishVisibility(_ preferences: BrowsePreferences, access: NativeVisibilityAccess) throws {
    guard case .appPublisher(let file) = access else { return }
    var raw: [String: Any] = [:]
    if FileManager.default.fileExists(atPath: file.path) {
        let data = try Data(contentsOf: file)
        guard let saved = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = saved["schemaVersion"] as? Int else { throw NativeStoreError.invalidDocument("Invalid visibility document") }
        guard version == 1 else { throw NativeStoreError.unsupportedVersion(version) }
        _ = try JSONDecoder().decode(NativeVisibilityDocument.self, from: data)
        raw = saved
    }
    raw["schemaVersion"] = 1
    raw["catalogueRevision"] = preferences.catalogueRevision
    raw["categoryVisibility"] = preferences.categoryVisibility
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys]).write(to: file, options: .atomic)
}
