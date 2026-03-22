import XCTest
import SourceDiscovery
@testable import SkillPersistence

final class SkillSyncTests: XCTestCase {

    // MARK: - Helpers

    private func makeDB() throws -> AppDatabase { try AppDatabase.makeInMemory() }

    private func makeRepos(db: AppDatabase) -> (SourceRepository, SkillRepository, DesiredStateRepository, SyncAuditRepository) {
        (
            SourceRepository(database: db),
            SkillRepository(database: db),
            DesiredStateRepository(database: db),
            SyncAuditRepository(database: db)
        )
    }

    private func makeEngine(db: AppDatabase) -> SyncEngine {
        let (_, skillRepo, dsRepo, auditRepo) = makeRepos(db: db)
        return SyncEngine(skillRepository: skillRepo, desiredStateRepository: dsRepo, auditRepository: auditRepo)
    }

    // MARK: - 5.1  Desired State Profile persistence

    func testSaveAndFetchProfile() throws {
        let db = try makeDB()
        let (_, _, dsRepo, _) = makeRepos(db: db)

        let profile = DesiredStateProfile(
            name: "My Profile",
            targetSourceIds: ["src-1", "src-2"],
            entries: [DesiredSkillEntry(skillName: "my-tool", targetVersion: "2.0", isEnabled: true)]
        )
        try dsRepo.save(profile)

        let fetched = try dsRepo.fetch(id: profile.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "My Profile")
        XCTAssertEqual(fetched?.targetSourceIds, ["src-1", "src-2"])
        XCTAssertEqual(fetched?.entries.first?.skillName, "my-tool")
        XCTAssertEqual(fetched?.entries.first?.targetVersion, "2.0")
    }

    func testFetchAllProfilesReturnsAll() throws {
        let db = try makeDB()
        let (_, _, dsRepo, _) = makeRepos(db: db)

        try dsRepo.save(DesiredStateProfile(name: "A"))
        try dsRepo.save(DesiredStateProfile(name: "B"))

        XCTAssertEqual(try dsRepo.fetchAll().count, 2)
    }

    func testDeleteProfile() throws {
        let db = try makeDB()
        let (_, _, dsRepo, _) = makeRepos(db: db)

        let p = DesiredStateProfile(name: "ToDelete")
        try dsRepo.save(p)
        try dsRepo.delete(profileId: p.id)
        XCTAssertNil(try dsRepo.fetch(id: p.id))
    }

