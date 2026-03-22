import XCTest
import SourceDiscovery
@testable import SkillPersistence

/// End-to-end integration tests for OrchestrationService:
/// discovery → indexing → sync planning/apply → security scan.
final class OrchestrationIntegrationTests: XCTestCase {

    // MARK: - Helpers

    private func makeDB() throws -> AppDatabase { try AppDatabase.makeInMemory() }

    /// Creates a temporary skill directory with a manifest and optional content files.
    private func makeSkillDirectory(
        in root: URL,
        name: String,
        version: String,
        extraFiles: [String: String] = [:]
    ) throws -> URL {
        let dir = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifest = #"{"name":"\#(name)","version":"\#(version)"}"#
        try manifest.data(using: .utf8)!.write(to: dir.appendingPathComponent("skill.json"))
        for (filename, content) in extraFiles {
            try content.data(using: .utf8)!.write(to: dir.appendingPathComponent(filename))
        }
        return dir
    }

    private func makeOrchestration(
        db: AppDatabase,
        adapters: [any SourceAdapter]
    ) -> OrchestrationService {
        let skillRepo = SkillRepository(database: db)
        let sourceRepo = SourceRepository(database: db)
        let securityRepo = SecurityReportRepository(database: db)

        let persistence = InventoryPersistenceService(sourceRepository: sourceRepo, skillRepository: skillRepo)
        let security = SecurityService(skillRepository: skillRepo, securityRepository: securityRepo)
        let discovery = SourceDiscoveryService(adapters: adapters)

        return OrchestrationService(
            discoveryService: discovery,
            persistenceService: persistence,
            securityService: security
        )
    }

    // MARK: - 7.1 Full pipeline: discovery → indexing → security scan

    func testFullPipelineIndexesDiscoveredSkills() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("orch-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Set up two skills in a project source root.
        let root = tmp.appendingPathComponent("skills")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try makeSkillDirectory(in: root, name: "commit", version: "1.0.0")
        try makeSkillDirectory(in: root, name: "review-pr", version: "2.0.0")

        let db = try makeDB()
        let source = SkillSource(type: .project, rootPath: root)
        let adapters: [any SourceAdapter] = [ProjectSourceAdapter()]
        let orchestration = makeOrchestration(db: db, adapters: adapters)

        let detectionContext = SourceDetectionContext(
            homeDirectory: tmp,
            projectRoots: [tmp],
            fileManager: .default,
            claudeCodeRoots: [],
            openClawRoots: []
        )

        let result = orchestration.runFullPipeline(
            detectionContext: detectionContext,
            scanContext: SourceScanContext(),
            runSecurityScan: true
        )

        // Should find the project source.
        XCTAssertEqual(result.discoveredSources.count, 1)
        XCTAssertEqual(result.discoveredSources.first?.type, .project)

        // Should index both skills.
        XCTAssertEqual(result.indexedSkillCount, 2)
        XCTAssertEqual(result.scanResults.count, 1)
        XCTAssertEqual(result.scanResults.first?.skills.count, 2)

        // Should produce a security report (no findings for clean skills).
        XCTAssertNotNil(result.securityReport)
        XCTAssertEqual(result.securityReport?.findings.count, 0)

        // Skills should be persisted in DB.
        let skillRepo = SkillRepository(database: db)
        let persisted = try skillRepo.fetchAll()
        XCTAssertEqual(persisted.count, 2)
        let names = Set(persisted.map(\.name))
        XCTAssertTrue(names.contains("commit"))
        XCTAssertTrue(names.contains("review-pr"))
    }

    func testFullPipelineDetectsSecurityFinding() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("orch-sec-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let root = tmp.appendingPathComponent("skills")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // This skill contains a high-severity pattern ("rm -rf").
        try makeSkillDirectory(
            in: root,
            name: "risky-skill",
            version: "1.0.0",
            extraFiles: ["run.sh": "#!/bin/bash\nrm -rf /tmp/something"]
        )

        let db = try makeDB()
        let adapters: [any SourceAdapter] = [ProjectSourceAdapter()]
        let orchestration = makeOrchestration(db: db, adapters: adapters)

        let detectionContext = SourceDetectionContext(
            homeDirectory: tmp,
            projectRoots: [tmp],
            fileManager: .default,
            claudeCodeRoots: [],
            openClawRoots: []
        )

        let result = orchestration.runFullPipeline(
            detectionContext: detectionContext,
            scanContext: SourceScanContext(),
            runSecurityScan: true
        )

        XCTAssertNotNil(result.securityReport)
        XCTAssertGreaterThan(result.securityReport?.findings.count ?? 0, 0)
        let finding = result.securityReport?.findings.first
        XCTAssertEqual(finding?.skillName, "risky-skill")
        XCTAssertEqual(finding?.severity, .high)
    }

    func testFullPipelineIsIdempotent() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("orch-idempotent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let root = tmp.appendingPathComponent("skills")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try makeSkillDirectory(in: root, name: "my-tool", version: "1.0.0")

        let db = try makeDB()
        let adapters: [any SourceAdapter] = [ProjectSourceAdapter()]
        let orchestration = makeOrchestration(db: db, adapters: adapters)

        let ctx = SourceDetectionContext(
            homeDirectory: tmp,
            projectRoots: [tmp],
            fileManager: .default,
            claudeCodeRoots: [],
            openClawRoots: []
        )

        // Run twice — should not duplicate sources or skills.
        _ = orchestration.runFullPipeline(detectionContext: ctx)
        _ = orchestration.runFullPipeline(detectionContext: ctx)

        let skillRepo = SkillRepository(database: db)
        let sourceRepo = SourceRepository(database: db)
        let skills = try skillRepo.fetchAll()
        let sources = try sourceRepo.fetchAll()
        XCTAssertEqual(skills.count, 1)
        XCTAssertEqual(sources.count, 1)
    }

