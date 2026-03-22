import Foundation
import SourceDiscovery

/// Wires scan results from SourceDiscoveryService / SkillScanner into the database.
public final class InventoryPersistenceService {
    private let sourceRepo: SourceRepository
    private let skillRepo: SkillRepository

    public init(sourceRepository: SourceRepository, skillRepository: SkillRepository) {
        self.sourceRepo = sourceRepository
        self.skillRepo = skillRepository
    }

    // MARK: - Sources

    /// Persist a newly discovered or registered source.
    /// Skips if the source already exists (idempotent on id).
    public func registerSource(_ source: SkillSource, isActive: Bool = true) throws {
        guard !(try sourceRepo.exists(id: source.id)) else { return }
        try sourceRepo.save(source, isActive: isActive)
    }

    /// Persist an array of discovered sources, skipping duplicates.
    public func registerSources(_ sources: [SkillSource]) throws {
        for source in sources {
            try registerSource(source)
        }
    }

    // MARK: - Scan results

    /// Persist the full result of a source scan: update source health and replace skill inventory.
    public func apply(scanResult: SourceScanResult) throws {
        // Ensure source row exists.
        try sourceRepo.save(scanResult.source)
        // Update source health metadata.
        try sourceRepo.updateScanResult(sourceId: scanResult.source.id, result: scanResult)
        // Replace skills for this source entirely.
        try skillRepo.replaceAll(for: scanResult.source.id, with: scanResult.skills)
    }

    /// Persist multiple scan results.
    public func apply(scanResults: [SourceScanResult]) throws {
        for result in scanResults {
            try apply(scanResult: result)
        }
    }

    // MARK: - Skill enable/disable

    /// Error thrown when attempting to toggle a skill from an unsupported source type.
    public struct EnableDisableNotSupported: Error {
        public let sourceType: SkillSourceType
        public var localizedDescription: String {
            "Source type '\(sourceType.displayName)' does not support enabling or disabling skills."
        }
    }

    /// Enable or disable a skill.
    ///
    /// - Throws: `EnableDisableNotSupported` if the skill's source type does not support the operation.
    /// - Returns: `true` if the skill was found and updated; `false` if no skill with that id exists.
    @discardableResult
    public func setSkillEnabled(skillId: String, isEnabled: Bool) throws -> Bool {
        guard let skill = try skillRepo.fetch(id: skillId) else { return false }
        guard let sourceType = SkillSourceType(rawValue: skill.sourceType) else { return false }
        guard sourceType.supportsEnableDisable else {
            throw EnableDisableNotSupported(sourceType: sourceType)
        }
        return try skillRepo.setEnabled(skillId: skillId, isEnabled: isEnabled)
    }

    // MARK: - Skill install/remove

    /// Error thrown when attempting to install or remove a skill from an unsupported source type.
    public struct InstallRemoveNotSupported: Error {
        public let sourceType: SkillSourceType
        public var localizedDescription: String {
            "Source type '\(sourceType.displayName)' does not support installing or removing skills."
        }
    }

    /// Install a skill package directory into a source, persist the resulting record, and return it.
    ///
    /// - Parameters:
    ///   - packageURL: Path to the skill directory to install.
    ///   - source: The target source.
    ///   - adapter: The adapter for the source type (must support install/remove).
    ///   - context: Scan context passed to the adapter.
    /// - Returns: The newly indexed `SkillRecord`.
    /// - Throws: `InstallRemoveNotSupported` if the source type does not allow it.
    @discardableResult
    public func installSkill(
        packageURL: URL,
        into source: SkillSource,
        using adapter: any SourceAdapter,
        context: SourceScanContext = SourceScanContext()
    ) throws -> SkillRecord {
        guard source.type.supportsInstallRemove else {
            throw InstallRemoveNotSupported(sourceType: source.type)
        }
        let record = try adapter.install(packageURL: packageURL, into: source, context: context)
        try skillRepo.save(record)
        return record
    }

