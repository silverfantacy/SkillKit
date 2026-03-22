import Foundation
import GRDB

// MARK: - Persisted Finding

struct PersistedSecurityFinding: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "security_findings"

    var id: String
    var skillId: String
    var skillName: String
    var ruleId: String
    var ruleDescription: String
    var severity: String
    var filePath: String
    var matchedContent: String
    var detectedAt: Date

    init(from finding: SecurityFinding) {
        self.id = finding.id
        self.skillId = finding.skillId
        self.skillName = finding.skillName
        self.ruleId = finding.ruleId
        self.ruleDescription = finding.ruleDescription
        self.severity = finding.severity.rawValue
        self.filePath = finding.filePath
        self.matchedContent = finding.matchedContent
        self.detectedAt = finding.detectedAt
    }

    func toFinding() -> SecurityFinding? {
        guard let sev = SecuritySeverity(rawValue: severity) else { return nil }
        return SecurityFinding(
            id: id,
            skillId: skillId,
            skillName: skillName,
            ruleId: ruleId,
            ruleDescription: ruleDescription,
            severity: sev,
            filePath: filePath,
            matchedContent: matchedContent,
            detectedAt: detectedAt
        )
    }
}

// MARK: - Persisted Ignore Entry

struct PersistedSecurityIgnoreEntry: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "security_ignore_list"

    var id: String
    var skillId: String
    var ruleId: String
    var addedAt: Date

    init(from entry: SecurityIgnoreEntry) {
        self.id = entry.id
        self.skillId = entry.skillId
        self.ruleId = entry.ruleId
        self.addedAt = entry.addedAt
    }

    func toEntry() -> SecurityIgnoreEntry {
        SecurityIgnoreEntry(id: id, skillId: skillId, ruleId: ruleId, addedAt: addedAt)
    }
}

// MARK: - Persisted Remediation Entry

struct PersistedSecurityRemediationEntry: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "security_remediation_log"

    var id: String
    var skillId: String
    var skillName: String
    var action: String
    var ruleId: String?
    var appliedAt: Date

    init(from entry: SecurityRemediationEntry) {
        self.id = entry.id
        self.skillId = entry.skillId
        self.skillName = entry.skillName
        self.action = entry.action.rawValue
        self.ruleId = entry.ruleId
        self.appliedAt = entry.appliedAt
    }

    func toEntry() -> SecurityRemediationEntry? {
        guard let action = SecurityRemediationEntry.Action(rawValue: action) else { return nil }
        return SecurityRemediationEntry(
            id: id,
            skillId: skillId,
            skillName: skillName,
            action: action,
            ruleId: ruleId,
            appliedAt: appliedAt
        )
    }
}

// MARK: - Repository

/// Persists and queries security findings, the ignore list, and remediation log.
public final class SecurityReportRepository {
    private let db: AppDatabase

    public init(database: AppDatabase) {
        self.db = database
    }

    // MARK: - Findings

    /// Replace all stored findings with the results of a new scan.
    public func saveReport(_ report: SecurityReport) throws {
        try db.dbWriter.write { db in
            try PersistedSecurityFinding.deleteAll(db)
            for finding in report.findings {
                try PersistedSecurityFinding(from: finding).insert(db)
            }
        }
    }

    /// Fetch the stored findings as a report.
    public func fetchReport() throws -> SecurityReport {
        let findings = try db.dbWriter.read { db in
            try PersistedSecurityFinding
                .order(Column("detectedAt").desc)
                .fetchAll(db)
                .compactMap { $0.toFinding() }
        }
        return SecurityReport(findings: findings)
    }

    // MARK: - Ignore List

    public func addIgnoreEntry(_ entry: SecurityIgnoreEntry) throws {
        try db.dbWriter.write { db in
            try PersistedSecurityIgnoreEntry(from: entry).save(db)
        }
    }

    public func removeIgnoreEntry(skillId: String, ruleId: String) throws {
        try db.dbWriter.write { db in
            try PersistedSecurityIgnoreEntry
                .filter(Column("skillId") == skillId && Column("ruleId") == ruleId)
                .deleteAll(db)
        }
    }

    public func fetchIgnoreList() throws -> [SecurityIgnoreEntry] {
        try db.dbWriter.read { db in
            try PersistedSecurityIgnoreEntry
                .order(Column("addedAt").desc)
                .fetchAll(db)
                .map { $0.toEntry() }
        }
    }

    // MARK: - Remediation Log

    public func appendRemediationEntry(_ entry: SecurityRemediationEntry) throws {
        try db.dbWriter.write { db in
            try PersistedSecurityRemediationEntry(from: entry).insert(db)
        }
    }

    public func fetchRemediationLog() throws -> [SecurityRemediationEntry] {
        try db.dbWriter.read { db in
            try PersistedSecurityRemediationEntry
                .order(Column("appliedAt").desc)
                .fetchAll(db)
                .compactMap { $0.toEntry() }
        }
    }
}
