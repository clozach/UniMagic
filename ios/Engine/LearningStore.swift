import Foundation

public struct LearnedAlias: Codable, Sendable, Equatable {
    public enum AliasType: String, Codable, Sendable { case learned, provisional }
    public var term: String
    public var hexseq: String
    public var type: AliasType
    public var score: Int
    public init(term: String, hexseq: String, type: AliasType, score: Int) {
        self.term = term; self.hexseq = hexseq; self.type = type; self.score = score
    }
}

public struct UsageEntry: Codable, Sendable, Equatable {
    public var hexseq: String
    public var count: Int
    public var lastUsed: Double?
    public var symbol: String?
    public init(hexseq: String, count: Int, lastUsed: Double? = nil, symbol: String? = nil) {
        self.hexseq = hexseq; self.count = count; self.lastUsed = lastUsed; self.symbol = symbol
    }
}

/// Pure store transforms. The host owns shared-container persistence and merging.
public struct LearningStore: Codable, Sendable, Equatable {
    public var version: Int = 1
    public var learned: [LearnedAlias] = []
    public var usage: [UsageEntry] = []
    public init() {}

    public func pick(query: String, hexseq: String, symbol: String? = nil, at timestamp: Double = 0) -> LearningStore {
        var next = self
        let words = query.lowercased().split(whereSeparator: { $0.isWhitespace })
            .map(String.init).filter { !$0.hasSuffixEmoji }
        if let last = words.last { next.vote(term: last, hexseq: hexseq, type: .learned) }
        if words.count > 1 { next.vote(term: words[words.count - 2], hexseq: hexseq, type: .provisional) }
        if let index = next.usage.firstIndex(where: { $0.hexseq == hexseq }) {
            next.usage[index].count += 1
            next.usage[index].lastUsed = timestamp
            next.usage[index].symbol = symbol
        } else { next.usage.append(UsageEntry(hexseq: hexseq, count: 1, lastUsed: timestamp, symbol: symbol)) }
        return next
    }

    public func teach(term: String, hexseq: String) -> LearningStore {
        var next = self
        let normalized = term.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.isEmpty { next.vote(term: normalized, hexseq: hexseq, type: .provisional) }
        return next
    }

    public func unlearn(term: String, hexseq: String) -> LearningStore {
        var next = self
        next.learned.removeAll { $0.term == term && $0.hexseq == hexseq }
        return next
    }

    private mutating func vote(term: String, hexseq: String, type: LearnedAlias.AliasType) {
        if let index = learned.firstIndex(where: { $0.term == term && $0.hexseq == hexseq }) {
            if type == .learned { learned[index].type = .learned }
            learned[index].score += 1
        } else { learned.append(LearnedAlias(term: term, hexseq: hexseq, type: type, score: type == .learned ? 1 : 0)) }
    }
}

private extension String {
    var hasSuffixEmoji: Bool {
        // Match canonical Extended_Pictographic, not isEmoji (which includes digits).
        range(of: "\\p{Extended_Pictographic}$", options: .regularExpression) != nil
    }
}
