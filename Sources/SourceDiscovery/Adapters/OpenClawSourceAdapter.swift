import Foundation

public struct OpenClawSourceAdapter: SourceAdapter {
    public let type: SkillSourceType = .openClaw
    public let supportsEnableDisable: Bool = false
    public let supportsInstallRemove: Bool = false
    public let supportsVersionChange: Bool = false
    private let scanner: SkillScanner

    public init(scanner: SkillScanner = SkillScanner()) {
        self.scanner = scanner
    }

    public func detectSources(context: SourceDetectionContext) -> [SkillSource] {
        let roots = context.openClawRoots ?? Self.defaultRoots(homeDirectory: context.homeDirectory)
        return roots.compactMap { root in
            guard isValidRoot(root, fileManager: context.fileManager) else { return nil }
            return SkillSource(type: .openClaw, rootPath: root, origin: .discovered)
        }
    }

    public func scan(source: SkillSource, context: SourceScanContext) -> SourceScanResult {
        scanner.scan(source: source, context: context)
    }

    public func install(packageURL: URL, into source: SkillSource, context: SourceScanContext) throws -> SkillRecord {
        throw SkillLifecycleError(code: .notSupported, message: "OpenClaw source does not support skill installation.")
    }

    public func remove(skill: SkillRecord, context: SourceScanContext) throws {
        throw SkillLifecycleError(code: .notSupported, message: "OpenClaw source does not support skill removal.")
    }

    public func changeVersion(of skill: SkillRecord, to newPackageURL: URL, in source: SkillSource, context: SourceScanContext) throws -> SkillRecord {
        throw SkillLifecycleError(code: .notSupported, message: "OpenClaw source does not support version changes.")
    }

    public static func defaultRoots(homeDirectory: URL) -> [URL] {
        [
            homeDirectory.appendingPathComponent(".openclaw/skills"),
            homeDirectory.appendingPathComponent("Library/Application Support/OpenClaw/skills")
        ]
    }

    private func isValidRoot(_ root: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue && fileManager.isReadableFile(atPath: root.path)
    }
}