    /// Remove an installed skill from its source and delete the inventory entry.
    ///
    /// - Parameters:
    ///   - skillId: The ID of the skill to remove.
    ///   - adapter: The adapter for the source type (must support install/remove).
    ///   - context: Scan context passed to the adapter.
    /// - Throws: `InstallRemoveNotSupported` if the source type does not allow it.
    public func removeSkill(
        skillId: String,
        using adapter: any SourceAdapter,
        context: SourceScanContext = SourceScanContext()
    ) throws {
        guard let skill = try skillRepo.fetch(id: skillId) else { return }
        guard let sourceType = SkillSourceType(rawValue: skill.sourceType),
              sourceType.supportsInstallRemove else {
            let type = SkillSourceType(rawValue: skill.sourceType) ?? .openClaw
            throw InstallRemoveNotSupported(sourceType: type)
        }
        let path = URL(fileURLWithPath: skill.path)
        let dummySource = SkillSource(id: skill.sourceId, type: sourceType, rootPath: path.deletingLastPathComponent())
        let record = SkillRecord(id: skill.id, name: skill.name, version: skill.version, path: path, source: dummySource)
        try adapter.remove(skill: record, context: context)
        try skillRepo.delete(skillId: skillId)
    }

    // MARK: - Skill version change

    /// Error thrown when attempting to change the version of a skill from an unsupported source type.
    public struct VersionChangeNotSupported: Error {
        public let sourceType: SkillSourceType
        public var localizedDescription: String {
            "Source type '\(sourceType.displayName)' does not support version changes."
        }
    }

    /// Replace an installed skill with a different version and update the inventory.
    ///
    /// - Parameters:
    ///   - skillId: The ID of the installed skill to upgrade or downgrade.
    ///   - newPackageURL: Path to the replacement skill directory.
    ///   - adapter: The adapter for the source type (must support version change).
    ///   - context: Scan context passed to the adapter.
    /// - Returns: The updated `SkillRecord` reflecting the new version.
    /// - Throws: `VersionChangeNotSupported` if the source type does not allow it.
    @discardableResult
    public func changeSkillVersion(
        skillId: String,
        to newPackageURL: URL,
        using adapter: any SourceAdapter,
        context: SourceScanContext = SourceScanContext()
    ) throws -> SkillRecord {
        guard let skill = try skillRepo.fetch(id: skillId) else {
            throw SkillLifecycleError(code: .skillNotFound, message: "No skill found with id: \(skillId)")
        }
        guard let sourceType = SkillSourceType(rawValue: skill.sourceType),
              sourceType.supportsVersionChange else {
            let type = SkillSourceType(rawValue: skill.sourceType) ?? .openClaw
            throw VersionChangeNotSupported(sourceType: type)
        }
        let skillPath = URL(fileURLWithPath: skill.path)
        let source = SkillSource(id: skill.sourceId, type: sourceType, rootPath: skillPath.deletingLastPathComponent())
        let record = SkillRecord(id: skill.id, name: skill.name, version: skill.version, path: skillPath, source: source)
        let updated = try adapter.changeVersion(of: record, to: newPackageURL, in: source, context: context)
        // Delete the old DB row (id is path-based, so it changes when directory name changes).
        try skillRepo.delete(skillId: skillId)
        try skillRepo.save(updated, isEnabled: skill.isEnabled)
        return updated
    }

    // MARK: - Incremental updates

    /// Apply incremental changes from IncrementalInventoryUpdater to the database.
    public func apply(incrementalResults: [IncrementalUpdateResult]) throws {
        for result in incrementalResults {
            switch result.change {
            case .added(let record):
                try skillRepo.save(record)
            case .updated(let record):
                try skillRepo.save(record)
            case .removed(let skillId):
                try skillRepo.delete(skillId: skillId)
            }
        }
    }
}
