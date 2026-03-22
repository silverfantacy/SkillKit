import Foundation

public struct ProjectSourceAdapter: SourceAdapter {
    public let type: SkillSourceType = .project
    public let supportsEnableDisable: Bool = true
    public let supportsInstallRemove: Bool = true
    public let supportsVersionChange: Bool = true
    private let scanner: SkillScanner

    public init(scanner: SkillScanner = SkillScanner()) {
        self.scanner = scanner
    }

    public func detectSources(context: SourceDetectionContext) -> [SkillSource] {
        guard !context.projectRoots.isEmpty else { return [] }
        var sources: [SkillSource] = []
        for projectRoot in context.projectRoots {
            for directoryName in context.projectSkillDirectoryNames {
                let root = projectRoot.appendingPathComponent(directoryName)
                guard isValidRoot(root, fileManager: context.fileManager) else { continue }
                let metadata = ["projectRoot": projectRoot.standardizedFileURL.path]
                let displayName = "Workspace (\(projectRoot.lastPathComponent))"
                sources.append(
                    SkillSource(
                        type: .project,
                        rootPath: root,
                        displayName: displayName,
                        origin: .discovered,
                        metadata: metadata
                    )
                )
            }
        }
        return sources
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

    private func isValidRoot(_ root: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue && fileManager.isReadableFile(atPath: root.path)
    }
}
