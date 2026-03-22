import Foundation
import SourceDiscovery

/// High-level service for security scanning and remediation.
public final class SecurityService {
    private let skillRepository: SkillRepository
    private let securityRepository: SecurityReportRepository
    private let scanner: SecurityScanner

    public init(
        skillRepository: SkillRepository,
        securityRepository: SecurityReportRepository,
        scanner: SecurityScanner = SecurityScanner()
    ) {
        self.skillRepository = skillRepository
        self.securityRepository = securityRepository
        self.scanner = scanner
    }

    // MARK: - Scan

    /// Scan all indexed skills (filtered by optional sourceId) and persist the report.
    /// Findings matching the stored ignore list are suppressed.
    @discardableResult
    public func runScan(sourceId: String? = nil) throws -> SecurityReport {
        let skills: [PersistedSkill]
        if let sourceId {
            skills = try skillRepository.fetch(sourceId: sourceId)
        } else {
            skills = try skillRepository.fetchAll()
        }
        let ignoreList = try securityRepository.fetchIgnoreList()
        let report = scanner.scan(skills: skills, ignoring: ignoreList)
        try securityRepository.saveReport(report)
        return report
    }

    /// Return the last persisted report without re-scanning.
    public func fetchReport() throws -> SecurityReport {
        try securityRepository.fetchReport()
    }

    // MARK: - Remediation: Disable Skill

    /// Disable a skill and record the action in the remediation log.
    public func disableSkill(skillId: String) throws {
        guard let skill = try skillRepository.fetch(id: skillId) else {
            throw SecurityServiceError.skillNotFound(skillId)
        }
        try skillRepository.setEnabled(skillId: skillId, isEnabled: false)
        let entry = SecurityRemediationEntry(
            skillId: skillId,
            skillName: skill.name,
            action: .disabled
        )
        try securityRepository.appendRemediationEntry(entry)
    }

    // MARK: - Remediation: Trust (mark finding as trusted)

    /// Mark a specific (skill, rule) combination as trusted, adding it to the ignore list
    /// and recording the action in the remediation log.
    public func trustFinding(skillId: String, ruleId: String) throws {
        guard let skill = try skillRepository.fetch(id: skillId) else {
            throw SecurityServiceError.skillNotFound(skillId)
        }
        let ignore = SecurityIgnoreEntry(skillId: skillId, ruleId: ruleId)
        try securityRepository.addIgnoreEntry(ignore)
        let entry = SecurityRemediationEntry(
            skillId: skillId,
            skillName: skill.name,
            action: .trusted,
            ruleId: ruleId
        )
        try securityRepository.appendRemediationEntry(entry)
    }

    // MARK: - Ignore List

    /// Fetch the current ignore list.
    public func fetchIgnoreList() throws -> [SecurityIgnoreEntry] {
        try securityRepository.fetchIgnoreList()
    }

    /// Remove a specific entry from the ignore list (re-enables future alerts).
    public func removeIgnoreEntry(skillId: String, ruleId: String) throws {
        try securityRepository.removeIgnoreEntry(skillId: skillId, ruleId: ruleId)
    }

    // MARK: - Remediation Log

    public func fetchRemediationLog() throws -> [SecurityRemediationEntry] {
        try securityRepository.fetchRemediationLog()
    }
}

// MARK: - Errors

public enum SecurityServiceError: Error, Equatable {
    case skillNotFound(String)
}