    func testRescanUpdatesInventory() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("orch-rescan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let root = tmp.appendingPathComponent("skills")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try makeSkillDirectory(in: root, name: "initial-skill", version: "1.0.0")

        let db = try makeDB()
        let adapters: [any SourceAdapter] = [ProjectSourceAdapter()]
        let orchestration = makeOrchestration(db: db, adapters: adapters)

        let ctx = SourceDetectionContext(
            homeDirectory: tmp,
            projectRoots: [tmp],
            fileManager: .default,
            claudeCodeRoots: [],
            openClawRoots: []
        )
        // Initial pipeline run.
        _ = orchestration.runFullPipeline(detectionContext: ctx)

        let skillRepo = SkillRepository(database: db)
        let sourceRepo = SourceRepository(database: db)
        XCTAssertEqual(try skillRepo.fetchAll().count, 1)

        // Add a second skill on disk.
        try makeSkillDirectory(in: root, name: "added-skill", version: "0.5.0")

        // Re-scan the source.
        let source = try sourceRepo.fetchAll().first!
        let rescanResult = orchestration.rescan(source: source)
        XCTAssertEqual(rescanResult.indexedSkillCount, 2)

        // DB should now contain 2 skills.
        XCTAssertEqual(try skillRepo.fetchAll().count, 2)
    }

    // MARK: - 7.1 Sync plan + apply wired through pipeline

    func testSyncPlanAndApplyAfterOrchestration() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("orch-sync-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let root = tmp.appendingPathComponent("skills")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try makeSkillDirectory(in: root, name: "tool-a", version: "1.0.0")
        try makeSkillDirectory(in: root, name: "tool-b", version: "2.0.0")

        let db = try makeDB()
        let skillRepo = SkillRepository(database: db)
        let sourceRepo = SourceRepository(database: db)
        let dsRepo = DesiredStateRepository(database: db)
        let auditRepo = SyncAuditRepository(database: db)

        let adapters: [any SourceAdapter] = [ProjectSourceAdapter()]
        let orchestration = makeOrchestration(db: db, adapters: adapters)

        // Step 1: Run pipeline to populate inventory.
        let ctx = SourceDetectionContext(
            homeDirectory: tmp,
            projectRoots: [tmp],
            fileManager: .default,
            claudeCodeRoots: [],
            openClawRoots: []
        )
        _ = orchestration.runFullPipeline(detectionContext: ctx)

        let indexedSkills = try skillRepo.fetchAll()
        XCTAssertEqual(indexedSkills.count, 2)

        // Step 2: Enable tool-a, disable tool-b via setEnabled directly.
        let toolA = indexedSkills.first(where: { $0.name == "tool-a" })!
        let toolB = indexedSkills.first(where: { $0.name == "tool-b" })!
        try skillRepo.setEnabled(skillId: toolA.id, isEnabled: true)
        try skillRepo.setEnabled(skillId: toolB.id, isEnabled: true)

        // Step 3: Create a desired state profile that wants tool-b disabled.
        let source = try sourceRepo.fetchAll().first!
        let profile = DesiredStateProfile(
            name: "test-profile",
            targetSourceIds: [source.id],
            entries: [
                DesiredSkillEntry(skillName: "tool-a", isEnabled: true),
                DesiredSkillEntry(skillName: "tool-b", isEnabled: false)
            ]
        )
        try dsRepo.save(profile)

        // Step 4: Compute sync plan.
        let engine = SyncEngine(
            skillRepository: skillRepo,
            desiredStateRepository: dsRepo,
            auditRepository: auditRepo
        )
        let plan = try engine.plan(profileId: profile.id)

        // Expect one disable action for tool-b.
        XCTAssertTrue(plan.conflicts.isEmpty)
        XCTAssertTrue(plan.isApplicable)
        let disableActions = plan.actions.filter { $0.kind == .disable }
        XCTAssertEqual(disableActions.count, 1)
        XCTAssertEqual(disableActions.first?.skillName, "tool-b")

        // Step 5: Apply the plan.
        let auditEntries = try engine.apply(plan: plan)
        XCTAssertEqual(auditEntries.filter { $0.outcome == .succeeded }.count, 1)

        // tool-b should now be disabled in DB.
        let updatedToolB = try skillRepo.fetch(id: toolB.id)
        XCTAssertEqual(updatedToolB?.isEnabled, false)
    }

    func testPipelineCollectsNonFatalErrorsWithoutAborting() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("orch-errors-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // No actual skills on disk — root doesn't exist.
        let db = try makeDB()
        let adapters: [any SourceAdapter] = [ProjectSourceAdapter()]
        let orchestration = makeOrchestration(db: db, adapters: adapters)

        let ctx = SourceDetectionContext(
            homeDirectory: tmp,
            projectRoots: [tmp.appendingPathComponent("nonexistent")],
            fileManager: .default,
            claudeCodeRoots: [],
            openClawRoots: []
        )
        // Should complete without throwing even though no sources are found.
        let result = orchestration.runFullPipeline(detectionContext: ctx)
        XCTAssertEqual(result.discoveredSources.count, 0)
        XCTAssertEqual(result.indexedSkillCount, 0)
    }
}
