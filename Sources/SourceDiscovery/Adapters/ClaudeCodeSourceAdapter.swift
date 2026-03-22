import Foundation

public struct ClaudeCodeSourceAdapter: SourceAdapter {
    public let type: SkillSourceType = .claudeCode
    public let supportsEnableDisable: Bool = true
    public let supportsInstallRemove: Bool = true
    public let supportsVersionChange: Bool = true
    private let scanner: SkillScanner

    public init(scanner: SkillScanner = SkillScanner()) {
        self.scanner = scanner
    }

    public func detectSources(context: SourceDetectionContext) -> [SkillSource] {
        let roots = context.claudeCodeRoots ?? Self.defaultRoots(homeDirectory: context.homeDirectory)
        return roots.compactMap { root in
            guard isValidRoot(root, fileManager: context.fileManager) else { return nil }
            return SkillSource(type: .claudeCode, rootPath: root, origin: .discovered)
        }
    }

    public func scan(source: SkillSource, context: SourceScanContext) -> SourceScanResult {
        scanner.scan(source: source, context: context)
    }

    public func install(packageURL: URL, into source: SkillSource, context: SourceScanContext) throws -> SkillRecord {
        try SkillInstaller.install(packageURL: packageURL, into: source, context: context, scanner: scanner)
    }

    public func remove(skill: SkillRecord, context: SourceScanContext) throws {
        try SkillInstaller.remove(skill: skill, context: context)
    }

    public func changeVersion(of skill: SkillRecord, to newPackageURL: URL, in source: SkillSource, context: SourceScanContext) throws -> SkillRecord {
        try SkillInstaller.changeVersion(of: skill, to: newPackageURL, in: source, context: context, scanner: scanner)
    }

    public static func defaultRoots(homeDirectory: URL) -> [URL] {
        [
            homeDirectory.appendingPathComponent(".claude/skills"),
            homeDirectory.appendingPathComponent("Library/Application Support/Claude/skills")
        ]
    }

    private func isValidRoot(_ root: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue && fileManager.isReadableFile(atPath: root.path)
    }
}
