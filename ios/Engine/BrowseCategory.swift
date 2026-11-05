import Foundation

/// Metadata stays lightweight; occurrence pages remain in SQLite until requested.
public struct BrowseCategory: Identifiable, Equatable, Sendable, Decodable {
    public let id: String
    public let title: String
    public let source: Source
    public let defaultEnabled: Bool
    public let defaultExemplar: CategoryExemplar
    public let orderKey: [UInt32]
    public let memberCount: Int
    public let membership: Membership
    public var exemplarOverride: CategoryExemplar?
    public var exemplar: CategoryExemplar { exemplarOverride ?? defaultExemplar }
    public var symbol: String { exemplar.symbol }
    public var isUtility: Bool { if case .utility = source { return true }; return false }
    public var isRecent: Bool { source == .utility(.recents) }

    private enum CodingKeys: String, CodingKey { case id, title, source, defaultEnabled, defaultExemplar, orderKey, memberCount, membership }
    public enum Utility: String, Codable, Sendable { case recents, frequent }
    public enum Membership: String, Decodable, Sendable {
        case sourceRule = "source-rule", explicit
        private enum Keys: String, CodingKey { case kind }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            guard let value = Self(rawValue: try c.decode(String.self, forKey: .kind)) else { throw NativeStoreError.invalidDocument("Unknown category membership") }
            self = value
        }
    }
    public enum Source: Equatable, Sendable, Decodable {
        case curatedSet(String), legacyRanges([ClosedRange<UInt32>]), unichar(String), block(String, UInt32), utility(Utility)
        private enum Keys: String, CodingKey { case kind, set, ranges, referenceID, block, startScalar, utility }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            switch try c.decode(String.self, forKey: .kind) {
            case "curated-set": self = .curatedSet(try c.decode(String.self, forKey: .set))
            case "unichar-observed": self = .unichar(try c.decode(String.self, forKey: .referenceID))
            case "unicode-block": self = .block(try c.decode(String.self, forKey: .block), try c.decode(UInt32.self, forKey: .startScalar))
            case "utility": self = .utility(try c.decode(Utility.self, forKey: .utility))
            case "legacy-ranges":
                let ranges = try c.decode([[UInt32]].self, forKey: .ranges)
                guard ranges.allSatisfy({ $0.count == 2 && $0[0] <= $0[1] && $0[1] <= 0x10FFFF }) else { throw NativeStoreError.invalidDocument("Invalid category scalar range") }
                self = .legacyRanges(ranges.map { $0[0]...$0[1] })
            default: throw NativeStoreError.invalidDocument("Unknown category source")
            }
        }
    }
}

public struct BrowseOccurrence: Identifiable, Sendable {
    public enum Provenance: Sendable { case catalogue, history(PickHistoryEvent) }
    public let id: String
    public let categoryID: String
    public let position: Int
    public let glyph: Glyph
    public let provenance: Provenance
    public var origin: BrowseOrigin { BrowseOrigin(categoryID: categoryID, occurrenceID: id) }
    public var sourceOrigin: BrowseOrigin? { if case .history(let event) = provenance { return event.origin }; return origin }
    public init(id: String, categoryID: String, position: Int, glyph: Glyph, provenance: Provenance = .catalogue) {
        self.id = id; self.categoryID = categoryID; self.position = position; self.glyph = glyph; self.provenance = provenance
    }
}

public enum BrowseItemCount: Equatable, Sendable { case known(Int), unknown; public var value: Int? { if case .known(let n) = self { return n }; return nil } }

public enum BrowseCursor: Equatable, Sendable {
    case offset(Int)
    case history(cursor: String?, position: Int)
    /// A jump inside the same frozen history traversal, relative to a known page boundary.
    case historySeek(after: String, boundary: Int, position: Int)
}
public struct BrowsePage: Sendable {
    public let items: [BrowseOccurrence]
    public let nextCursor: BrowseCursor?
    public let startOffset: Int
    public let totalCount: BrowseItemCount
    public var glyphs: [Glyph] { items.map(\.glyph) }
    public var hasMore: Bool { nextCursor != nil }
    public var nextOffset: Int { if case .offset(let n) = nextCursor { return n }; return startOffset + items.count }
    public init(items: [BrowseOccurrence], nextCursor: BrowseCursor?, startOffset: Int = 0, totalCount: BrowseItemCount = .unknown) {
        self.items = items; self.nextCursor = nextCursor; self.startOffset = startOffset; self.totalCount = totalCount
    }
}

public struct BrowseContextTarget: Identifiable, Sendable {
    public enum Match: Sendable { case exactOccurrence, canonicalVariant }
    public let categoryID: String
    public let occurrenceID: String
    public let position: Int
    public let glyph: Glyph
    public let match: Match
    public var id: String { occurrenceID }
    public init(categoryID: String, occurrenceID: String, position: Int, glyph: Glyph, match: Match) {
        self.categoryID = categoryID; self.occurrenceID = occurrenceID; self.position = position; self.glyph = glyph; self.match = match
    }
}

public enum BrowseNavigationTarget: Identifiable, Sendable {
    case section(UUID, categoryID: String), occurrence(UUID, BrowseContextTarget)
    public var id: UUID { switch self { case .section(let id, _), .occurrence(let id, _): return id } }
    public var categoryID: String { switch self { case .section(_, let id): return id; case .occurrence(_, let target): return target.categoryID } }
}
