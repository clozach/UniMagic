import Foundation

@main enum NativePersistenceTests {
    static func event(_ id: String, at: Double? = nil) -> PickHistoryEvent {
        PickHistoryEvent(eventID: id, glyphID: "1F43B 200D 2744", symbol: "🐻‍❄️", occurredAt: at, provenance: .pick(host: .nativeKeyboard, action: .insert))
    }
    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw NativeStoreError.invalidDocument("TEST: " + message) }
    }
    static func main() throws {
        if CommandLine.arguments.count == 4 {
            let store = try NativePersonalizationStore(location: .local(URL(fileURLWithPath: CommandLine.arguments[2])), catalogueRevision: "test")
            if CommandLine.arguments[1] == "--once" {
                _ = try store.importHistoryOnce(PickHistoryImport(importID: "legacy-once-race", events: [event(CommandLine.arguments[3])]))
                return
            }
            for n in 0..<100 {
                try store.appendHistoryEvent(event(CommandLine.arguments[3] + "-\(n)", at: Double(n)))
                _ = try store.setCategoryEnabled(CommandLine.arguments[3] + "-\(n)", enabled: true)
            }
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("unimagic-store-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let learning = directory.appendingPathComponent("learning-v1.json")
        let oldLearning = Data("{\"version\":1,\"learned\":[{\"term\":\"old\"}],\"usage\":[{\"count\":20}]}".utf8)
        try oldLearning.write(to: learning)
        let store = try NativePersonalizationStore(location: .local(directory), catalogueRevision: "test")
        _ = try store.setCategoryEnabled("set:Emoji", enabled: false)
        _ = try store.applyCategoryDefaults(migrationID: "seed", categoryIDs: ["set:Emoji", "set:Dashes"])
        _ = try store.applyCategoryDefaults(migrationID: "seed", categoryIDs: ["set:Quotes"])
        let prefs = try store.readPreferences()
        try require(prefs.categoryVisibility["set:Emoji"] == false && prefs.categoryVisibility["set:Dashes"] == true && prefs.categoryVisibility["set:Quotes"] == nil, "Migration respects explicit false and is idempotent")
        _ = try store.setCategoryExemplar("set:Emoji", exemplar: .emoji("🐻‍❄️"))
        _ = try store.setCategoryExemplar("set:Emoji", exemplar: nil)
        try require(try store.readPreferences().exemplarOverrides.isEmpty, "Reset removes override")
        let raw = try store.rows("SELECT payload FROM preferences WHERE id=1").first!["payload"]!
        var unknown = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as! [String: Any]
        unknown["futureMetadata"] = ["keep": "this"]
        try store.execute("UPDATE preferences SET payload=? WHERE id=1", [.text(String(decoding: try JSONSerialization.data(withJSONObject: unknown), as: UTF8.self))])
        _ = try store.setCategoryEnabled("block:Arrows", enabled: true)
        try require(try store.rows("SELECT payload FROM preferences WHERE id=1").first!["payload"]!.contains("futureMetadata"), "Unknown preference fields preserved")

        // Actual separate processes contend on the same SQLite file.
        var processes: [Process] = []
        for owner in ["app", "keyboard"] {
            let process = Process(); process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); process.arguments = ["--writer", directory.path, owner]
            try process.run(); processes.append(process)
        }
        for process in processes { process.waitUntilExit(); try require(process.terminationStatus == 0, "Concurrent writer succeeds") }
        try require(try store.historyCount() == 200, "Concurrent events not lost; count does not load payloads")
        try require(try store.readPreferences().categoryVisibility.count == 203, "Concurrent preferences not lost")
        var ids: [String] = []; var cursor: String?
        repeat {
            let page = try store.readHistoryPage(cursor: cursor, limit: 17)
            try require(page.events.count <= 17, "Bounded UI page")
            ids += page.events.map(\.eventID); cursor = page.nextCursor
            if ids.count == 17 { try store.appendHistoryEvent(event("new-during-paging", at: 1000)) }
        } while cursor != nil
        try require(ids.count == 200 && Set(ids).count == 200, "Keyset cursor survives prepend without duplicates/skips")
        let snapshot = PickHistoryImport(importID: "photo", events: [event("photo-1"), event("photo-2")])
        try require(try store.importHistory(snapshot).imported == 2, "Snapshot imported")
        try require(try store.importHistory(snapshot).alreadyApplied, "Snapshot retry no-op")
        let all = try store.readHistoryPage(limit: 500).events
        try require(Array(all.suffix(2)).map(\.eventID) == ["photo-1", "photo-2"], "Unknown dates keep source order")
        let datedCursor = try store.readHistoryPage(limit: 17).nextCursor
        let unknownCursor = try store.readHistoryPage(limit: 202).nextCursor
        for cursor in [nil, datedCursor, unknownCursor] {
            let query = try store.historyPageQuery(cursor: cursor, limit: 17)
            let plan = try store.rows("EXPLAIN QUERY PLAN " + query.sql, query.values).compactMap { $0["detail"] }.joined(separator: " | ")
            try require(!plan.contains("TEMP B-TREE") && plan.contains("USING INDEX history_order"), "History paging uses ordered index without temporary sort: " + plan)
            if cursor != nil { try require(plan.contains("SEARCH history USING INDEX history_order"), "Keyset cursor uses index range: " + plan) }
            print("History query plan: " + plan)
        }
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(event("null"))) as! [String: Any]
        try require(encoded["occurredAt"] is NSNull, "Unknown dates encode null")
        do { _ = try store.importHistory(PickHistoryImport(importID: "invalid", events: [event("would-roll-back"), PickHistoryEvent(eventID: "bad", glyphID: "x", symbol: "", occurredAt: nil, provenance: .pick(host: .nativeApp, action: .copy))])); throw NativeStoreError.invalidDocument("Invalid import accepted") }
        catch NativeStoreError.invalidDocument { }
        try require(try store.rows("SELECT event_id FROM history WHERE event_id='would-roll-back'").isEmpty, "Invalid import rolls back complete transaction")
        let reader = try NativePersonalizationStore(location: .sharedReadOnly(directory), catalogueRevision: "test")
        try require(try reader.readHistoryPage(limit: 10).events.count == 10, "Read-only opens initialized database")
        do { try reader.appendHistoryEvent(event("denied")); throw NativeStoreError.invalidDocument("Read-only write accepted") }
        catch NativeStoreError.readOnly { }
        try require(try store.mergeHistoryEvents([event("local-1", at: 2000)] ) == 1, "Local events promoted")
        try require(try store.mergeHistoryEvents([event("local-1", at: 2000), event("local-2", at: 2001)] ) == 1, "Promotion retry adds only new IDs")
        try store.appendHistoryEvent(event("opaque\0one", at: 3000)); try store.appendHistoryEvent(event("opaque\0two", at: 3001))
        try require(try store.readHistoryPage(limit: 2).events.map(\.eventID) == ["opaque\0two", "opaque\0one"], "Opaque IDs remain distinct across embedded NUL")
        func cell(_ position: Int) -> PickHistoryEvent { PickHistoryEvent(eventID: "cell-\(position)", glyphID: "2764", symbol: "❤️", occurredAt: nil, provenance: .snapshotImport(importID: "partial", source: "photo", position: position)) }
        _ = try store.importHistory(PickHistoryImport(importID: "partial", events: [cell(0), cell(2)]))
        _ = try store.mergeHistoryEvents([event("other-unknown")])
        let late = try store.importHistory(PickHistoryImport(importID: "partial", events: [cell(1)]))
        try require(late.imported == 1 && !late.alreadyApplied, "Late verified cell added under original import ID")
        let tail = try store.readHistoryPage(limit: 500).events.map(\.eventID)
        try require(Array(tail.suffix(4)) == ["cell-0", "cell-1", "cell-2", "other-unknown"], "Sparse reservation retains late snapshot position ahead of later unknown merges")
        try require(try store.importHistory(PickHistoryImport(importID: "partial", events: [cell(0), cell(1), cell(2)])).alreadyApplied, "Complete snapshot retry remains no-op")
        let once = try NativePersonalizationStore(location: .local(directory.appendingPathComponent("once")), catalogueRevision: "test")
        let emptyOnce = PickHistoryImport(importID: "legacy-empty", events: [])
        try require(try !once.importHistoryOnce(emptyOnce).alreadyApplied, "Empty baseline records its first completion")
        try require(try once.importHistoryOnce(PickHistoryImport(importID: "legacy-empty", events: [event("new-real-pick-must-not-be-legacy")])).alreadyApplied, "Empty legacy baseline stays sealed")
        try require(try once.historyCount() == 0, "Evolving empty legacy source adds no manufactured event")
        let honest = PickHistoryEvent(eventID: "honest-legacy", glyphID: "2014", symbol: "—", occurredAt: 100_000, provenance: .legacyAggregate(source: "old", count: 9))
        _ = try once.importHistoryOnce(PickHistoryImport(importID: "legacy-prior", events: [honest]))
        let honestPayload = try once.rows("SELECT payload FROM history WHERE event_id='honest-legacy'").first!["payload"]!
        try require(try once.importHistoryOnce(PickHistoryImport(importID: "legacy-prior", events: [honest, event("later-usage")])).imported == 0, "Prior legacy import ignores unseen later usage")
        try require(try once.rows("SELECT payload FROM history WHERE event_id='honest-legacy'").first!["payload"]! == honestPayload && once.historyCount() == 1, "Honest legacy event remains exact")
        _ = try once.importHistory(PickHistoryImport(importID: "old-additive-marker", events: [event("old-legacy")]))
        try require(try once.importHistoryOnce(PickHistoryImport(importID: "old-additive-marker", events: [event("unseen-later")])).alreadyApplied, "Existing legacy marker is accepted as completion")
        do { _ = try once.importHistoryOnce(PickHistoryImport(importID: "once-invalid", events: [event("once-roll-back"), PickHistoryEvent(eventID: "invalid", glyphID: "x", symbol: "", occurredAt: nil, provenance: .legacyAggregate(source: "old", count: 1))])) }
        catch NativeStoreError.invalidDocument { }
        try require(try once.rows("SELECT event_id FROM history WHERE event_id='once-roll-back'").isEmpty && once.rows("SELECT import_id FROM history_imports WHERE import_id='once-invalid'").isEmpty, "Failed one-time import rolls back events and completion together")
        try require(try once.importHistoryOnce(PickHistoryImport(importID: "once-invalid", events: [event("valid-retry")])).imported == 1, "Failed one-time import remains retryable")
        let onceDirectory = directory.appendingPathComponent("once-race")
        let onceRace = try NativePersonalizationStore(location: .local(onceDirectory), catalogueRevision: "test")
        var onceProcesses: [Process] = []
        for owner in ["first-source", "evolving-source"] {
            let process = Process(); process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); process.arguments = ["--once", onceDirectory.path, owner]
            try process.run(); onceProcesses.append(process)
        }
        for process in onceProcesses { process.waitUntilExit(); try require(process.terminationStatus == 0, "Concurrent one-time importer succeeds") }
        try require(try onceRace.historyCount() == 1, "Concurrent sources seal one initial legacy snapshot")
        let legacyDirectory = directory.appendingPathComponent("old-v1")
        func legacyCell(_ p: Int) -> PickHistoryEvent { PickHistoryEvent(eventID: "legacy-cell-\(p)", glyphID: "2764", symbol: "❤️", occurredAt: nil, provenance: .snapshotImport(importID: "legacy-partial", source: "photo", position: p)) }
        var legacy: NativePersonalizationStore? = try NativePersonalizationStore(location: .local(legacyDirectory), catalogueRevision: "test")
        _ = try legacy!.importHistory(PickHistoryImport(importID: "legacy-partial", events: [legacyCell(0), legacyCell(2)]))
        try legacy!.execute("DROP TABLE history_imports")
        try legacy!.execute("CREATE TABLE history_imports(import_id TEXT PRIMARY KEY)")
        try legacy!.execute("INSERT INTO history_imports VALUES('legacy-partial')")
        legacy = nil
        let migratedLegacy = try NativePersonalizationStore(location: .local(legacyDirectory), catalogueRevision: "test")
        _ = try migratedLegacy.importHistory(PickHistoryImport(importID: "legacy-partial", events: [legacyCell(1)]))
        try require(try migratedLegacy.readHistoryPage(limit: 10).events.map(\.eventID) == ["legacy-cell-0", "legacy-cell-1", "legacy-cell-2"], "Existing v1 import marker migrates without losing IDs, strings or snapshot order")
        try require(try Data(contentsOf: learning) == oldLearning, "Legacy learning untouched; no fake history")
        let before = try store.rows("SELECT payload FROM preferences WHERE id=1").first!["payload"]!
        var future = unknown; future["schemaVersion"] = 2
        let futureJSON = String(decoding: try JSONSerialization.data(withJSONObject: future), as: UTF8.self)
        try store.execute("UPDATE preferences SET payload=? WHERE id=1", [.text(futureJSON)])
        do { _ = try store.setCategoryEnabled("oops", enabled: true); throw NativeStoreError.invalidDocument("Future preference rewritten") }
        catch NativeStoreError.unsupportedVersion(2) { }
        try require(try store.rows("SELECT payload FROM preferences WHERE id=1").first!["payload"]! == futureJSON, "Future preference bytes preserved")
        try store.execute("UPDATE preferences SET payload=? WHERE id=1", [.text(before)])
        try store.execute("PRAGMA user_version=2")
        do { _ = try NativePersonalizationStore(location: .local(directory), catalogueRevision: "test"); throw NativeStoreError.invalidDocument("Future database opened writable") }
        catch NativeStoreError.unsupportedVersion(2) { }
        print("Native persistence checks passed: cross-process contention, exact strings, paging, additive snapshots, one-time legacy boundaries including empty baselines, read-only, unknown/newer data, legacy preservation")
    }
}
