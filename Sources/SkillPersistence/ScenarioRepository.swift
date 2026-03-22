import Foundation
import GRDB

/// Manages scenario CRUD operations.
public final class ScenarioRepository {
    private let db: AppDatabase

    public init(database: AppDatabase) {
        self.db = database
    }

    // MARK: - Write

    public func save(_ scenario: PersistedScenario) throws {
        try db.dbWriter.write { db in
            try scenario.save(db)
        }
    }

    public func delete(id: String) throws {
        _ = try db.dbWriter.write { db in
            try PersistedScenario.deleteOne(db, key: id)
        }
    }

    // MARK: - Read

    public func fetchAll() throws -> [PersistedScenario] {
        try db.dbWriter.read { db in
            try PersistedScenario.order(Column("createdAt")).fetchAll(db)
        }
    }

    public func fetch(id: String) throws -> PersistedScenario? {
        try db.dbWriter.read { db in
            try PersistedScenario.fetchOne(db, key: id)
        }
    }
}
