import Foundation
import GRDB

/// Persists and queries the sync audit log.
public final class SyncAuditRepository {
    private let db: AppDatabase

    public init(database: AppDatabase) {
        self.db = database
    }

    // MARK: - Write

    /// Append a new audit log entry.
    public func append(_ entry: SyncAuditEntry) throws {
        let record = PersistedSyncAuditEntry(from: entry)
        try db.dbWriter.write { db in
            try record.insert(db)
        }
    }

    // MARK: - Read

    /// Fetch all entries, newest first.
    public func fetchAll() throws -> [SyncAuditEntry] {
        try db.dbWriter.read { db in
            try PersistedSyncAuditEntry
                .order(Column("appliedAt").desc)
                .fetchAll(db)
                .compactMap { $0.toAuditEntry() }
        }
    }

    /// Fetch entries for a specific profile, newest first.
    public func fetch(profileId: String) throws -> [SyncAuditEntry] {
        try db.dbWriter.read { db in
            try PersistedSyncAuditEntry
                .filter(Column("profileId") == profileId)
                .order(Column("appliedAt").desc)
                .fetchAll(db)
                .compactMap { $0.toAuditEntry() }
        }
    }

    /// Fetch entries within a date range (inclusive), newest first.
    public func fetch(from start: Date, to end: Date) throws -> [SyncAuditEntry] {
        try db.dbWriter.read { db in
            try PersistedSyncAuditEntry
                .filter(Column("appliedAt") >= start && Column("appliedAt") <= end)
                .order(Column("appliedAt").desc)
                .fetchAll(db)
                .compactMap { $0.toAuditEntry() }
        }
    }
}
