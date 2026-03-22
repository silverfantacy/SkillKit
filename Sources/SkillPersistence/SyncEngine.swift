import Foundation
import SourceDiscovery

/// Computes synchronization plans by diffing desired state profiles against the
/// current skill inventory. The engine is stateless — it reads from repositories
/// and returns a `SyncPlan` without modifying anything.
public final class SyncEngine {
    private let skillRepo: SkillRepository
    private let desiredStateRepo: DesiredStateRepository
    private let auditRepo: SyncAuditRepository

    public init(
        skillRepository: SkillRepository,
        desiredStateRepository: DesiredStateRepository,
        auditRepository: SyncAuditRepository
    ) {
        self.skillRepo = skillRepository
        self.desiredStateRepo = desiredStateRepository
        self.auditRepo = auditRepository
    }

    // MARK: - Plan

    /// Compute a sync plan for the given profile without applying any changes.
    ///
    /// Callers MUST inspect `plan.conflicts` and obtain user confirmation before
    /// calling `apply(plan:)`.
    public func plan(profileId: String) throws -> SyncPlan {
        guard let profile = try desiredStateRepo.fetch(id: profileId) else {
            throw SyncError.profileNotFound(profileId)
        }
        return try buildPlan(for: profile)
    }

    // MARK: - Apply

    /// Apply a previously computed plan (all non-conflicting actions).
    ///
    /// - Precondition: `plan.isApplicable` must be `true` — callers should check
    ///   for conflicts before calling this method.
    /// - Each action outcome is recorded in the audit log regardless of success/failure.
    @discardableResult
    public func apply(plan: SyncPlan) throws -> [SyncAuditEntry] {
        guard plan.isApplicable else {
            throw SyncError.planHasConflicts(plan.conflicts)
        }
        var entries: [SyncAuditEntry] = []
        for action in plan.actions {
            let entry = applyAction(action, profileId: plan.profileId)
            try auditRepo.append(entry)
            entries.append(entry)
        }
        return entries
    }

    // MARK: - Private helpers

    private func buildPlan(for profile: DesiredStateProfile) throws -> SyncPlan {
        // Gather current inventory for all targeted sources.
        var currentByName: [String: [PersistedSkill]] = [:]
        for sourceId in profile.targetSourceIds {
            let skills = try skillRepo.fetch(sourceId: sourceId)
            for skill in skills {
                currentByName[skill.name, default: []].append(skill)
            }
        }

        var actions: [SyncAction] = []
        var conflicts: [SyncConflict] = []

        for entry in profile.entries {
            let existing = currentByName[entry.skillName] ?? []

            if existing.isEmpty {
                // Skill is absent — plan an install on the first target source.
                if let firstSourceId = profile.targetSourceIds.first {
                    actions.append(SyncAction(
                        kind: .install,
                        skillName: entry.skillName,
                        sourceId: firstSourceId,
                        targetVersion: entry.targetVersion
                    ))
                }
            } else {
                // Conflict check: detect version disagreement across target sources.
                if let conflict = detectVersionConflict(entry: entry, existing: existing, targetSourceIds: profile.targetSourceIds) {
                    conflicts.append(conflict)
                    continue
                }

                for skill in existing {
                    // Version mismatch?
                    if let target = entry.targetVersion, skill.version != target {
                        actions.append(SyncAction(
                            kind: .changeVersion,
                            skillName: entry.skillName,
                            sourceId: skill.sourceId,
                            currentVersion: skill.version,
                            targetVersion: target
                        ))
                    }
                    // Enabled state mismatch?
                    if skill.isEnabled != entry.isEnabled {
                        actions.append(SyncAction(
                            kind: entry.isEnabled ? .enable : .disable,
                            skillName: entry.skillName,
                            sourceId: skill.sourceId,
                            currentVersion: skill.version
                        ))
                    }
                }
            }
        }

        return SyncPlan(
            profileId: profile.id,
            actions: actions,
            conflicts: conflicts
        )
    }

    /// Returns a conflict if skills across targeted sources have different versions
    /// and a single target version is required.
    private func detectVersionConflict(
        entry: DesiredSkillEntry,
        existing: [PersistedSkill],
        targetSourceIds: [String]
    ) -> SyncConflict? {
        guard let targetVersion = entry.targetVersion else { return nil }
        // Find skills in targeted sources that are at a different version.
        let mismatchedSourceIds = existing
            .filter { targetSourceIds.contains($0.sourceId) && $0.version != targetVersion }
            .map(\.sourceId)

        // Only a conflict when more than one source disagrees with each other
        // (not just with the target — that's handled as a changeVersion action).
        let uniqueVersions = Set(existing.filter { targetSourceIds.contains($0.sourceId) }.compactMap(\.version))
        guard uniqueVersions.count > 1 else { return nil }

        let conflictingSourceIds = Array(Set(mismatchedSourceIds))
        guard !conflictingSourceIds.isEmpty else { return nil }

        return SyncConflict(
            kind: .versionConflict,
            skillName: entry.skillName,
            conflictingSourceIds: conflictingSourceIds,
            description: "Skill '\(entry.skillName)' has conflicting installed versions (\(uniqueVersions.sorted().joined(separator: ", "))) across target sources. Resolve manually before syncing."
        )
    }

    /// Applies a single action and returns the resulting audit entry.
    /// This implementation reflects the action into the database directly via
    /// the skill repository (enable/disable). Install/remove/changeVersion are
    /// recorded as "skipped" because they require an adapter + filesystem; the
    /// caller is expected to integrate those via InventoryPersistenceService.
    private func applyAction(_ action: SyncAction, profileId: String) -> SyncAuditEntry {
        do {
            switch action.kind {
            case .enable:
                try skillRepo.setEnabledByName(action.skillName, sourceId: action.sourceId, isEnabled: true)
                return SyncAuditEntry(profileId: profileId, action: action, outcome: .succeeded)
            case .disable:
                try skillRepo.setEnabledByName(action.skillName, sourceId: action.sourceId, isEnabled: false)
                return SyncAuditEntry(profileId: profileId, action: action, outcome: .succeeded)
            case .install, .remove, .changeVersion:
                // These require filesystem adapters — record as skipped so callers
                // can handle them via InventoryPersistenceService.
                return SyncAuditEntry(profileId: profileId, action: action, outcome: .skipped,
                                      detail: "Action '\(action.kind.rawValue)' requires filesystem adapter; apply via InventoryPersistenceService.")
            }
        } catch {
            return SyncAuditEntry(profileId: profileId, action: action, outcome: .failed,
                                  detail: error.localizedDescription)
        }
    }
}

// MARK: - Errors

public struct SyncError: Error, LocalizedError {
    public enum Code {
        case profileNotFound
        case planHasConflicts
    }

    public let code: Code
    public let message: String

    public var errorDescription: String? { message }

    public static func profileNotFound(_ id: String) -> SyncError {
        SyncError(code: .profileNotFound, message: "No desired state profile found with id: \(id)")
    }

    public static func planHasConflicts(_ conflicts: [SyncConflict]) -> SyncError {
        SyncError(code: .planHasConflicts, message: "Sync plan has \(conflicts.count) unresolved conflict(s) and cannot be applied.")
    }
}
