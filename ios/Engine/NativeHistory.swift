import Foundation

private struct HistoryCursor: Codable { let sequence: Int64; let occurredAt: Double? }
private enum HistoryImportMode { case additive, once }

extension NativePersonalizationStore {
    public func historyCount() throws -> Int { try locked { Int(try integer("SELECT COUNT(*) FROM history")) } }
    public func appendHistoryEvent(_ event: PickHistoryEvent) throws {
        try transaction { try self.insertHistory(event) }
    }
    public func readHistoryPage(cursor: String? = nil, limit: Int = 100, skipping: Int = 0) throws -> PickHistoryPage {
        guard (1...500).contains(limit) else { throw NativeStoreError.invalidDocument("History page size must be 1–500") }
        guard skipping >= 0 else { throw NativeStoreError.invalidCursor }
        return try locked {
            let query = try historyPageQuery(cursor: cursor, limit: limit)
            let page = try rows(query.sql + " OFFSET ?", query.values + [.integer(Int64(skipping))])
            let visible = Array(page.prefix(limit))
            let events = try visible.map { try JSONDecoder().decode(PickHistoryEvent.self, from: Data(($0["payload"] ?? "").utf8)) }
            var next: String?
            if page.count > limit, let last = visible.last, let sequence = Int64(last["sequence"] ?? ""), let event = events.last {
                next = try JSONEncoder().encode(HistoryCursor(sequence: sequence, occurredAt: event.occurredAt)).base64EncodedString()
            }
            return PickHistoryPage(events: events, nextCursor: next)
        }
    }
    // DESC already puts NULL dates last. The compound dated/undated query lets
    // SQLite merge two ordered index ranges without sorting the whole history.
    func historyPageQuery(cursor: String?, limit: Int) throws -> (sql: String, values: [Parameter]) {
        let columns = "SELECT sequence,occurred_at,payload FROM history"
        let order = " ORDER BY occurred_at DESC,sequence DESC LIMIT ?"
        guard let cursor else { return (columns + order, [.integer(Int64(limit + 1))]) }
        guard let data = Data(base64Encoded: cursor), let c = try? JSONDecoder().decode(HistoryCursor.self, from: data), c.occurredAt?.isFinite != false else { throw NativeStoreError.invalidCursor }
        if let time = c.occurredAt {
            return (columns + " WHERE (occurred_at,sequence) < (?,?) UNION ALL " + columns + " WHERE occurred_at IS NULL" + order,
                    [.number(time), .integer(c.sequence), .integer(Int64(limit + 1))])
        }
        return (columns + " WHERE occurred_at IS NULL AND sequence < ?" + order, [.integer(c.sequence), .integer(Int64(limit + 1))])
    }
    public func importHistory(_ snapshot: PickHistoryImport) throws -> HistoryImportResult {
        try importHistory(snapshot, mode: .additive)
    }
    /// Seals the initial source snapshot, including an empty one. Later source
    /// changes must not be manufactured into additional legacy history events.
    public func importHistoryOnce(_ snapshot: PickHistoryImport) throws -> HistoryImportResult {
        try importHistory(snapshot, mode: .once)
    }
    private func importHistory(_ snapshot: PickHistoryImport, mode: HistoryImportMode) throws -> HistoryImportResult {
        guard !snapshot.importID.isEmpty else { throw NativeStoreError.invalidDocument("Empty import ID") }
        return try transaction {
            let prior = try self.rows("SELECT import_id,base_sequence FROM history_imports WHERE import_id=?", [.text(snapshot.importID)]).first
            if case .once = mode, prior != nil { return HistoryImportResult(imported: 0, alreadyApplied: true) }
            let positions = snapshot.events.compactMap { self.snapshotPosition($0, importID: snapshot.importID) }
            let base: Int64?
            if !positions.isEmpty {
                if let saved = prior?["base_sequence"], let n = Int64(saved) { base = n }
                else {
                    base = try self.historyFloor() - 1
                    try self.execute("INSERT INTO history_imports(import_id,base_sequence,reservation_size) VALUES(?,?,1000000) ON CONFLICT(import_id) DO UPDATE SET base_sequence=excluded.base_sequence,reservation_size=excluded.reservation_size", [.text(snapshot.importID), .integer(base!)])
                    // Upgrade a prior partial v1 import once; retain its exact IDs
                    // and strings while restoring its original sparse positions.
                    if prior != nil {
                        for row in try self.rows("SELECT event_id,payload FROM history") {
                            let old = try JSONDecoder().decode(PickHistoryEvent.self, from: Data((row["payload"] ?? "").utf8))
                            if let position = self.snapshotPosition(old, importID: snapshot.importID) {
                                try self.validateSnapshotPosition(position)
                                try self.execute("UPDATE history SET sequence=? WHERE event_id=?", [.integer(base! - Int64(position)), .text(old.eventID)])
                            }
                        }
                    }
                }
            } else { base = nil }
            var imported = 0
            for event in snapshot.events {
                if try !self.rows("SELECT event_id FROM history WHERE event_id=?", [.text(event.eventID)]).isEmpty { continue }
                if let position = self.snapshotPosition(event, importID: snapshot.importID), let base {
                    try self.validateSnapshotPosition(position)
                    try self.insertHistory(event, sequence: base - Int64(position))
                    imported += 1
                } else { imported += try self.mergeEvents([event]) }
            }
            try self.execute("INSERT OR IGNORE INTO history_imports(import_id) VALUES(?)", [.text(snapshot.importID)])
            return HistoryImportResult(imported: imported, alreadyApplied: prior != nil && imported == 0)
        }
    }
    /// Used for local fallback → shared promotion. Stable IDs make every retry safe.
    /// Iterate bounded source pages; no import marker hides later local events.
    public func mergeHistoryEvents(_ events: [PickHistoryEvent]) throws -> Int { try transaction { try self.mergeEvents(events) } }

