import Foundation

public enum CategoryExemplar: Equatable, Sendable, Codable {
    case unicode(String), emoji(String), customFont(String)
    private enum Keys: String, CodingKey { case kind, symbol, font }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let symbol = try c.decode(String.self, forKey: .symbol)
        guard !symbol.isEmpty else { throw NativeStoreError.invalidDocument("Empty exemplar") }
        switch try c.decode(String.self, forKey: .kind) {
        case "unicode": self = .unicode(symbol)
        case "emoji": self = .emoji(symbol)
        case "custom-font":
            guard try c.decode(String.self, forKey: .font) == "UniCharCategories" else { throw NativeStoreError.invalidDocument("Unknown icon font") }
            self = .customFont(symbol)
        default: throw NativeStoreError.invalidDocument("Unknown exemplar kind")
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .unicode(let s): try c.encode("unicode", forKey: .kind); try c.encode(s, forKey: .symbol)
        case .emoji(let s): try c.encode("emoji", forKey: .kind); try c.encode(s, forKey: .symbol)
        case .customFont(let s):
            try c.encode("custom-font", forKey: .kind); try c.encode(s, forKey: .symbol); try c.encode("UniCharCategories", forKey: .font)
        }
    }
    public var symbol: String { switch self { case .unicode(let s), .emoji(let s), .customFont(let s): return s } }
}

public struct BrowsePreferences: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var catalogueRevision: String
    public var categoryVisibility: [String: Bool] = [:]
    public var exemplarOverrides: [String: CategoryExemplar] = [:]
    public var appliedMigrations: [String] = []
    public init(catalogueRevision: String) { self.catalogueRevision = catalogueRevision }
}

public struct BrowseOrigin: Codable, Equatable, Sendable {
    public var categoryID: String
    public var occurrenceID: String
    public init(categoryID: String, occurrenceID: String) { self.categoryID = categoryID; self.occurrenceID = occurrenceID }
}

public enum HistoryHost: String, Codable, Sendable { case nativeApp = "native-app", nativeKeyboard = "native-keyboard", tinycast, obsidian }
public enum HistoryAction: String, Codable, Sendable { case copy, insert }
public enum HistoryProvenance: Codable, Equatable, Sendable {
    case pick(host: HistoryHost, action: HistoryAction)
    case snapshotImport(importID: String, source: String, position: Int)
    case legacyAggregate(source: String, count: Int)
    private enum Keys: String, CodingKey { case kind, host, action, importID, source, position, count }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "pick": self = .pick(host: try c.decode(HistoryHost.self, forKey: .host), action: try c.decode(HistoryAction.self, forKey: .action))
        case "snapshot-import": self = .snapshotImport(importID: try c.decode(String.self, forKey: .importID), source: try c.decode(String.self, forKey: .source), position: try c.decode(Int.self, forKey: .position))
        case "legacy-aggregate": self = .legacyAggregate(source: try c.decode(String.self, forKey: .source), count: try c.decode(Int.self, forKey: .count))
        default: throw NativeStoreError.invalidDocument("Unknown history provenance")
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        switch self {
        case .pick(let host, let action): try c.encode("pick", forKey: .kind); try c.encode(host, forKey: .host); try c.encode(action, forKey: .action)
        case .snapshotImport(let id, let source, let position):
            try c.encode("snapshot-import", forKey: .kind); try c.encode(id, forKey: .importID); try c.encode(source, forKey: .source); try c.encode(position, forKey: .position)
        case .legacyAggregate(let source, let count):
            try c.encode("legacy-aggregate", forKey: .kind); try c.encode(source, forKey: .source); try c.encode(count, forKey: .count)
        }
    }
}

public struct PickHistoryEvent: Codable, Equatable, Sendable {
    public var eventID: String
    public var glyphID: String
    public var symbol: String
    public var occurredAt: Double?
    public var provenance: HistoryProvenance
    public var origin: BrowseOrigin?
    public init(eventID: String = UUID().uuidString, glyphID: String, symbol: String, occurredAt: Double?, provenance: HistoryProvenance, origin: BrowseOrigin? = nil) {
        self.eventID = eventID; self.glyphID = glyphID; self.symbol = symbol; self.occurredAt = occurredAt; self.provenance = provenance; self.origin = origin
    }
    // Null is meaningful on the wire: a snapshot does not invent a past date.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(eventID, forKey: .eventID); try c.encode(glyphID, forKey: .glyphID); try c.encode(symbol, forKey: .symbol)
        try c.encode(occurredAt, forKey: .occurredAt); try c.encode(provenance, forKey: .provenance); try c.encodeIfPresent(origin, forKey: .origin)
    }
}

public struct PickHistoryDocument: Codable, Sendable {
    public var schemaVersion = 1
    public var events: [PickHistoryEvent] = []
    public var appliedImports: [String] = []
    public init() {}
}
public struct PickHistoryPage: Sendable { public let events: [PickHistoryEvent]; public let nextCursor: String? }
public struct PickHistoryImport: Sendable {
    public let importID: String
    public let events: [PickHistoryEvent]
    public init(importID: String, events: [PickHistoryEvent]) { self.importID = importID; self.events = events }
}
public struct HistoryImportResult: Sendable { public let imported: Int; public let alreadyApplied: Bool }

public enum NativePersonalizationLocation: Sendable {
    case sharedReadWrite(URL), sharedReadOnly(URL), local(URL)
    public var directory: URL { switch self { case .sharedReadWrite(let u), .sharedReadOnly(let u), .local(let u): return u } }
    public var isWritable: Bool { if case .sharedReadOnly = self { return false }; return true }
    public var isShared: Bool { if case .local = self { return false }; return true }
}
public enum NativePersonalizationPaths {
    public static let groupRelativeDirectory = "Library/Application Support/UniMagic"
    public static let localRelativeDirectory = "UniMagic/LocalPersonalization"
    public static func sharedDirectory(inGroupRoot root: URL) -> URL { root.appendingPathComponent(groupRelativeDirectory, isDirectory: true) }
    public static func localDirectory(inApplicationSupport root: URL) -> URL { root.appendingPathComponent(localRelativeDirectory, isDirectory: true) }
}
public enum NativeStoreError: Error, CustomStringConvertible {
    case readOnly, invalidDocument(String), unsupportedVersion(Int), sqlite(String), invalidCursor
    public var description: String {
        switch self {
        case .readOnly: return "Shared personalization is read-only. Changes need an explicitly selected writable store."
        case .invalidDocument(let s): return "Personalization data preserved: \(s)"
        case .unsupportedVersion(let v): return "Unsupported personalization version \(v); existing data preserved."
        case .sqlite(let s): return "Personalization storage: \(s)"
        case .invalidCursor: return "History page cursor is no longer valid."
        }
    }
}
