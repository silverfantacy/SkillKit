import XCTest
import SourceDiscovery
import TestSupport
@testable import SkillPersistence

final class SkillPersistenceTests: XCTestCase {

    // MARK: - AppDatabase

    func testMigrationsApplyWithoutError() throws {
        XCTAssertNoThrow(try AppDatabase.makeInMemory())
    }

    // MARK: - SourceRepository

    func testSaveAndFetchSource() throws {
        let db = try AppDatabase.makeInMemory()
        let repo = SourceRepository(database: db)

        let source = SkillSource(type: .claudeCode, rootPath: URL(fileURLWithPath: "/tmp/skills"))
        try repo.save(source)

        let fetched = try repo.fetch(id: source.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.id, source.id)
        XCTAssertEqual(fetched?.type, .claudeCode)
    }

    func testFetchActiveSourcesExcludesInactive() throws {
        let db = try AppDatabase.makeInMemory()
        let repo = SourceRepository(database: db)

        let s1 = SkillSource(type: .claudeCode, rootPath: URL(fileURLWithPath: "/tmp/a"))
        let s2 = SkillSource(type: .project, rootPath: URL(fileURLWithPath: "/tmp/b"))
        try repo.save(s1, isActive: true)
        try repo.save(s2, isActive: false)

        let active = try repo.fetchActive()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.id, s1.id)
    }

    func testUpdateScanResult() throws {
        let db = try AppDatabase.makeInMemory()
        let repo = SourceRepository(database: db)

        let source = SkillSource(type: .project, rootPath: URL(fileURLWithPath: "/tmp/proj"))
        try repo.save(source)

        let scanResult = SourceScanResult(
            source: source,
            skills: [],
            errors: [SourceScanError(code: .rootNotFound, message: "not found")],
            scannedAt: Date()
        )
        try repo.updateScanResult(sourceId: source.id, result: scanResult)

        // A failure result should deactivate the source.
        let active = try repo.fetchActive()
        XCTAssertTrue(active.isEmpty)
    }

    func testUpdateScanResultReactivatesSourceAfterSuccessfulRetry() throws {
        let db = try AppDatabase.makeInMemory()
        let repo = SourceRepository(database: db)

        let source = SkillSource(type: .project, rootPath: URL(fileURLWithPath: "/tmp/retry"))
        try repo.save(source)

        let failureResult = SourceScanResult(
            source: source,
            skills: [],
            errors: [SourceScanError(code: .ioFailure, message: "scan failed")],
            scannedAt: Date()
        )
        try repo.updateScanResult(sourceId: source.id, result: failureResult)

        var persisted = try repo.fetchPersistedAll().first { $0.id == source.id }
        XCTAssertEqual(persisted?.lastScanStatus, SourceScanStatus.failure.rawValue)
        XCTAssertEqual(persisted?.lastScanError, "scan failed")
        XCTAssertTrue(try repo.fetchActive().isEmpty)

        let successResult = SourceScanResult(
            source: source,
            skills: [SkillRecord(name: "retry-ok", version: "1.0.0", path: URL(fileURLWithPath: "/tmp/retry/retry-ok"), source: source)],
            errors: [],
            scannedAt: Date()
        )
        try repo.updateScanResult(sourceId: source.id, result: successResult)

        persisted = try repo.fetchPersistedAll().first { $0.id == source.id }
        XCTAssertEqual(persisted?.lastScanStatus, SourceScanStatus.success.rawValue)
        XCTAssertNil(persisted?.lastScanError)

        let active = try repo.fetchActive()
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.id, source.id)
    }

    func testDeleteSource() throws {
        let db = try AppDatabase.makeInMemory()
        let repo = SourceRepository(database: db)

        let source = SkillSource(type: .project, rootPath: URL(fileURLWithPath: "/tmp/del"))
        try repo.save(source)
        try repo.delete(sourceId: source.id)

        let fetched = try repo.fetch(id: source.id)
        XCTAssertNil(fetched)
    }

    func testExistsReturnsFalseForUnknownId() throws {
        let db = try AppDatabase.makeInMemory()
        let repo = SourceRepository(database: db)
        XCTAssertFalse(try repo.exists(id: "no-such-id"))
    }

    // MARK: - SkillRepository

    func testSaveAndFetchSkill() throws {
        let db = try AppDatabase.makeInMemory()
        let sourceRepo = SourceRepository(database: db)
        let skillRepo = SkillRepository(database: db)

        let source = SkillSource(type: .project, rootPath: URL(fileURLWithPath: "/tmp/s"))
        try sourceRepo.save(source)

        let record = SkillRecord(
            name: "my-skill",
            version: "1.0.0",
            path: URL(fileURLWithPath: "/tmp/s/my-skill"),
            source: source
        )
        try skillRepo.save(record)

        let fetched = try skillRepo.fetch(id: record.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.name, "my-skill")
        XCTAssertEqual(fetched?.version, "1.0.0")
    }

    func testReplaceAllRemovesOldSkills() throws {
        let db = try AppDatabase.makeInMemory()
        let sourceRepo = SourceRepository(database: db)
        let skillRepo = SkillRepository(database: db)

        let source = SkillSource(type: .project, rootPath: URL(fileURLWithPath: "/tmp/s2"))
        try sourceRepo.save(source)

        let old = SkillRecord(name: "old-skill", version: nil, path: URL(fileURLWithPath: "/tmp/s2/old"), source: source)
        try skillRepo.save(old)

        let new = SkillRecord(name: "new-skill", version: "2.0", path: URL(fileURLWithPath: "/tmp/s2/new"), source: source)
        try skillRepo.replaceAll(for: source.id, with: [new])

        let all = try skillRepo.fetch(sourceId: source.id)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.name, "new-skill")
    }

    func testDeleteSkill() throws {
        let db = try AppDatabase.makeInMemory()
        let sourceRepo = SourceRepository(database: db)
        let skillRepo = SkillRepository(database: db)

        let source = SkillSource(type: .project, rootPath: URL(fileURLWithPath: "/tmp/s3"))
        try sourceRepo.save(source)

        let record = SkillRecord(name: "to-delete", version: nil, path: URL(fileURLWithPath: "/tmp/s3/skill"), source: source)
        try skillRepo.save(record)
        try skillRepo.delete(skillId: record.id)

        XCTAssertNil(try skillRepo.fetch(id: record.id))
    }

    func testQueryFiltersByName() throws {
        let db = try AppDatabase.makeInMemory()
        let sourceRepo = SourceRepository(database: db)
        let skillRepo = SkillRepository(database: db)

        let source = SkillSource(type: .project, rootPath: URL(fileURLWithPath: "/tmp/s4"))
        try sourceRepo.save(source)

        for name in ["alpha", "beta", "alpha-two"] {
            let r = SkillRecord(name: name, version: nil, path: URL(fileURLWithPath: "/tmp/s4/\(name)"), source: source)
            try skillRepo.save(r)
        }

        let results = try skillRepo.query(nameContains: "alpha")
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.name.contains("alpha") })
    }

    // MARK: - InventoryPersistenceService

    func testApplyScanResultPersistsSkills() throws {
        let db = try AppDatabase.makeInMemory()
        let service = InventoryPersistenceService(
            sourceRepository: SourceRepository(database: db),
            skillRepository: SkillRepository(database: db)
        )

        let source = SkillSource(type: .project, rootPath: URL(fileURLWithPath: "/tmp/scan"))
        let skills = [
            SkillRecord(name: "skill-a", version: "1.0", path: URL(fileURLWithPath: "/tmp/scan/skill-a"), source: source),
            SkillRecord(name: "skill-b", version: "2.0", path: URL(fileURLWithPath: "/tmp/scan/skill-b"), source: source)
        ]
        let scanResult = SourceScanResult(source: source, skills: skills, errors: [], scannedAt: Date())

        try service.apply(scanResult: scanResult)

        let skillRepo = SkillRepository(database: db)
        let stored = try skillRepo.fetch(sourceId: source.id)
        XCTAssertEqual(stored.count, 2)
    }

    func testApplyIncrementalResultsAddsAndRemoves() throws {
        let db = try AppDatabase.makeInMemory()
        let sourceRepo = SourceRepository(database: db)
        let skillRepo = SkillRepository(database: db)
        let service = InventoryPersistenceService(
            sourceRepository: sourceRepo,
            skillRepository: skillRepo
        )

        let source = SkillSource(type: .project, rootPath: URL(fileURLWithPath: "/tmp/inc"))
        try sourceRepo.save(source)

        let existingSkillPath = URL(fileURLWithPath: "/tmp/inc/existing")
        let existing = SkillRecord(name: "existing", version: nil, path: existingSkillPath, source: source)
        try skillRepo.save(existing)

        let newPath = URL(fileURLWithPath: "/tmp/inc/new-skill")
        let newRecord = SkillRecord(name: "new-skill", version: "1.0", path: newPath, source: source)

        let incremental: [IncrementalUpdateResult] = [
            IncrementalUpdateResult(source: source, skillPath: newPath, change: .added(newRecord), scannedAt: Date()),
            IncrementalUpdateResult(source: source, skillPath: existingSkillPath, change: .removed(skillId: existing.id), scannedAt: Date())
        ]
        try service.apply(incrementalResults: incremental)

        XCTAssertNil(try skillRepo.fetch(id: existing.id))
        XCTAssertNotNil(try skillRepo.fetch(id: newRecord.id))
    }

    // MARK: - Enable/Disable Skills (Task 4.1)

    func testSetEnabledUpdatesSkillState() throws {
        let db = try AppDatabase.makeInMemory()
        let sourceRepo = SourceRepository(database: db)
        let skillRepo = SkillRepository(database: db)

        let source = SkillSource(type: .claudeCode, rootPath: URL(fileURLWithPath: "/tmp/en"))
        try sourceRepo.save(source)

        let record = SkillRecord(name: "toggle-skill", version: nil, path: URL(fileURLWithPath: "/tmp/en/toggle-skill"), source: source)
        try skillRepo.save(record, isEnabled: true)

        let updated = try skillRepo.setEnabled(skillId: record.id, isEnabled: false)
        XCTAssertTrue(updated)
        XCTAssertEqual(try skillRepo.fetch(id: record.id)?.isEnabled, false)

        try skillRepo.setEnabled(skillId: record.id, isEnabled: true)
        XCTAssertEqual(try skillRepo.fetch(id: record.id)?.isEnabled, true)
    }

    func testSetEnabledReturnsFalseForMissingSkill() throws {
        let db = try AppDatabase.makeInMemory()
        let skillRepo = SkillRepository(database: db)
        let updated = try skillRepo.setEnabled(skillId: "no-such-skill", isEnabled: false)
        XCTAssertFalse(updated)
    }

    func testInventoryServiceEnablesSupportedSourceType() throws {
        let db = try AppDatabase.makeInMemory()
        let sourceRepo = SourceRepository(database: db)
        let skillRepo = SkillRepository(database: db)
        let service = InventoryPersistenceService(sourceRepository: sourceRepo, skillRepository: skillRepo)

        let source = SkillSource(type: .project, rootPath: URL(fileURLWithPath: "/tmp/proj-en"))
        try sourceRepo.save(source)

        let record = SkillRecord(name: "proj-skill", version: nil, path: URL(fileURLWithPath: "/tmp/proj-en/proj-skill"), source: source)
        try skillRepo.save(record, isEnabled: true)

        XCTAssertNoThrow(try service.setSkillEnabled(skillId: record.id, isEnabled: false))
        XCTAssertEqual(try skillRepo.fetch(id: record.id)?.isEnabled, false)
    }

    func testInventoryServiceBlocksUnsupportedSourceType() throws {
        let db = try AppDatabase.makeInMemory()
        let sourceRepo = SourceRepository(database: db)
        let skillRepo = SkillRepository(database: db)
        let service = InventoryPersistenceService(sourceRepository: sourceRepo, skillRepository: skillRepo)

        let source = SkillSource(type: .openClaw, rootPath: URL(fileURLWithPath: "/tmp/oc-en"))
        try sourceRepo.save(source)

        let record = SkillRecord(name: "oc-skill", version: nil, path: URL(fileURLWithPath: "/tmp/oc-en/oc-skill"), source: source)
        try skillRepo.save(record, isEnabled: true)

        XCTAssertThrowsError(try service.setSkillEnabled(skillId: record.id, isEnabled: false)) { error in
            XCTAssertTrue(error is InventoryPersistenceService.EnableDisableNotSupported)
        }
        // Skill remains enabled after blocked attempt.
        XCTAssertEqual(try skillRepo.fetch(id: record.id)?.isEnabled, true)
    }

    func testRegisterSourceIsIdempotent() throws {
        let db = try AppDatabase.makeInMemory()
        let service = InventoryPersistenceService(
            sourceRepository: SourceRepository(database: db),
            skillRepository: SkillRepository(database: db)
        )

        let source = SkillSource(type: .claudeCode, rootPath: URL(fileURLWithPath: "/tmp/cc"))
        XCTAssertNoThrow(try service.registerSource(source))
        XCTAssertNoThrow(try service.registerSource(source))

        let all = try SourceRepository(database: db).fetchAll()
        XCTAssertEqual(all.count, 1)
    }

    // MARK: - Install/Remove Skills (Task 4.2)

    func testInstallSkillPersistsRecord() throws {
        let db = try AppDatabase.makeInMemory()
        let sourceRepo = SourceRepository(database: db)
        let skillRepo = SkillRepository(database: db)
        let service = InventoryPersistenceService(sourceRepository: sourceRepo, skillRepository: skillRepo)

        // Set up real temp dir so the adapter can actually copy files.
        let tmp = try TemporaryDirectory(prefix: "install-test")
        let sourceRoot = try tmp.makeSourceRoot()
        let packageDir = try tmp.makeSkillPackage(name: "Hello Skill", version: "2.0.0", directoryName: "hello-skill")

        let source = SkillSource(type: .project, rootPath: sourceRoot)
        try sourceRepo.save(source)

        let record = try service.installSkill(
            packageURL: packageDir,
            into: source,
            using: ProjectSourceAdapter(),
            context: SourceScanContext()
        )

        XCTAssertEqual(record.name, "Hello Skill")
        XCTAssertEqual(record.version, "2.0.0")
        let stored = try skillRepo.fetch(id: record.id)
        XCTAssertNotNil(stored)
        XCTAssertEqual(stored?.name, "Hello Skill")
    }

    func testRemoveSkillDeletesRecordAndFiles() throws {
        let db = try AppDatabase.makeInMemory()
        let sourceRepo = SourceRepository(database: db)
        let skillRepo = SkillRepository(database: db)
        let service = InventoryPersistenceService(sourceRepository: sourceRepo, skillRepository: skillRepo)

        let tmp = try TemporaryDirectory(prefix: "remove-test")
        let sourceRoot = try tmp.makeSourceRoot()
        let skillDir = sourceRoot.appendingPathComponent("bye-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)

        let source = SkillSource(type: .project, rootPath: sourceRoot)
        try sourceRepo.save(source)
        let record = SkillRecord(name: "bye-skill", version: nil, path: skillDir, source: source)
        try skillRepo.save(record)

        try service.removeSkill(skillId: record.id, using: ProjectSourceAdapter(), context: SourceScanContext())

        XCTAssertNil(try skillRepo.fetch(id: record.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: skillDir.path))
    }

    func testInstallSkillBlocksUnsupportedSourceType() throws {
        let db = try AppDatabase.makeInMemory()
        let service = InventoryPersistenceService(
            sourceRepository: SourceRepository(database: db),
            skillRepository: SkillRepository(database: db)
        )

        let source = SkillSource(type: .openClaw, rootPath: URL(fileURLWithPath: "/tmp/oc"))
        let packageDir = URL(fileURLWithPath: "/tmp/pkg")
        XCTAssertThrowsError(
            try service.installSkill(packageURL: packageDir, into: source, using: OpenClawSourceAdapter())
        ) { error in
            XCTAssertTrue(error is InventoryPersistenceService.InstallRemoveNotSupported)
        }
    }

    func testRemoveSkillIsNoOpForUnknownId() throws {
        let db = try AppDatabase.makeInMemory()
        let service = InventoryPersistenceService(
            sourceRepository: SourceRepository(database: db),
            skillRepository: SkillRepository(database: db)
        )
        XCTAssertNoThrow(try service.removeSkill(skillId: "no-such-id", using: ProjectSourceAdapter()))
    }

    // MARK: - Version change (Task 4.3)

    func testChangeSkillVersionUpdatesRecord() throws {
        let db = try AppDatabase.makeInMemory()
        let sourceRepo = SourceRepository(database: db)
        let skillRepo = SkillRepository(database: db)
        let service = InventoryPersistenceService(sourceRepository: sourceRepo, skillRepository: skillRepo)

        let tmp = try TemporaryDirectory(prefix: "ver-test")
        let sourceRoot = try tmp.makeSourceRoot()

        // v1 package.
        let v1Dir = try tmp.makeSkillPackage(name: "My Skill", version: "1.0.0", directoryName: "my-skill-v1")

        let source = SkillSource(type: .project, rootPath: sourceRoot)
        try sourceRepo.save(source)

        // Install v1 via service.
        let v1 = try service.installSkill(packageURL: v1Dir, into: source, using: ProjectSourceAdapter(), context: SourceScanContext())
        XCTAssertEqual(v1.version, "1.0.0")

        // v2 package.
        let v2Dir = try tmp.makeSkillPackage(name: "My Skill", version: "2.0.0", directoryName: "my-skill-v2")

        // Change to v2.
        let v2 = try service.changeSkillVersion(skillId: v1.id, to: v2Dir, using: ProjectSourceAdapter(), context: SourceScanContext())
        XCTAssertEqual(v2.version, "2.0.0")

        // Old record gone, new record present.
        XCTAssertNil(try skillRepo.fetch(id: v1.id))
        XCTAssertNotNil(try skillRepo.fetch(id: v2.id))
    }

    func testChangeSkillVersionThrowsForUnsupportedSourceType() throws {
        let db = try AppDatabase.makeInMemory()
        let sourceRepo = SourceRepository(database: db)
        let skillRepo = SkillRepository(database: db)
        let service = InventoryPersistenceService(sourceRepository: sourceRepo, skillRepository: skillRepo)

        let source = SkillSource(type: .openClaw, rootPath: URL(fileURLWithPath: "/tmp/oc"))
        try sourceRepo.save(source)
        let record = SkillRecord(name: "oc-skill", version: "1.0", path: URL(fileURLWithPath: "/tmp/oc/oc-skill"), source: source)
        try skillRepo.save(record)

        XCTAssertThrowsError(
            try service.changeSkillVersion(skillId: record.id, to: URL(fileURLWithPath: "/tmp/v2"), using: OpenClawSourceAdapter())
        ) { error in
            XCTAssertTrue(error is InventoryPersistenceService.VersionChangeNotSupported)
        }
    }

    func testChangeSkillVersionThrowsForUnknownSkillId() throws {
        let db = try AppDatabase.makeInMemory()
        let service = InventoryPersistenceService(
            sourceRepository: SourceRepository(database: db),
            skillRepository: SkillRepository(database: db)
        )
        XCTAssertThrowsError(
            try service.changeSkillVersion(skillId: "no-such-id", to: URL(fileURLWithPath: "/tmp/v2"), using: ProjectSourceAdapter())
        ) { error in
            guard let e = error as? SkillLifecycleError else { return XCTFail("wrong error type") }
            XCTAssertEqual(e.code, .skillNotFound)
        }
    }

    // MARK: - Permission checks (Task 4.4)

    func testInstallBlockedWhenSourceRootMissing() throws {
        let db = try AppDatabase.makeInMemory()
        let service = InventoryPersistenceService(
            sourceRepository: SourceRepository(database: db),
            skillRepository: SkillRepository(database: db)
        )
        let missingRoot = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString)")
        let source = SkillSource(type: .project, rootPath: missingRoot)
        XCTAssertThrowsError(
            try service.installSkill(packageURL: URL(fileURLWithPath: "/tmp/pkg"), into: source, using: ProjectSourceAdapter())
        ) { error in
            guard let e = error as? SkillLifecycleError else { return XCTFail("wrong error type") }
            // Missing root → .sourceNotFound from PermissionChecker.requireWritableSourceRoot
            XCTAssertEqual(e.code, .sourceNotFound)
        }
    }

    func testRemoveBlockedWhenSkillPathMissing() throws {
        let db = try AppDatabase.makeInMemory()
        let sourceRepo = SourceRepository(database: db)
        let skillRepo = SkillRepository(database: db)
        let service = InventoryPersistenceService(sourceRepository: sourceRepo, skillRepository: skillRepo)

        let source = SkillSource(type: .project, rootPath: URL(fileURLWithPath: "/tmp/skills"))
        try sourceRepo.save(source)
        let ghostPath = URL(fileURLWithPath: "/tmp/skills/ghost-skill-\(UUID().uuidString)")
        let record = SkillRecord(name: "ghost", version: nil, path: ghostPath, source: source)
        try skillRepo.save(record)

        XCTAssertThrowsError(
            try service.removeSkill(skillId: record.id, using: ProjectSourceAdapter())
        ) { error in
            guard let e = error as? SkillLifecycleError else { return XCTFail("wrong error type") }
            XCTAssertEqual(e.code, .skillNotFound)
        }
    }
}
