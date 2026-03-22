import Foundation
import GRDB

/// Persists and queries DesiredStateProfile entries.
public final class DesiredStateRepository {
    private let db: AppDatabase

    public init(database: AppDatabase) {
        self.db = database
    }

    // MARK: - Write

    /// Insert or replace a desired state profile.
    public func save(_ profile: DesiredStateProfile) throws {
        var record = PersistedDesiredStateProfile(from: profile)
        try db.dbWriter.write { db in
            try record.save(db)
        }
    }

    /// Delete a profile by id.
    public func delete(profileId: String) throws {
        try db.dbWriter.write { db in
            try PersistedDesiredStateProfile.deleteOne(db, key: profileId)
        }
    }

    // MARK: - Read

    public func fetchAll() throws -> [DesiredStateProfile] {
        try db.dbWriter.read { db in
            try PersistedDesiredStateProfile
                .order(Column("name"))
                .fetchAll(db)
                .map { $0.toProfile() }
        }
    }

    public func fetch(id: String) throws -> DesiredStateProfile? {
        try db.dbWriter.read { db in
            try PersistedDesiredStateProfile.fetchOne(db, key: id)?.toProfile()
        }
    }
}
