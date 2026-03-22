import Foundation
import GRDB

/// GRDB row for a DesiredStateProfile stored in SQLite.
struct PersistedDesiredStateProfile: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "desired_state_profiles"

    var id: String
    var name: String
    /// JSON-encoded [String] of source IDs.
    var targetSourceIdsJSON: String
    /// JSON-encoded [DesiredSkillEntry].
    var entriesJSON: String
    var createdAt: Date
    var updatedAt: Date

    init(from profile: DesiredStateProfile) {
        self.id = profile.id
        self.name = profile.name
        self.targetSourceIdsJSON = (try? JSONEncoder().encode(profile.targetSourceIds))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        self.entriesJSON = (try? JSONEncoder().encode(profile.entries))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        self.createdAt = profile.createdAt
        self.updatedAt = profile.updatedAt
    }

    func toProfile() -> DesiredStateProfile {
        let sourceIds = (try? JSONDecoder().decode([String].self, from: Data(targetSourceIdsJSON.utf8))) ?? []
        let entries = (try? JSONDecoder().decode([DesiredSkillEntry].self, from: Data(entriesJSON.utf8))) ?? []
        return DesiredStateProfile(
            id: id,
            name: name,
            targetSourceIds: sourceIds,
            entries: entries,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

/// GRDB row for a SyncAuditEntry stored in SQLite.
struct PersistedSyncAuditEntry: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "sync_audit_log"

    var id: String
    var profileId: String
    var skillName: String
    var sourceId: String
    var action: String
    var outcome: String
    var detail: String?
    var appliedAt: Date

    init(from entry: SyncAuditEntry) {
        self.id = entry.id
        self.profileId = entry.profileId
        self.skillName = entry.skillName
        self.sourceId = entry.sourceId
        self.action = entry.action.rawValue
        self.outcome = entry.outcome.rawValue
        self.detail = entry.detail
        self.appliedAt = entry.appliedAt
    }

    func toAuditEntry() -> SyncAuditEntry? {
        guard let action = SyncAction.Kind(rawValue: self.action),
              let outcome = SyncActionOutcome(rawValue: self.outcome) else { return nil }
        return SyncAuditEntry(
            id: id,
            profileId: profileId,
            action: SyncAction(kind: action, skillName: skillName, sourceId: sourceId),
            outcome: outcome,
            detail: detail,
            appliedAt: appliedAt
        )
    }
}
