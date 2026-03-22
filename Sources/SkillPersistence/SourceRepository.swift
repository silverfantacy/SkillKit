import Foundation
import GRDB
import SourceDiscovery

/// Persists and queries skill sources.
public final class SourceRepository {
    private let db: AppDatabase

    public init(database: AppDatabase) {
        self.db = database
    }

    // MARK: - Write

    /// Insert or replace a source. Marks it as active by default.
    public func save(_ source: SkillSource, isActive: Bool = true) throws {
        var record = PersistedSource(from: source, isActive: isActive)
        try db.dbWriter.write { db in
            try record.save(db)
        }
    }

    /// Update scan result metadata for an existing source.
    public func updateScanResult(sourceId: String, result: SourceScanResult) throws {
        try db.dbWriter.write { db in
            guard var record = try PersistedSource.fetchOne(db, key: sourceId) else { return }
            record.lastScanAt = result.scannedAt
            record.lastScanStatus = result.status.rawValue
            record.lastScanError = result.errors.first?.message
            record.isActive = (result.status != .failure)
            try record.update(db)
        }
    }

    /// Mark a source as inactive (e.g. path became inaccessible).
    public func deactivate(sourceId: String, reason: String? = nil) throws {
        try db.dbWriter.write { db in
            guard var record = try PersistedSource.fetchOne(db, key: sourceId) else { return }
            record.isActive = false
            record.lastScanError = reason
            try record.update(db)
        }
    }

    /// Delete a source (cascades to skills).
    public func delete(sourceId: String) throws {
        try db.dbWriter.write { db in
            try PersistedSource.deleteOne(db, key: sourceId)
        }
    }

    // MARK: - Read

    public func fetchAll() throws -> [SkillSource] {
        try db.dbWriter.read { db in
            try PersistedSource.fetchAll(db).map { $0.toSkillSource() }
        }
    }

    /// Fetch all sources including scan status metadata.
    public func fetchPersistedAll() throws -> [PersistedSource] {
        try db.dbWriter.read { db in
            try PersistedSource
                .order(Column("displayName"))
                .fetchAll(db)
        }
    }

    public func fetchActive() throws -> [SkillSource] {
        try db.dbWriter.read { db in
            try PersistedSource
                .filter(Column("isActive") == true)
                .fetchAll(db)
                .map { $0.toSkillSource() }
        }
    }

    public func fetch(id: String) throws -> SkillSource? {
        try db.dbWriter.read { db in
            try PersistedSource.fetchOne(db, key: id)?.toSkillSource()
        }
    }

    /// Returns true if a source with the given id already exists.
    public func exists(id: String) throws -> Bool {
        try db.dbWriter.read { db in
            try PersistedSource.exists(db, key: id)
        }
    }
}
