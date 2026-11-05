import Foundation
import SQLite3

/// Separate from learning-v1.json. SQLite serializes cross-process mutations;
/// every transaction re-reads current state before applying the requested delta.
public final class NativePersonalizationStore: @unchecked Sendable {
    public let location: NativePersonalizationLocation
    public let databaseURL: URL
    let catalogueRevision: String
    private var database: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    enum Parameter { case text(String), number(Double), integer(Int64), null }

    public init(location: NativePersonalizationLocation, catalogueRevision: String) throws {
        self.location = location; self.catalogueRevision = catalogueRevision
        databaseURL = location.directory.appendingPathComponent("personalization-v1.sqlite")
        if location.isWritable { try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true) }
        let flags = (location.isWritable ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY) | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &database, flags, nil) == SQLITE_OK else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) } ?? "Database unavailable"
            sqlite3_close(database); database = nil; throw NativeStoreError.sqlite(message)
        }
        sqlite3_busy_timeout(database, 5_000)
        do {
            let version = try integer("PRAGMA user_version")
            guard version <= 1 else { throw NativeStoreError.unsupportedVersion(Int(version)) }
            if location.isWritable {
                try execute("PRAGMA journal_mode=DELETE")
                try transaction {
                    try self.execute("CREATE TABLE IF NOT EXISTS preferences (id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL)")
                    try self.execute("CREATE TABLE IF NOT EXISTS history (sequence INTEGER PRIMARY KEY, event_id TEXT NOT NULL UNIQUE, occurred_at REAL, payload TEXT NOT NULL)")
                    try self.execute("CREATE INDEX IF NOT EXISTS history_order ON history(occurred_at DESC, sequence DESC)")
                    try self.execute("CREATE TABLE IF NOT EXISTS history_imports (import_id TEXT PRIMARY KEY, base_sequence INTEGER, reservation_size INTEGER)")
                    let columns = try self.rows("PRAGMA table_info(history_imports)").compactMap { $0["name"] }
                    if !columns.contains("base_sequence") { try self.execute("ALTER TABLE history_imports ADD COLUMN base_sequence INTEGER") }
                    if !columns.contains("reservation_size") { try self.execute("ALTER TABLE history_imports ADD COLUMN reservation_size INTEGER") }
                    try self.execute("PRAGMA user_version=1")
                }
            } else if version != 1 { throw NativeStoreError.invalidDocument("Shared database has not been initialized by the app") }
        } catch { sqlite3_close(database); database = nil; throw error }
    }
    deinit { sqlite3_close(database) }

    func locked<T>(_ body: () throws -> T) rethrows -> T { lock.lock(); defer { lock.unlock() }; return try body() }
    func transaction<T>(_ body: () throws -> T) throws -> T {
        guard location.isWritable else { throw NativeStoreError.readOnly }
        return try locked {
            try execute("BEGIN IMMEDIATE")
            do { let value = try body(); try execute("COMMIT"); return value }
            catch { try? execute("ROLLBACK"); throw error }
        }
    }
    func execute(_ sql: String, _ values: [Parameter] = []) throws { _ = try rows(sql, values) }
    func integer(_ sql: String, _ values: [Parameter] = []) throws -> Int64 {
        guard let value = try rows(sql, values).first?.values.first, let n = Int64(value) else { throw NativeStoreError.sqlite("Expected integer result") }
        return n
    }
    func rows(_ sql: String, _ values: [Parameter] = []) throws -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            let slot = Int32(index + 1)
            let result: Int32
            switch value {
            case .text(let s): result = sqlite3_bind_text(statement, slot, s, Int32(s.utf8.count), transient)
            case .number(let n): result = sqlite3_bind_double(statement, slot, n)
            case .integer(let n): result = sqlite3_bind_int64(statement, slot, n)
            case .null: result = sqlite3_bind_null(statement, slot)
            }
            guard result == SQLITE_OK else { throw failure() }
        }
        var result: [[String: String]] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                var row: [String: String] = [:]
                for index in 0..<sqlite3_column_count(statement) {
                    if let text = sqlite3_column_text(statement, index) { row[String(cString: sqlite3_column_name(statement, index))] = String(cString: text) }
                }
                result.append(row)
            case SQLITE_DONE: return result
            default: throw failure()
            }
        }
    }
    private func failure() -> NativeStoreError { .sqlite(database.map { String(cString: sqlite3_errmsg($0)) } ?? "Database closed") }
    func json<T: Encodable>(_ value: T) throws -> String { String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
}
