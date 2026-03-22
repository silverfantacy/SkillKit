import XCTest
import SourceDiscovery
@testable import SkillPersistence

final class SkillSecurityScanTests: XCTestCase {

    // MARK: - Helpers

    private func makeDB() throws -> AppDatabase { try AppDatabase.makeInMemory() }

    private func makeSkill(name: String, path: String, db: AppDatabase) throws -> PersistedSkill {
        let sourceRepo = SourceRepository(database: db)
        let skillRepo = SkillRepository(database: db)
        let source = SkillSource(type: .project, rootPath: URL(fileURLWithPath: "/tmp/\(name)-src"))
        try sourceRepo.save(source)
        let record = SkillRecord(name: name, version: "1.0", path: URL(fileURLWithPath: path), source: source)
        try skillRepo.save(record)
        return try skillRepo.fetch(id: record.id)!
    }

    // MARK: - 6.1 SecurityScanner – Rule-Based Scanning

    func testScannerDetectsRiskyCommand() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("scanner-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let script = tmp.appendingPathComponent("run.sh")
        try "rm -rf /tmp/important".write(to: script, atomically: true, encoding: .utf8)

        let db = try makeDB()
        let skill = try makeSkill(name: "risky-skill", path: tmp.path, db: db)

        let scanner = SecurityScanner()
        let findings = scanner.scan(skill: skill)

        XCTAssertFalse(findings.isEmpty)
        XCTAssertTrue(findings.contains { $0.ruleId == "risky-rm-rf" })
        XCTAssertEqual(findings.first { $0.ruleId == "risky-rm-rf" }?.severity, .high)
    }

    func testScannerIgnoresCleanSkill() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("clean-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let script = tmp.appendingPathComponent("run.sh")
        try "echo hello world".write(to: script, atomically: true, encoding: .utf8)

        let db = try makeDB()
        let skill = try makeSkill(name: "clean-skill", path: tmp.path, db: db)

        let scanner = SecurityScanner()
        let findings = scanner.scan(skill: skill)
        XCTAssertTrue(findings.isEmpty)
    }

    func testScannerReturnsOneMatchPerRulePerFile() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("dedup-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let script = tmp.appendingPathComponent("run.sh")
        // Two occurrences of sudo – scanner should emit one finding per rule per file.
        try "sudo foo\nsudo bar".write(to: script, atomically: true, encoding: .utf8)

        let db = try makeDB()
        let skill = try makeSkill(name: "multi-sudo", path: tmp.path, db: db)

        let scanner = SecurityScanner()
        let findings = scanner.scan(skill: skill)
        let sudoFindings = findings.filter { $0.ruleId == "risky-sudo" }
        XCTAssertEqual(sudoFindings.count, 1)
    }

    // MARK: - 6.2 SecurityReport – Grouped by Severity

    func testReportGroupsByHighestSeverity() {
        let finding1 = SecurityFinding(skillId: "s1", skillName: "a", ruleId: "r1", ruleDescription: "d1", severity: .high, filePath: "/a", matchedContent: "x")
        let finding2 = SecurityFinding(skillId: "s2", skillName: "b", ruleId: "r2", ruleDescription: "d2", severity: .low, filePath: "/b", matchedContent: "y")
        let report = SecurityReport(findings: [finding1, finding2])

        let grouped = report.byHighestSeverity
        XCTAssertEqual(grouped[.high]?.count, 1)
        XCTAssertEqual(grouped[.low]?.count, 1)
        XCTAssertNil(grouped[.medium])
    }

    func testReportSortedPutsHighFirst() {
        let high = SecurityFinding(skillId: "s1", skillName: "a", ruleId: "r1", ruleDescription: "d", severity: .high, filePath: "/a", matchedContent: "")
        let medium = SecurityFinding(skillId: "s2", skillName: "b", ruleId: "r2", ruleDescription: "d", severity: .medium, filePath: "/b", matchedContent: "")
        let low = SecurityFinding(skillId: "s3", skillName: "c", ruleId: "r3", ruleDescription: "d", severity: .low, filePath: "/c", matchedContent: "")
        let report = SecurityReport(findings: [low, high, medium])
        XCTAssertEqual(report.sorted.first?.severity, .high)
        XCTAssertEqual(report.sorted.last?.severity, .low)
    }

    func testSecurityReportRepositorySaveAndFetch() throws {
        let db = try makeDB()
        let repo = SecurityReportRepository(database: db)

        let finding = SecurityFinding(skillId: "s1", skillName: "skill-a", ruleId: "risky-sudo", ruleDescription: "sudo", severity: .high, filePath: "/a/run.sh", matchedContent: "sudo foo")
        let report = SecurityReport(findings: [finding])
        try repo.saveReport(report)

        let fetched = try repo.fetchReport()
        XCTAssertEqual(fetched.findings.count, 1)
        XCTAssertEqual(fetched.findings.first?.ruleId, "risky-sudo")
        XCTAssertEqual(fetched.findings.first?.severity, .high)
    }

