import Foundation
import SourceDiscovery

/// Scans skill files using a rule set and produces a list of findings.
public final class SecurityScanner {
    private let rules: [SecurityScanRule]
    private let fileManager: FileManager
    private let compiledRules: [(rule: SecurityScanRule, regex: NSRegularExpression)]

    public init(rules: [SecurityScanRule] = SecurityScanRules.defaults, fileManager: FileManager = .default) {
        self.rules = rules
        self.fileManager = fileManager
        self.compiledRules = rules.compactMap { rule in
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]) else { return nil }
            return (rule, regex)
        }
    }

    // MARK: - Public API

    /// Scan a single skill and return any findings.
    public func scan(skill: PersistedSkill) -> [SecurityFinding] {
        let skillURL = URL(fileURLWithPath: skill.path)
        return scanFiles(at: skillURL, skillId: skill.id, skillName: skill.name)
    }

    /// Scan all provided skills and return the combined report.
    /// Findings that match any entry in `ignoreList` are suppressed.
    public func scan(skills: [PersistedSkill], ignoring ignoreList: [SecurityIgnoreEntry] = []) -> SecurityReport {
        let ignoreSet = Set(ignoreList.map { IgnoreKey(skillId: $0.skillId, ruleId: $0.ruleId) })
        var findings: [SecurityFinding] = []
        for skill in skills {
            let raw = scan(skill: skill)
            let filtered = raw.filter { !ignoreSet.contains(IgnoreKey(skillId: $0.skillId, ruleId: $0.ruleId)) }
            findings.append(contentsOf: filtered)
        }
        return SecurityReport(findings: findings)
    }

    // MARK: - Private

    private func scanFiles(at url: URL, skillId: String, skillName: String) -> [SecurityFinding] {
        var findings: [SecurityFinding] = []
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }

        if isDir.boolValue {
            let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            while let child = enumerator?.nextObject() as? URL {
                if (try? child.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    findings.append(contentsOf: scanSingleFile(child, skillId: skillId, skillName: skillName))
                }
            }
        } else {
            findings.append(contentsOf: scanSingleFile(url, skillId: skillId, skillName: skillName))
        }
        return findings
    }

    private func scanSingleFile(_ fileURL: URL, skillId: String, skillName: String) -> [SecurityFinding] {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        var findings: [SecurityFinding] = []
        let lines = content.components(separatedBy: .newlines)
        let now = Date()

        for (rule, regex) in compiledRules {
            for line in lines {
                let range = NSRange(line.startIndex..., in: line)
                if regex.firstMatch(in: line, options: [], range: range) != nil {
                    let truncated = String(line.trimmingCharacters(in: .whitespaces).prefix(200))
                    let finding = SecurityFinding(
                        skillId: skillId,
                        skillName: skillName,
                        ruleId: rule.id,
                        ruleDescription: rule.description,
                        severity: rule.severity,
                        filePath: fileURL.path,
                        matchedContent: truncated,
                        detectedAt: now
                    )
                    findings.append(finding)
                    break // one finding per rule per file
                }
            }
        }
        return findings
    }
}

// MARK: - Helpers

private struct IgnoreKey: Hashable {
    let skillId: String
    let ruleId: String
}