    private func mergeEvents(_ events: [PickHistoryEvent]) throws -> Int {
        var sequence = try historyFloor() - 1
        var imported = 0
        for event in events {
            let exists = try !rows("SELECT event_id FROM history WHERE event_id=?", [.text(event.eventID)]).isEmpty
            if !exists { try insertHistory(event, sequence: sequence); imported += 1; sequence -= 1 }
        }
        return imported
    }
    private func historyFloor() throws -> Int64 {
        let floor = try integer("SELECT MIN(value) FROM (SELECT COALESCE(MIN(sequence),0) AS value FROM history UNION ALL SELECT MIN(base_sequence-reservation_size+1) FROM history_imports WHERE base_sequence IS NOT NULL)")
        guard floor > Int64.min + 1_000_001 else { throw NativeStoreError.invalidDocument("History sequence capacity exhausted") }
        return floor
    }
    private func snapshotPosition(_ event: PickHistoryEvent, importID: String) -> Int? {
        if case .snapshotImport(let id, _, let position) = event.provenance, id == importID { return position }
        return nil
    }
    private func validateSnapshotPosition(_ position: Int) throws {
        guard (0..<1_000_000).contains(position) else { throw NativeStoreError.invalidDocument("Snapshot position exceeds reserved range") }
    }
    private func insertHistory(_ event: PickHistoryEvent, sequence: Int64? = nil) throws {
        guard !event.eventID.isEmpty, !event.glyphID.isEmpty, !event.symbol.isEmpty, event.occurredAt?.isFinite != false else { throw NativeStoreError.invalidDocument("Invalid history event") }
        try execute("INSERT INTO history(sequence,event_id,occurred_at,payload) VALUES(?,?,?,?) ON CONFLICT(event_id) DO NOTHING", [sequence.map(Parameter.integer) ?? .null, .text(event.eventID), event.occurredAt.map(Parameter.number) ?? .null, .text(try json(event))])
    }
}
