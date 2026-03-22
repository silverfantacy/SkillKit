import Foundation
import GRDB

/// The application's SQLite database, configured with all migrations.
public final class AppDatabase {
    public let dbWriter: any DatabaseWriter

    private init(dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try migrator.migrate(dbWriter)
    }

    private var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        #if DEBUG
        m.eraseDatabaseOnSchemaChange = true
        #endif

        m.registerMigration("v1_create_sources") { db in
            try db.create(table: "sources") { t in
                t.primaryKey("id", .text).notNull()
                t.column("type", .text).notNull()
                t.column("rootPath", .text).notNull()
                t.column("displayName", .text).notNull()
                t.column("origin", .text).notNull()
                t.column("metadataJSON", .text).notNull().defaults(to: "{}")
                t.column("isActive", .boolean).notNull().defaults(to: true)
                t.column("lastScanAt", .datetime)
                t.column("lastScanStatus", .text)
                t.column("lastScanError", .text)
            }
        }

        m.registerMigration("v1_create_skills") { db in
            try db.create(table: "skills") { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("version", .text)
                t.column("path", .text).notNull()
                t.column("sourceId", .text).notNull()
                    .references("sources", onDelete: .cascade)
                t.column("sourceType", .text).notNull()
                t.column("metadataJSON", .text).notNull().defaults(to: "{}")
                t.column("isEnabled", .boolean).notNull().defaults(to: true)
                t.column("indexedAt", .datetime).notNull()
            }
            try db.create(index: "skills_on_sourceId", on: "skills", columns: ["sourceId"])
            try db.create(index: "skills_on_name", on: "skills", columns: ["name"])
        }

        m.registerMigration("v2_create_desired_state_profiles") { db in
            try db.create(table: "desired_state_profiles") { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("targetSourceIdsJSON", .text).notNull().defaults(to: "[]")
                t.column("entriesJSON", .text).notNull().defaults(to: "[]")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }

        m.registerMigration("v2_create_sync_audit_log") { db in
            try db.create(table: "sync_audit_log") { t in
                t.primaryKey("id", .text).notNull()
                t.column("profileId", .text).notNull()
                t.column("skillName", .text).notNull()
                t.column("sourceId", .text).notNull()
                t.column("action", .text).notNull()
                t.column("outcome", .text).notNull()
                t.column("detail", .text)
                t.column("appliedAt", .datetime).notNull()
            }
            try db.create(index: "sync_audit_on_profileId", on: "sync_audit_log", columns: ["profileId"])
            try db.create(index: "sync_audit_on_appliedAt", on: "sync_audit_log", columns: ["appliedAt"])
        }

        m.registerMigration("v5_create_scenarios") { db in
            try db.create(table: "scenarios") { t in
                t.primaryKey("id", .text).notNull()
                t.column("name", .text).notNull()
                t.column("scenarioDescription", .text).notNull().defaults(to: "")
                t.column("enabledSkillIdsJSON", .text).notNull().defaults(to: "[]")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(index: "scenarios_on_name", on: "scenarios", columns: ["name"])
        }

        m.registerMigration("v4_add_skill_tags") { db in
            try db.alter(table: "skills") { t in
                t.add(column: "tagsJSON", .text).notNull().defaults(to: "[]")
            }
        }

        m.registerMigration("v3_create_security_tables") { db in
            try db.create(table: "security_findings") { t in
                t.primaryKey("id", .text).notNull()
                t.column("skillId", .text).notNull()
                t.column("skillName", .text).notNull()
                t.column("ruleId", .text).notNull()
                t.column("ruleDescription", .text).notNull()
                t.column("severity", .text).notNull()
                t.column("filePath", .text).notNull()
                t.column("matchedContent", .text).notNull()
                t.column("detectedAt", .datetime).notNull()
            }
            try db.create(index: "security_findings_on_skillId", on: "security_findings", columns: ["skillId"])
            try db.create(index: "security_findings_on_severity", on: "security_findings", columns: ["severity"])

            try db.create(table: "security_ignore_list") { t in
                t.primaryKey("id", .text).notNull()
                t.column("skillId", .text).notNull()
                t.column("ruleId", .text).notNull()
                t.column("addedAt", .datetime).notNull()
            }
            try db.create(index: "security_ignore_on_skillId_ruleId", on: "security_ignore_list", columns: ["skillId", "ruleId"], unique: true)

            try db.create(table: "security_remediation_log") { t in
                t.primaryKey("id", .text).notNull()
                t.column("skillId", .text).notNull()
                t.column("skillName", .text).notNull()
                t.column("action", .text).notNull()
                t.column("ruleId", .text)
                t.column("appliedAt", .datetime).notNull()
            }
            try db.create(index: "security_remediation_on_skillId", on: "security_remediation_log", columns: ["skillId"])
        }

        return m
    }
}

// MARK: - Factory

public extension AppDatabase {
    /// Open (or create) an on-disk database at the given path.
    static func open(at path: String) throws -> AppDatabase {
        let dbPool = try DatabasePool(path: path)
        return try AppDatabase(dbWriter: dbPool)
    }

    /// Create a temporary in-memory database (for tests).
    static func makeInMemory() throws -> AppDatabase {
        let dbQueue = try DatabaseQueue()
        return try AppDatabase(dbWriter: dbQueue)
    }
}
