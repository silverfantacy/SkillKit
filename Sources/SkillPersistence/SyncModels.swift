import Foundation
import SourceDiscovery

// MARK: - Desired State

/// The desired state for a single skill within a profile.
public struct DesiredSkillEntry: Codable, Hashable {
    /// The canonical skill name (e.g. "my-tool").
    public var skillName: String
    /// Target version, or nil to accept any installed version.
    public var targetVersion: String?
    /// Whether the skill should be enabled.
    public var isEnabled: Bool

    public init(skillName: String, targetVersion: String? = nil, isEnabled: Bool = true) {
        self.skillName = skillName
        self.targetVersion = targetVersion
        self.isEnabled = isEnabled
    }
}

/// A named desired-state profile that can target one or more sources.
public struct DesiredStateProfile: Identifiable, Codable, Hashable {
    public var id: String
    public var name: String
    /// IDs of sources this profile applies to.
    public var targetSourceIds: [String]
    /// Desired entries, keyed by skill name.
    public var entries: [DesiredSkillEntry]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        targetSourceIds: [String] = [],
        entries: [DesiredSkillEntry] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.targetSourceIds = targetSourceIds
        self.entries = entries
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Sync Plan

/// A single planned action to reconcile actual vs desired state.
public struct SyncAction: Codable, Hashable {
    public enum Kind: String, Codable, Hashable {
        /// Install a skill that is missing.
        case install
        /// Remove a skill that should not exist.
        case remove
        /// Enable a skill that is currently disabled.
        case enable
        /// Disable a skill that is currently enabled.
        case disable
        /// Upgrade or downgrade to the desired version.
        case changeVersion
    }

    public var kind: Kind
    public var skillName: String
    public var sourceId: String
    /// Current version in the inventory (nil if not installed).
    public var currentVersion: String?
    /// Desired version from the profile (nil if no version target).
    public var targetVersion: String?

    public init(
        kind: Kind,
        skillName: String,
        sourceId: String,
        currentVersion: String? = nil,
        targetVersion: String? = nil
    ) {
        self.kind = kind
        self.skillName = skillName
        self.sourceId = sourceId
        self.currentVersion = currentVersion
        self.targetVersion = targetVersion
    }
}

/// A detected conflict that prevents automatic sync resolution.
public struct SyncConflict: Codable, Hashable {
    public enum Kind: String, Codable, Hashable {
        /// Two target sources require different versions of the same shared skill.
        case versionConflict
    }

    public var kind: Kind
    public var skillName: String
    public var conflictingSourceIds: [String]
    public var description: String

    public init(kind: Kind, skillName: String, conflictingSourceIds: [String], description: String) {
        self.kind = kind
        self.skillName = skillName
        self.conflictingSourceIds = conflictingSourceIds
        self.description = description
    }
}

/// The output of the sync engine's diff calculation.
public struct SyncPlan: Codable {
    public var profileId: String
    public var actions: [SyncAction]
    public var conflicts: [SyncConflict]
    public var computedAt: Date

    /// True when there are no conflicts and the plan can be applied.
    public var isApplicable: Bool { conflicts.isEmpty }

    public init(
        profileId: String,
        actions: [SyncAction],
        conflicts: [SyncConflict],
        computedAt: Date = Date()
    ) {
        self.profileId = profileId
        self.actions = actions
        self.conflicts = conflicts
        self.computedAt = computedAt
    }
}

// MARK: - Audit Log

/// The outcome of a single sync action that was applied.
public enum SyncActionOutcome: String, Codable, Hashable {
    case succeeded
    case failed
    case skipped
}

/// A record written to the audit log after a sync action is applied.
public struct SyncAuditEntry: Identifiable, Codable, Hashable {
    public var id: String
    public var profileId: String
    public var skillName: String
    public var sourceId: String
    public var action: SyncAction.Kind
    public var outcome: SyncActionOutcome
    /// Human-readable detail, e.g. error message on failure.
    public var detail: String?
    public var appliedAt: Date

    public init(
        id: String = UUID().uuidString,
        profileId: String,
        action: SyncAction,
        outcome: SyncActionOutcome,
        detail: String? = nil,
        appliedAt: Date = Date()
    ) {
        self.id = id
        self.profileId = profileId
        self.skillName = action.skillName
        self.sourceId = action.sourceId
        self.action = action.kind
        self.outcome = outcome
        self.detail = detail
        self.appliedAt = appliedAt
    }
}
