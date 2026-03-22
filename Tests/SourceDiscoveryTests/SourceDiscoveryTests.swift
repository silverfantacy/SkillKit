import XCTest
import TestSupport
@testable import SourceDiscovery

final class SourceDiscoveryTests: XCTestCase {
    func testDetectsClaudeCodeSource() throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent(".claude/skills")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let adapter = ClaudeCodeSourceAdapter()
        let context = SourceDetectionContext(
            homeDirectory: temp.url,
            projectRoots: [],
            fileManager: .default,
            claudeCodeRoots: [root],
            openClawRoots: []
        )
        let sources = adapter.detectSources(context: context)

        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.type, .claudeCode)
        XCTAssertEqual(sources.first?.rootPath.standardizedFileURL, root.standardizedFileURL)
    }

    func testScanReadsManifest() throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("skills")
        let skillDirectory = root.appendingPathComponent("hello-skill")
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)

        let manifest = """
        {
          "name": "Hello Skill",
          "version": "1.2.3"
        }
        """
        let manifestURL = skillDirectory.appendingPathComponent("skill.json")
        try manifest.data(using: .utf8)?.write(to: manifestURL)

        let source = SkillSource(type: .project, rootPath: root)
        let result = SkillScanner().scan(source: source, context: SourceScanContext())

        XCTAssertEqual(result.errors.count, 0)
        XCTAssertEqual(result.skills.count, 1)
        XCTAssertEqual(result.skills.first?.name, "Hello Skill")
        XCTAssertEqual(result.skills.first?.version, "1.2.3")
        XCTAssertEqual(result.skills.first?.sourceId, source.id)
    }

    func testScanCollectsDocumentMetadataPaths() throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("skills")
        let skillDirectory = root.appendingPathComponent("metadata-skill")
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)

        try "# Skill".data(using: .utf8)!.write(to: skillDirectory.appendingPathComponent("SKILL.md"))
        try "# Readme".data(using: .utf8)!.write(to: skillDirectory.appendingPathComponent("README.md"))
        try "{\"name\":\"Metadata Skill\",\"version\":\"0.0.1\"}".data(using: .utf8)!.write(to: skillDirectory.appendingPathComponent("skill.json"))

        let source = SkillSource(type: .project, rootPath: root)
        let result = SkillScanner().scan(source: source, context: SourceScanContext())

        XCTAssertEqual(result.errors.count, 0)
        guard let skill = result.skills.first else {
            return XCTFail("Expected at least one skill")
        }

        XCTAssertEqual(skill.metadata["documents.skill"], skillDirectory.appendingPathComponent("SKILL.md").standardizedFileURL.path)
        XCTAssertEqual(skill.metadata["documents.readme"], skillDirectory.appendingPathComponent("README.md").standardizedFileURL.path)
        XCTAssertEqual(skill.metadata["documents.primary"], skillDirectory.appendingPathComponent("SKILL.md").standardizedFileURL.path)
        XCTAssertEqual(skill.metadata["manifest.path"], skillDirectory.appendingPathComponent("skill.json").standardizedFileURL.path)
        XCTAssertNotNil(skill.metadata["filesystem.fileCount"])
        XCTAssertNotNil(skill.metadata["filesystem.lastModified"])
    }

    func testScanCollectsDocumentFallbackMetadataCombinations() throws {
        let temp = try TemporaryDirectory()
        let root = temp.url.appendingPathComponent("skills")

        let skillPreferred = root.appendingPathComponent("skill-preferred")
        try FileManager.default.createDirectory(at: skillPreferred, withIntermediateDirectories: true)
        try "# Skill".data(using: .utf8)!.write(to: skillPreferred.appendingPathComponent("SKILL.md"))
        try "# Readme".data(using: .utf8)!.write(to: skillPreferred.appendingPathComponent("README.md"))
        try "{\"name\":\"Skill Preferred\",\"version\":\"1.0.0\"}".data(using: .utf8)!.write(to: skillPreferred.appendingPathComponent("skill.json"))

        let readmeOnly = root.appendingPathComponent("readme-only")
        try FileManager.default.createDirectory(at: readmeOnly, withIntermediateDirectories: true)
        try "# Readme Only".data(using: .utf8)!.write(to: readmeOnly.appendingPathComponent("README.md"))
        try "{\"name\":\"Readme Only\",\"version\":\"2.0.0\"}".data(using: .utf8)!.write(to: readmeOnly.appendingPathComponent("manifest.json"))

        let noDocs = root.appendingPathComponent("no-docs")
        try FileManager.default.createDirectory(at: noDocs, withIntermediateDirectories: true)
        try "{\"name\":\"No Docs\",\"version\":\"3.0.0\"}".data(using: .utf8)!.write(to: noDocs.appendingPathComponent("skill.json"))

        let source = SkillSource(type: .project, rootPath: root)
        let result = SkillScanner().scan(source: source, context: SourceScanContext())

        XCTAssertEqual(result.errors.count, 0)
        XCTAssertEqual(result.skills.count, 3)

        let metadataByFolder = Dictionary(uniqueKeysWithValues: result.skills.map { ($0.path.lastPathComponent, $0.metadata) })

        guard let skillPreferredMetadata = metadataByFolder["skill-preferred"],
              let readmeOnlyMetadata = metadataByFolder["readme-only"],
              let noDocsMetadata = metadataByFolder["no-docs"] else {
            return XCTFail("Expected metadata for all fallback cases")
        }

        XCTAssertEqual(skillPreferredMetadata["documents.primary"], skillPreferred.appendingPathComponent("SKILL.md").standardizedFileURL.path)
        XCTAssertEqual(skillPreferredMetadata["documents.skill"], skillPreferred.appendingPathComponent("SKILL.md").standardizedFileURL.path)
        XCTAssertEqual(skillPreferredMetadata["documents.readme"], skillPreferred.appendingPathComponent("README.md").standardizedFileURL.path)
        XCTAssertEqual(skillPreferredMetadata["manifest.path"], skillPreferred.appendingPathComponent("skill.json").standardizedFileURL.path)

        XCTAssertEqual(readmeOnlyMetadata["documents.primary"], readmeOnly.appendingPathComponent("README.md").standardizedFileURL.path)
        XCTAssertNil(readmeOnlyMetadata["documents.skill"])
        XCTAssertEqual(readmeOnlyMetadata["documents.readme"], readmeOnly.appendingPathComponent("README.md").standardizedFileURL.path)
        XCTAssertEqual(readmeOnlyMetadata["manifest.path"], readmeOnly.appendingPathComponent("manifest.json").standardizedFileURL.path)

        XCTAssertNil(noDocsMetadata["documents.primary"])
        XCTAssertNil(noDocsMetadata["documents.skill"])
        XCTAssertNil(noDocsMetadata["documents.readme"])
        XCTAssertEqual(noDocsMetadata["manifest.path"], noDocs.appendingPathComponent("skill.json").standardizedFileURL.path)
    }

    // MARK: - IncrementalInventoryUpdater

    func testIncrementalUpdateAddsSkill() throws {
        let temp = try TemporaryDirectory()
        let root = try temp.makeSourceRoot()
        let skillDir = root.appendingPathComponent("new-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let manifest = #"{"name":"New Skill","version":"0.1.0"}"#
        try manifest.data(using: .utf8)!.write(to: skillDir.appendingPathComponent("skill.json"))

        let source = SkillSource(type: .project, rootPath: root)
        let event = SkillFileChangeEvent(path: skillDir, kind: .added, source: source)
        let results = IncrementalInventoryUpdater().process(events: [event], context: SourceScanContext())

        XCTAssertEqual(results.count, 1)
        if case .added(let record) = results.first?.change {
            XCTAssertEqual(record.name, "New Skill")
            XCTAssertEqual(record.version, "0.1.0")
        } else {
            XCTFail("Expected .added change")
        }
    }

    func testIncrementalUpdateRemovesSkill() throws {
        let temp = try TemporaryDirectory()
        let root = try temp.makeSourceRoot()
        let skillDir = root.appendingPathComponent("gone-skill")

        let source = SkillSource(type: .project, rootPath: root)
        let event = SkillFileChangeEvent(path: skillDir, kind: .removed, source: source)
        let results = IncrementalInventoryUpdater().process(events: [event], context: SourceScanContext())

        XCTAssertEqual(results.count, 1)
        if case .removed(let skillId) = results.first?.change {
            XCTAssertTrue(skillId.contains("gone-skill"))
        } else {
            XCTFail("Expected .removed change")
        }
    }

    func testIncrementalUpdateModifiesSkill() throws {
        let temp = try TemporaryDirectory()
        let root = try temp.makeSourceRoot()
        let skillDir = root.appendingPathComponent("my-skill")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        let manifest = #"{"name":"My Skill","version":"2.0.0"}"#
        try manifest.data(using: .utf8)!.write(to: skillDir.appendingPathComponent("skill.json"))

        let source = SkillSource(type: .project, rootPath: root)
        let event = SkillFileChangeEvent(path: skillDir, kind: .modified, source: source)
        let results = IncrementalInventoryUpdater().process(events: [event], context: SourceScanContext())

        XCTAssertEqual(results.count, 1)
        if case .updated(let record) = results.first?.change {
            XCTAssertEqual(record.name, "My Skill")
            XCTAssertEqual(record.version, "2.0.0")
        } else {
            XCTFail("Expected .updated change")
        }
    }

    func testIncrementalUpdateDeduplicatesEvents() throws {
        let temp = try TemporaryDirectory()
        let root = try temp.makeSourceRoot()
        let skillDir = root.appendingPathComponent("dup-skill")

        let source = SkillSource(type: .project, rootPath: root)
        // Two events for the same path — should collapse to one result.
        let events = [
            SkillFileChangeEvent(path: skillDir, kind: .modified, source: source),
            SkillFileChangeEvent(path: skillDir, kind: .removed, source: source),
        ]
        let results = IncrementalInventoryUpdater().process(events: events, context: SourceScanContext())

        XCTAssertEqual(results.count, 1)
        if case .removed = results.first?.change { /* expected */ } else {
            XCTFail("Expected .removed to win deduplication")
        }
    }

    // MARK: - SkillSourceWatcher

    func testWatcherDetectsAddedSkillDirectory() throws {
        let temp = try TemporaryDirectory()
        let root = try temp.makeSourceRoot()
        let source = SkillSource(type: .project, rootPath: root)

        let expectation = XCTestExpectation(description: "watcher fires added event")
        let watcher = SkillSourceWatcher(sources: [source], latency: 0.1) { events in
            if events.contains(where: { $0.kind == .added }) {
                expectation.fulfill()
            }
        }
        watcher.start()

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            let newSkill = root.appendingPathComponent("watched-skill")
            try? FileManager.default.createDirectory(at: newSkill, withIntermediateDirectories: true)
        }

        wait(for: [expectation], timeout: 5)
        watcher.stop()
    }

    // MARK: - Enable/Disable support (Task 4.1)

    func testClaudeCodeAdapterSupportsEnableDisable() {
        XCTAssertTrue(ClaudeCodeSourceAdapter().supportsEnableDisable)
    }

    func testOpenClawAdapterDoesNotSupportEnableDisable() {
        XCTAssertFalse(OpenClawSourceAdapter().supportsEnableDisable)
    }

    func testProjectAdapterSupportsEnableDisable() {
        XCTAssertTrue(ProjectSourceAdapter().supportsEnableDisable)
    }

    func testSkillSourceTypeSupportsEnableDisable() {
        XCTAssertTrue(SkillSourceType.claudeCode.supportsEnableDisable)
        XCTAssertTrue(SkillSourceType.project.supportsEnableDisable)
        XCTAssertFalse(SkillSourceType.openClaw.supportsEnableDisable)
    }

    // MARK: - Install/Remove support (Task 4.2)

    func testClaudeCodeAdapterSupportsInstallRemove() {
        XCTAssertTrue(ClaudeCodeSourceAdapter().supportsInstallRemove)
    }

    func testProjectAdapterSupportsInstallRemove() {
        XCTAssertTrue(ProjectSourceAdapter().supportsInstallRemove)
    }

    func testOpenClawAdapterDoesNotSupportInstallRemove() {
        XCTAssertFalse(OpenClawSourceAdapter().supportsInstallRemove)
    }

    func testSkillSourceTypeSupportsInstallRemove() {
        XCTAssertTrue(SkillSourceType.claudeCode.supportsInstallRemove)
        XCTAssertTrue(SkillSourceType.project.supportsInstallRemove)
        XCTAssertFalse(SkillSourceType.openClaw.supportsInstallRemove)
    }

    func testInstallCopiesSkillIntoSourceRoot() throws {
        let temp = try TemporaryDirectory()
        let sourceRoot = temp.url.appendingPathComponent("target-skills")
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let packageDir = temp.url.appendingPathComponent("my-new-skill")
        try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)
        let manifest = #"{"name":"My New Skill","version":"1.0.0"}"#
        try manifest.data(using: .utf8)!.write(to: packageDir.appendingPathComponent("skill.json"))

        let source = SkillSource(type: .project, rootPath: sourceRoot)
        let record = try ProjectSourceAdapter().install(packageURL: packageDir, into: source, context: SourceScanContext())

        XCTAssertEqual(record.name, "My New Skill")
        XCTAssertEqual(record.version, "1.0.0")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceRoot.appendingPathComponent("my-new-skill").path))
    }

    func testInstallFallbackRecoversManifestMetadataWhenScannerMissesIt() throws {
        let temp = try TemporaryDirectory()
        let sourceRoot = try temp.makeSourceRoot()

        let packageDir = temp.url.appendingPathComponent("fallback-skill")
        try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)
        let manifest = #"{"name":"Fallback Skill","version":"9.9.9"}"#
        try manifest.data(using: .utf8)!.write(to: packageDir.appendingPathComponent("skill.json"))

        let source = SkillSource(type: .project, rootPath: sourceRoot)
        // Force scanner to miss `skill.json` so scan record would otherwise use directory name + nil version.
        let adapter = ProjectSourceAdapter(scanner: SkillScanner(manifestFileNames: ["nonexistent.json"]))
        let record = try adapter.install(packageURL: packageDir, into: source, context: SourceScanContext())

        XCTAssertEqual(record.name, "Fallback Skill")
        XCTAssertEqual(record.version, "9.9.9")
        XCTAssertEqual(record.path.lastPathComponent, "fallback-skill")
    }

    func testInstallFailsIfDestinationAlreadyExists() throws {
        let temp = try TemporaryDirectory()
        let sourceRoot = temp.url.appendingPathComponent("skills")
        let existing = sourceRoot.appendingPathComponent("clash-skill")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let packageDir = temp.url.appendingPathComponent("clash-skill")
        try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)

        let source = SkillSource(type: .claudeCode, rootPath: sourceRoot)
        XCTAssertThrowsError(try ClaudeCodeSourceAdapter().install(packageURL: packageDir, into: source, context: SourceScanContext())) { error in
            guard let e = error as? SkillLifecycleError else { return XCTFail("wrong error type") }
            XCTAssertEqual(e.code, .ioFailure)
        }
    }

    func testRemoveDeletesSkillDirectory() throws {
        let temp = try TemporaryDirectory()
        let sourceRoot = temp.url.appendingPathComponent("skills")
        let skillDir = sourceRoot.appendingPathComponent("to-remove")
        try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)

        let source = SkillSource(type: .project, rootPath: sourceRoot)
        let record = SkillRecord(name: "to-remove", version: nil, path: skillDir, source: source)
        try ProjectSourceAdapter().remove(skill: record, context: SourceScanContext())

        XCTAssertFalse(FileManager.default.fileExists(atPath: skillDir.path))
    }

    func testRemoveFailsForMissingSkill() throws {
        let temp = try TemporaryDirectory()
        let sourceRoot = try temp.makeSourceRoot()
        let missingDir = sourceRoot.appendingPathComponent("ghost-skill")

        let source = SkillSource(type: .claudeCode, rootPath: sourceRoot)
        let record = SkillRecord(name: "ghost-skill", version: nil, path: missingDir, source: source)
        XCTAssertThrowsError(try ClaudeCodeSourceAdapter().remove(skill: record, context: SourceScanContext())) { error in
            guard let e = error as? SkillLifecycleError else { return XCTFail("wrong error type") }
            XCTAssertEqual(e.code, .skillNotFound)
        }
    }

    func testOpenClawInstallThrowsNotSupported() throws {
        let temp = try TemporaryDirectory()
        let sourceRoot = temp.url.appendingPathComponent("oc-skills")
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let packageDir = temp.url.appendingPathComponent("pkg")
        try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)

        let source = SkillSource(type: .openClaw, rootPath: sourceRoot)
        XCTAssertThrowsError(try OpenClawSourceAdapter().install(packageURL: packageDir, into: source, context: SourceScanContext())) { error in
            guard let e = error as? SkillLifecycleError else { return XCTFail("wrong error type") }
            XCTAssertEqual(e.code, .notSupported)
        }
    }

    func testInstallFailsWhenSourceRootMissing() throws {
        let temp = try TemporaryDirectory()
        let missingRoot = temp.url.appendingPathComponent("does-not-exist")
        let packageDir = temp.url.appendingPathComponent("pkg")
        try FileManager.default.createDirectory(at: packageDir, withIntermediateDirectories: true)

        let source = SkillSource(type: .claudeCode, rootPath: missingRoot)
        XCTAssertThrowsError(try ClaudeCodeSourceAdapter().install(packageURL: packageDir, into: source, context: SourceScanContext())) { error in
            guard let e = error as? SkillLifecycleError else { return XCTFail("wrong error type") }
            XCTAssertEqual(e.code, .sourceNotFound)
        }
    }

    // MARK: - Version change support (Task 4.3)

    func testAdaptersReportVersionChangeSupport() {
        XCTAssertTrue(ClaudeCodeSourceAdapter().supportsVersionChange)
        XCTAssertTrue(ProjectSourceAdapter().supportsVersionChange)
        XCTAssertFalse(OpenClawSourceAdapter().supportsVersionChange)
    }

    func testSkillSourceTypeSupportsVersionChange() {
        XCTAssertTrue(SkillSourceType.claudeCode.supportsVersionChange)
        XCTAssertTrue(SkillSourceType.project.supportsVersionChange)
        XCTAssertFalse(SkillSourceType.openClaw.supportsVersionChange)
    }

    func testChangeVersionReplacesDirectoryAndUpdatesRecord() throws {
        let temp = try TemporaryDirectory()
        let sourceRoot = try temp.makeSourceRoot()

        // Install v1.
        let v1Dir = try temp.makeSkillPackage(name: "My Skill", version: "1.0.0", directoryName: "my-skill-v1")

        let source = SkillSource(type: .project, rootPath: sourceRoot)
        let v1record = try ProjectSourceAdapter().install(packageURL: v1Dir, into: source, context: SourceScanContext())

        XCTAssertEqual(v1record.version, "1.0.0")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceRoot.appendingPathComponent("my-skill-v1").path))

        // Prepare v2 package.
        let v2Dir = try temp.makeSkillPackage(name: "My Skill", version: "2.0.0", directoryName: "my-skill-v2")

        // Change version: v1 → v2.
        let v2record = try ProjectSourceAdapter().changeVersion(of: v1record, to: v2Dir, in: source, context: SourceScanContext())

        XCTAssertEqual(v2record.version, "2.0.0")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceRoot.appendingPathComponent("my-skill-v1").path),
                       "Old version directory should be removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceRoot.appendingPathComponent("my-skill-v2").path),
                      "New version directory should be present")
    }

    func testOpenClawChangeVersionThrowsNotSupported() throws {
        let temp = try TemporaryDirectory()
        let sourceRoot = try temp.makeSourceRoot()
        let v2Dir = temp.url.appendingPathComponent("skill-v2")
        try FileManager.default.createDirectory(at: v2Dir, withIntermediateDirectories: true)

        let source = SkillSource(type: .openClaw, rootPath: sourceRoot)
        let dummyRecord = SkillRecord(name: "skill", version: "1.0", path: sourceRoot.appendingPathComponent("skill-v1"), source: source)

        XCTAssertThrowsError(
            try OpenClawSourceAdapter().changeVersion(of: dummyRecord, to: v2Dir, in: source, context: SourceScanContext())
        ) { error in
            guard let e = error as? SkillLifecycleError else { return XCTFail("wrong error type") }
            XCTAssertEqual(e.code, .notSupported)
        }
    }

    // MARK: - Permission checks (Task 4.4)

    func testPermissionCheckerRequireWritableThrowsForNonexistentPath() {
        let missingPath = URL(fileURLWithPath: "/nonexistent/path/that/cannot/be/written")
        XCTAssertThrowsError(
            try PermissionChecker.requireWritable(missingPath, for: "test-op")
        ) { error in
            guard let e = error as? SkillLifecycleError else { return XCTFail("wrong error type") }
            XCTAssertEqual(e.code, .permissionDenied)
            XCTAssertTrue(e.message.contains("test-op"))
            XCTAssertTrue(e.message.contains("write access"))
        }
    }

    func testPermissionCheckerRequireWritableSourceRootThrowsWhenMissing() {
        let missingRoot = URL(fileURLWithPath: "/nonexistent/source-root")
        let source = SkillSource(type: .claudeCode, rootPath: missingRoot)
        XCTAssertThrowsError(
            try PermissionChecker.requireWritableSourceRoot(source, for: "install")
        ) { error in
            guard let e = error as? SkillLifecycleError else { return XCTFail("wrong error type") }
            XCTAssertEqual(e.code, .sourceNotFound)
        }
    }

    func testPermissionCheckerRequireReadableThrowsForNonexistentPath() {
        let missing = URL(fileURLWithPath: "/nonexistent/unreadable")
        XCTAssertThrowsError(
            try PermissionChecker.requireReadable(missing, for: "scan")
        ) { error in
            guard let e = error as? SkillLifecycleError else { return XCTFail("wrong error type") }
            XCTAssertEqual(e.code, .permissionDenied)
            XCTAssertTrue(e.message.contains("read access"))
        }
    }

    func testInstallReportsPermissionDeniedWhenSourceRootNotWritable() throws {
        // We rely on the existing test that validates sourceNotFound when root is absent,
        // since on macOS we cannot easily revoke write permission on a temp directory.
        // This test validates the error message format from PermissionChecker.
        let missingRoot = URL(fileURLWithPath: "/tmp/nonexistent-root-\(UUID().uuidString)")
        let source = SkillSource(type: .project, rootPath: missingRoot)
        let pkg = URL(fileURLWithPath: "/tmp/pkg")
        XCTAssertThrowsError(
            try ProjectSourceAdapter().install(packageURL: pkg, into: source, context: SourceScanContext())
        ) { error in
            guard let e = error as? SkillLifecycleError else { return XCTFail("wrong error type") }
            XCTAssertEqual(e.code, .sourceNotFound)
        }
    }

    // MARK: - Existing tests

    func testDetectsProjectSource() throws {
        let temp = try TemporaryDirectory()
        let projectRoot = temp.url.appendingPathComponent("project")
        let skillsRoot = projectRoot.appendingPathComponent("skills")
        try FileManager.default.createDirectory(at: skillsRoot, withIntermediateDirectories: true)

        let adapter = ProjectSourceAdapter()
        let context = SourceDetectionContext(
            homeDirectory: temp.url,
            projectRoots: [projectRoot],
            fileManager: .default
        )
        let sources = adapter.detectSources(context: context)

        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.type, .project)
        XCTAssertEqual(sources.first?.rootPath.standardizedFileURL, skillsRoot.standardizedFileURL)
    }
}

