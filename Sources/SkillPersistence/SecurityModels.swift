import Foundation
import SourceDiscovery

// MARK: - Severity

public enum SecuritySeverity: String, Codable, Hashable, CaseIterable, Comparable {
    case low
    case medium
    case high

    public static func < (lhs: SecuritySeverity, rhs: SecuritySeverity) -> Bool {
        lhs.rank < rhs.rank
    }

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }
}

// MARK: - Scan Rule

/// A single rule used during static scanning of skill files.
public struct SecurityScanRule: Identifiable, Codable, Hashable {
    public let id: String
    /// Human-readable description of what this rule detects.
    public let description: String
    public let severity: SecuritySeverity
    /// Regex pattern applied to file content.
    public let pattern: String

    public init(id: String, description: String, severity: SecuritySeverity, pattern: String) {
        self.id = id
        self.description = description
        self.severity = severity
        self.pattern = pattern
    }
}

// MARK: - Finding

/// A single security issue found in a skill.
public struct SecurityFinding: Identifiable, Codable, Hashable {
    public let id: String
    public let skillId: String
    public let skillName: String
    public let ruleId: String
    public let ruleDescription: String
    public let severity: SecuritySeverity
    /// The file path where the finding was detected.
    public let filePath: String
    /// The line of content that triggered the rule (may be truncated).
    public let matchedContent: String
    public let detectedAt: Date

    public init(
        id: String = UUID().uuidString,
        skillId: String,
        skillName: String,
        ruleId: String,
        ruleDescription: String,
        severity: SecuritySeverity,
        filePath: String,
        matchedContent: String,
        detectedAt: Date = Date()
    ) {
        self.id = id
        self.skillId = skillId
        self.skillName = skillName
        self.ruleId = ruleId
        self.ruleDescription = ruleDescription
        self.severity = severity
        self.filePath = filePath
        self.matchedContent = matchedContent
        self.detectedAt = detectedAt
    }
}

// MARK: - Report

/// All findings from a single scan run, grouped by severity.
public struct SecurityReport: Codable {
    public let scannedAt: Date
    public let findings: [SecurityFinding]

    public init(scannedAt: Date = Date(), findings: [SecurityFinding]) {
        self.scannedAt = scannedAt
        self.findings = findings
    }

    /// Findings grouped by severity, highest first.
    public var byHighestSeverity: [SecuritySeverity: [SecurityFinding]] {
        Dictionary(grouping: findings, by: \.severity)
    }

    /// All findings sorted by severity descending, then skill name.
    public var sorted: [SecurityFinding] {
        findings.sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return $0.skillName < $1.skillName
        }
    }

    public var hasHighSeverity: Bool {
        findings.contains { $0.severity == .high }
    }
}

// MARK: - Ignore List Entry

/// An entry suppressing a specific (skill, rule) combination from future reports.
public struct SecurityIgnoreEntry: Identifiable, Codable, Hashable {
    public let id: String
    public let skillId: String
    public let ruleId: String
    public let addedAt: Date

    public init(id: String = UUID().uuidString, skillId: String, ruleId: String, addedAt: Date = Date()) {
        self.id = id
        self.skillId = skillId
        self.ruleId = ruleId
        self.addedAt = addedAt
    }
}

// MARK: - Remediation Log Entry

/// Records that a remediation action was taken in response to findings.
public struct SecurityRemediationEntry: Identifiable, Codable, Hashable {
    public enum Action: String, Codable, Hashable {
        /// Skill was disabled due to security findings.
        case disabled
        /// Finding was marked as trusted / ignored.
        case trusted
    }

    public let id: String
    public let skillId: String
    public let skillName: String
    public let action: Action
    public let ruleId: String?
    public let appliedAt: Date

    public init(
        id: String = UUID().uuidString,
        skillId: String,
        skillName: String,
        action: Action,
        ruleId: String? = nil,
        appliedAt: Date = Date()
    ) {
        self.id = id
        self.skillId = skillId
        self.skillName = skillName
        self.action = action
        self.ruleId = ruleId
        self.appliedAt = appliedAt
    }
}
