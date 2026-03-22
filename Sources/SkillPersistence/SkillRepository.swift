import Foundation
import GRDB
import SourceDiscovery

/// Persists and queries skill inventory entries.
public final class SkillRepository {
    private let db: AppDatabase

    public init(database: AppDatabase) {
        self.db = database
    }

    // MARK: - Write

    /// Insert or replace a skill record.
    public func save(_ record: SkillRecord, isEnabled: Bool = true) throws {
        let persisted = PersistedSkill(from: record, isEnabled: isEnabled, indexedAt: Date())
        try db.dbWriter.write { db in
            try persisted.save(db)
        }
    }

    /// Replace all skills for a source with the results of a scan.
    public func replaceAll(for sourceId: String, with skills: [SkillRecord]) throws {
        let now = Date()
        try db.dbWriter.write { db in
            try PersistedSkill
                .filter(Column("sourceId") == sourceId)
                .deleteAll(db)
            for record in skills {
                let persisted = PersistedSkill(from: record, indexedAt: now)
                try persisted.insert(db)
            }
        }
    }

    /// Update the enabled state of a single skill.
    /// Returns false if no skill with the given id exists.
    @discardableResult
    public func setEnabled(skillId: String, isEnabled: Bool) throws -> Bool {
        try db.dbWriter.write { db in
            guard var record = try PersistedSkill.fetchOne(db, key: skillId) else { return false }
            record.isEnabled = isEnabled
            try record.update(db)
            return true
        }
    }

    /// Remove a single skill by id.
    public func delete(skillId: String) throws {
        _ = try db.dbWriter.write { db in
            try PersistedSkill.deleteOne(db, key: skillId)
        }
    }

    /// Update the enabled state of all skills with a given name in a source.
    /// Returns the number of updated rows.
    @discardableResult
    public func setEnabledByName(_ name: String, sourceId: String, isEnabled: Bool) throws -> Int {
        try db.dbWriter.write { db in
            let request = PersistedSkill
                .filter(Column("name") == name && Column("sourceId") == sourceId)
            let count = try request.fetchCount(db)
            try request.updateAll(db, Column("isEnabled").set(to: isEnabled))
            return count
        }
    }

    /// Batch update isEnabled in a single transaction.
    /// - Parameter enabledIds: Skill ids to enable; all others in the same source(s) are disabled.
    /// - Parameter scopeSourceIds: If non-empty, only skills in these sources are affected.
    public func batchSetEnabled(enabledIds: Set<String>, scopeSourceIds: [String] = []) throws {
        try db.dbWriter.write { db in
            var request = PersistedSkill.all()
            if !scopeSourceIds.isEmpty {
                request = request.filter(scopeSourceIds.contains(Column("sourceId")))
            }
            let allSkills = try request.fetchAll(db)
            for var skill in allSkills {
                let shouldEnable = enabledIds.contains(skill.id)
                if skill.isEnabled != shouldEnable {
                    skill.isEnabled = shouldEnable
                    try skill.update(db)
                }
            }
        }
    }

    /// Update the raw metadataJSON for a skill.
    @discardableResult
    public func setMetadataJSON(skillId: String, json: String) throws -> Bool {
        try db.dbWriter.write { db in
            guard var record = try PersistedSkill.fetchOne(db, key: skillId) else { return false }
            record.metadataJSON = json
            try record.update(db)
            return true
        }
    }

    /// Set the tags for a skill. Returns false if no skill with the given id exists.
    @discardableResult
    public func setTags(skillId: String, tags: [String]) throws -> Bool {
        let json = (try? JSONEncoder().encode(tags)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return try db.dbWriter.write { db in
            guard var record = try PersistedSkill.fetchOne(db, key: skillId) else { return false }
            record.tagsJSON = json
            try record.update(db)
            return true
        }
    }

    /// Remove all skills belonging to a source.
    public func deleteAll(sourceId: String) throws {
        try db.dbWriter.write { db in
            try PersistedSkill
                .filter(Column("sourceId") == sourceId)
                .deleteAll(db)
        }
    }

    // MARK: - Read

    public func fetchAll() throws -> [PersistedSkill] {
        try db.dbWriter.read { db in
            try PersistedSkill.fetchAll(db)
        }
    }

    public func fetch(sourceId: String) throws -> [PersistedSkill] {
        try db.dbWriter.read { db in
            try PersistedSkill
                .filter(Column("sourceId") == sourceId)
                .fetchAll(db)
        }
    }

    public func fetch(id: String) throws -> PersistedSkill? {
        try db.dbWriter.read { db in
            try PersistedSkill.fetchOne(db, key: id)
        }
    }

    /// Filter skills by source, enabled status, and/or text search on name.
    public func query(
        sourceId: String? = nil,
        isEnabled: Bool? = nil,
        nameContains: String? = nil
    ) throws -> [PersistedSkill] {
        try db.dbWriter.read { db in
            var request = PersistedSkill.all()
            if let sourceId {
                request = request.filter(Column("sourceId") == sourceId)
            }
            if let isEnabled {
                request = request.filter(Column("isEnabled") == isEnabled)
            }
            if let nameContains, !nameContains.isEmpty {
                request = request.filter(Column("name").like("%\(nameContains)%"))
            }
            return try request.order(Column("name")).fetchAll(db)
        }
    }
}