    func testSaveProfileIsIdempotent() throws {
        let db = try makeDB()
        let (_, _, dsRepo, _) = makeRepos(db: db)

        var p = DesiredStateProfile(name: "Upsert")
        try dsRepo.save(p)

        p.name = "Upserted"
        try dsRepo.save(p)

        let all = try dsRepo.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.name, "Upserted")
    }

    // MARK: - 5.2  Sync plan generation

    func testPlanProducesInstallForMissingSkill() throws {
        let db = try makeDB()
        let (sourceRepo, _, dsRepo, _) = makeRepos(db: db)
        let engine = makeEngine(db: db)

        let source = SkillSource(id: "src-a", type: .project, rootPath: URL(fileURLWithPath: "/tmp/a"))
        try sourceRepo.save(source)

        let profile = DesiredStateProfile(
            name: "p1",
            targetSourceIds: ["src-a"],
            entries: [DesiredSkillEntry(skillName: "missing-tool")]
        )
        try dsRepo.save(profile)

        let plan = try engine.plan(profileId: profile.id)
        XCTAssertTrue(plan.conflicts.isEmpty)
        XCTAssertEqual(plan.actions.count, 1)
        XCTAssertEqual(plan.actions.first?.kind, .install)
        XCTAssertEqual(plan.actions.first?.skillName, "missing-tool")
    }

    func testPlanProducesEnableActionForDisabledSkill() throws {
        let db = try makeDB()
        let (sourceRepo, skillRepo, dsRepo, _) = makeRepos(db: db)
        let engine = makeEngine(db: db)

        let source = SkillSource(id: "src-b", type: .claudeCode, rootPath: URL(fileURLWithPath: "/tmp/b"))
        try sourceRepo.save(source)

        let skill = SkillRecord(name: "alpha", version: "1.0", path: URL(fileURLWithPath: "/tmp/b/alpha"), source: source)
        try skillRepo.save(skill, isEnabled: false)

        let profile = DesiredStateProfile(
            name: "p2",
            targetSourceIds: ["src-b"],
            entries: [DesiredSkillEntry(skillName: "alpha", isEnabled: true)]
        )
        try dsRepo.save(profile)

        let plan = try engine.plan(profileId: profile.id)
        XCTAssertTrue(plan.conflicts.isEmpty)
        let enableAction = plan.actions.first { $0.kind == .enable }
        XCTAssertNotNil(enableAction)
        XCTAssertEqual(enableAction?.skillName, "alpha")
    }

    func testPlanProducesChangeVersionForVersionMismatch() throws {
        let db = try makeDB()
        let (sourceRepo, skillRepo, dsRepo, _) = makeRepos(db: db)
        let engine = makeEngine(db: db)

        let source = SkillSource(id: "src-c", type: .project, rootPath: URL(fileURLWithPath: "/tmp/c"))
        try sourceRepo.save(source)

        let skill = SkillRecord(name: "beta", version: "1.0", path: URL(fileURLWithPath: "/tmp/c/beta"), source: source)
        try skillRepo.save(skill)

        let profile = DesiredStateProfile(
            name: "p3",
            targetSourceIds: ["src-c"],
            entries: [DesiredSkillEntry(skillName: "beta", targetVersion: "2.0")]
        )
        try dsRepo.save(profile)

        let plan = try engine.plan(profileId: profile.id)
        XCTAssertTrue(plan.conflicts.isEmpty)
        let cvAction = plan.actions.first { $0.kind == .changeVersion }
        XCTAssertNotNil(cvAction)
        XCTAssertEqual(cvAction?.currentVersion, "1.0")
        XCTAssertEqual(cvAction?.targetVersion, "2.0")
    }

    func testPlanThrowsForUnknownProfile() throws {
        let db = try makeDB()
        let engine = makeEngine(db: db)
        XCTAssertThrowsError(try engine.plan(profileId: "no-such-id")) { error in
            guard let e = error as? SyncError else { return XCTFail("wrong error type") }
            XCTAssertEqual(e.code, .profileNotFound)
        }
    }

    func testPlanIsApplicableWhenNoConflicts() throws {
        let db = try makeDB()
        let (_, _, dsRepo, _) = makeRepos(db: db)
        let engine = makeEngine(db: db)

        let p = DesiredStateProfile(name: "clean", targetSourceIds: [], entries: [])
        try dsRepo.save(p)

        let plan = try engine.plan(profileId: p.id)
        XCTAssertTrue(plan.isApplicable)
        XCTAssertTrue(plan.actions.isEmpty)
    }

    // MARK: - 5.3  Conflict detection

    func testConflictDetectedForDivergingVersionsAcrossSources() throws {
        let db = try makeDB()
        let (sourceRepo, skillRepo, dsRepo, _) = makeRepos(db: db)
        let engine = makeEngine(db: db)

        let srcA = SkillSource(id: "src-x", type: .project, rootPath: URL(fileURLWithPath: "/tmp/x"))
        let srcB = SkillSource(id: "src-y", type: .project, rootPath: URL(fileURLWithPath: "/tmp/y"))
        try sourceRepo.save(srcA)
        try sourceRepo.save(srcB)

        // Same skill but different installed versions in two sources.
        let skillX = SkillRecord(name: "shared", version: "1.0", path: URL(fileURLWithPath: "/tmp/x/shared"), source: srcA)
        let skillY = SkillRecord(name: "shared", version: "2.0", path: URL(fileURLWithPath: "/tmp/y/shared"), source: srcB)
        try skillRepo.save(skillX)
        try skillRepo.save(skillY)

        let profile = DesiredStateProfile(
            name: "conflict-test",
            targetSourceIds: ["src-x", "src-y"],
            entries: [DesiredSkillEntry(skillName: "shared", targetVersion: "2.0")]
        )
        try dsRepo.save(profile)

        let plan = try engine.plan(profileId: profile.id)
        XCTAssertFalse(plan.isApplicable)
        XCTAssertEqual(plan.conflicts.count, 1)
        XCTAssertEqual(plan.conflicts.first?.kind, .versionConflict)
        XCTAssertEqual(plan.conflicts.first?.skillName, "shared")
    }

    func testApplyThrowsWhenPlanHasConflicts() throws {
        let db = try makeDB()
        let engine = makeEngine(db: db)

        let conflict = SyncConflict(kind: .versionConflict, skillName: "x", conflictingSourceIds: ["s1"], description: "test")
        let plan = SyncPlan(profileId: "p", actions: [], conflicts: [conflict])

        XCTAssertThrowsError(try engine.apply(plan: plan)) { error in
            guard let e = error as? SyncError else { return XCTFail("wrong error type") }
            XCTAssertEqual(e.code, .planHasConflicts)
        }
    }

    // MARK: - 5.4  Sync audit log

    func testAuditLogRecordsAppliedActions() throws {
        let db = try makeDB()
        let (sourceRepo, skillRepo, dsRepo, auditRepo) = makeRepos(db: db)
        let engine = makeEngine(db: db)

        let source = SkillSource(id: "src-audit", type: .claudeCode, rootPath: URL(fileURLWithPath: "/tmp/audit"))
        try sourceRepo.save(source)

        let skill = SkillRecord(name: "log-me", version: nil, path: URL(fileURLWithPath: "/tmp/audit/log-me"), source: source)
        try skillRepo.save(skill, isEnabled: false)

        let profile = DesiredStateProfile(
            name: "audit-profile",
            targetSourceIds: ["src-audit"],
            entries: [DesiredSkillEntry(skillName: "log-me", isEnabled: true)]
        )
        try dsRepo.save(profile)

        let plan = try engine.plan(profileId: profile.id)
        XCTAssertTrue(plan.isApplicable)

        let entries = try engine.apply(plan: plan)
        XCTAssertFalse(entries.isEmpty)
        XCTAssertEqual(entries.first?.skillName, "log-me")
        XCTAssertEqual(entries.first?.action, .enable)
        XCTAssertEqual(entries.first?.outcome, .succeeded)

        // Verify audit log persisted.
        let stored = try auditRepo.fetch(profileId: profile.id)
        XCTAssertEqual(stored.count, entries.count)
        XCTAssertEqual(stored.first?.outcome, .succeeded)
    }

    func testAuditLogFetchAll() throws {
        let db = try makeDB()
        let (_, _, _, auditRepo) = makeRepos(db: db)

        let fakeAction = SyncAction(kind: .install, skillName: "x", sourceId: "s1")
        try auditRepo.append(SyncAuditEntry(profileId: "p1", action: fakeAction, outcome: .skipped))
        try auditRepo.append(SyncAuditEntry(profileId: "p2", action: fakeAction, outcome: .failed, detail: "oops"))

        let all = try auditRepo.fetchAll()
        XCTAssertEqual(all.count, 2)
    }

    func testAuditLogFetchByDateRange() throws {
        let db = try makeDB()
        let (_, _, _, auditRepo) = makeRepos(db: db)

        let fakeAction = SyncAction(kind: .enable, skillName: "y", sourceId: "s2")
        let past = Date(timeIntervalSinceNow: -3600)
        let now = Date()

        try auditRepo.append(SyncAuditEntry(profileId: "p", action: fakeAction, outcome: .succeeded, appliedAt: past))
        try auditRepo.append(SyncAuditEntry(profileId: "p", action: fakeAction, outcome: .succeeded, appliedAt: now))

        let recent = try auditRepo.fetch(from: Date(timeIntervalSinceNow: -60), to: Date(timeIntervalSinceNow: 60))
        XCTAssertEqual(recent.count, 1)
    }

    func testMigrationsIncludeSyncTables() throws {
        let db = try AppDatabase.makeInMemory()
        let (_, _, dsRepo, auditRepo) = makeRepos(db: db)

        // Both repos should work without error if migrations ran.
        XCTAssertNoThrow(try dsRepo.fetchAll())
        XCTAssertNoThrow(try auditRepo.fetchAll())
    }
}