    func testSaveReportReplacesOldFindings() throws {
        let db = try makeDB()
        let repo = SecurityReportRepository(database: db)

        let old = SecurityFinding(skillId: "s1", skillName: "a", ruleId: "r1", ruleDescription: "d", severity: .low, filePath: "/a", matchedContent: "")
        try repo.saveReport(SecurityReport(findings: [old]))

        let new1 = SecurityFinding(skillId: "s2", skillName: "b", ruleId: "r2", ruleDescription: "d", severity: .high, filePath: "/b", matchedContent: "")
        let new2 = SecurityFinding(skillId: "s3", skillName: "c", ruleId: "r3", ruleDescription: "d", severity: .medium, filePath: "/c", matchedContent: "")
        try repo.saveReport(SecurityReport(findings: [new1, new2]))

        let fetched = try repo.fetchReport()
        XCTAssertEqual(fetched.findings.count, 2)
        XCTAssertFalse(fetched.findings.contains { $0.id == old.id })
    }

    // MARK: - 6.3 Remediation – Disable Skill

    func testDisableSkillPersistsAndLogsAction() throws {
        let db = try makeDB()
        let skillRepo = SkillRepository(database: db)
        let secRepo = SecurityReportRepository(database: db)
        let service = SecurityService(skillRepository: skillRepo, securityRepository: secRepo)

        let skill = try makeSkill(name: "bad-skill", path: "/tmp/bad-skill", db: db)
        XCTAssertEqual(try skillRepo.fetch(id: skill.id)?.isEnabled, true)

        try service.disableSkill(skillId: skill.id)

        XCTAssertEqual(try skillRepo.fetch(id: skill.id)?.isEnabled, false)
        let log = try service.fetchRemediationLog()
        XCTAssertEqual(log.count, 1)
        XCTAssertEqual(log.first?.action, .disabled)
        XCTAssertEqual(log.first?.skillName, "bad-skill")
    }

    func testDisableSkillThrowsForUnknownId() throws {
        let db = try makeDB()
        let service = SecurityService(
            skillRepository: SkillRepository(database: db),
            securityRepository: SecurityReportRepository(database: db)
        )
        XCTAssertThrowsError(try service.disableSkill(skillId: "no-such-id")) { error in
            XCTAssertEqual(error as? SecurityServiceError, .skillNotFound("no-such-id"))
        }
    }

    // MARK: - 6.4 Ignore List

    func testTrustFindingAddsToIgnoreListAndLogs() throws {
        let db = try makeDB()
        let skillRepo = SkillRepository(database: db)
        let secRepo = SecurityReportRepository(database: db)
        let service = SecurityService(skillRepository: skillRepo, securityRepository: secRepo)

        let skill = try makeSkill(name: "known-skill", path: "/tmp/known-skill", db: db)
        try service.trustFinding(skillId: skill.id, ruleId: "risky-sudo")

        let ignoreList = try service.fetchIgnoreList()
        XCTAssertEqual(ignoreList.count, 1)
        XCTAssertEqual(ignoreList.first?.skillId, skill.id)
        XCTAssertEqual(ignoreList.first?.ruleId, "risky-sudo")

        let log = try service.fetchRemediationLog()
        XCTAssertEqual(log.first?.action, .trusted)
        XCTAssertEqual(log.first?.ruleId, "risky-sudo")
    }

    func testRemoveIgnoreEntryRestoresFutureFinding() throws {
        let db = try makeDB()
        let skillRepo = SkillRepository(database: db)
        let secRepo = SecurityReportRepository(database: db)
        let service = SecurityService(skillRepository: skillRepo, securityRepository: secRepo)

        let skill = try makeSkill(name: "skill-x", path: "/tmp/skill-x", db: db)
        try service.trustFinding(skillId: skill.id, ruleId: "risky-sudo")
        XCTAssertEqual(try service.fetchIgnoreList().count, 1)

        try service.removeIgnoreEntry(skillId: skill.id, ruleId: "risky-sudo")
        XCTAssertEqual(try service.fetchIgnoreList().count, 0)
    }

    func testScanSupressesIgnoredFindings() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ignore-scan-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let script = tmp.appendingPathComponent("run.sh")
        try "sudo do-something".write(to: script, atomically: true, encoding: .utf8)

        let db = try makeDB()
        let skillRepo = SkillRepository(database: db)
        let secRepo = SecurityReportRepository(database: db)
        let service = SecurityService(skillRepository: skillRepo, securityRepository: secRepo)

        let skill = try makeSkill(name: "ok-sudo-skill", path: tmp.path, db: db)
        try service.trustFinding(skillId: skill.id, ruleId: "risky-sudo")

        let report = try service.runScan()
        XCTAssertFalse(report.findings.contains { $0.ruleId == "risky-sudo" && $0.skillId == skill.id })
    }
}
