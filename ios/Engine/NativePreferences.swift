import Foundation

extension NativePersonalizationStore {
    public func readPreferences() throws -> BrowsePreferences { try locked { try preferences().value } }
    public func setCategoryEnabled(_ categoryID: String, enabled: Bool) throws -> BrowsePreferences {
        guard !categoryID.isEmpty else { throw NativeStoreError.invalidDocument("Empty category ID") }
        return try updatePreferences { raw in
            var map = raw["categoryVisibility"] as? [String: Any] ?? [:]; map[categoryID] = enabled; raw["categoryVisibility"] = map
        }
    }
    public func setCategoryExemplar(_ categoryID: String, exemplar: CategoryExemplar?) throws -> BrowsePreferences {
        guard !categoryID.isEmpty else { throw NativeStoreError.invalidDocument("Empty category ID") }
        return try updatePreferences { raw in
            var map = raw["exemplarOverrides"] as? [String: Any] ?? [:]
            if let exemplar {
                guard !exemplar.symbol.isEmpty else { throw NativeStoreError.invalidDocument("Empty exemplar") }
                map[categoryID] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(exemplar))
            } else { map.removeValue(forKey: categoryID) }
            raw["exemplarOverrides"] = map
        }
    }
    public func applyCategoryDefaults(migrationID: String, categoryIDs: [String]) throws -> BrowsePreferences {
        guard !migrationID.isEmpty, categoryIDs.allSatisfy({ !$0.isEmpty }) else { throw NativeStoreError.invalidDocument("Empty migration/category ID") }
        return try updatePreferences { raw in
            var applied = raw["appliedMigrations"] as? [String] ?? []
            guard !applied.contains(migrationID) else { return }
            var map = raw["categoryVisibility"] as? [String: Any] ?? [:]
            for id in categoryIDs where map[id] == nil { map[id] = true }
            applied.append(migrationID); raw["appliedMigrations"] = applied; raw["categoryVisibility"] = map
        }
    }

    private func preferences() throws -> (raw: [String: Any], value: BrowsePreferences) {
        let data: Data
        if let payload = try rows("SELECT payload FROM preferences WHERE id=1").first?["payload"] { data = Data(payload.utf8) }
        else { data = try JSONEncoder().encode(BrowsePreferences(catalogueRevision: catalogueRevision)) }
        guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any], let version = raw["schemaVersion"] as? Int else { throw NativeStoreError.invalidDocument("Invalid preferences document") }
        guard version == 1 else { throw NativeStoreError.unsupportedVersion(version) }
        return (raw, try JSONDecoder().decode(BrowsePreferences.self, from: data))
    }
    private func updatePreferences(_ change: (inout [String: Any]) throws -> Void) throws -> BrowsePreferences {
        try transaction {
            var raw = try self.preferences().raw
            try change(&raw); raw["catalogueRevision"] = self.catalogueRevision
            let data = try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys])
            let value = try JSONDecoder().decode(BrowsePreferences.self, from: data)
            try self.execute("INSERT INTO preferences(id,payload) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload", [.text(String(decoding: data, as: UTF8.self))])
            return value
        }
    }
}
