import Foundation

public struct SourceDetectionContext {
    public let homeDirectory: URL
    public let projectRoots: [URL]
    public let fileManager: FileManager
    public let claudeCodeRoots: [URL]?
    public let openClawRoots: [URL]?
    public let projectSkillDirectoryNames: [String]

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        projectRoots: [URL] = [],
        fileManager: FileManager = .default,
        claudeCodeRoots: [URL]? = nil,
        openClawRoots: [URL]? = nil,
        projectSkillDirectoryNames: [String] = [".claude/skills", ".openclaw/skills", ".cursor/skills", ".windsurf/skills", "skills", ".skills"]
    ) {
        self.homeDirectory = homeDirectory
        self.projectRoots = projectRoots
        self.fileManager = fileManager
        self.claudeCodeRoots = claudeCodeRoots
        self.openClawRoots = openClawRoots
        self.projectSkillDirectoryNames = projectSkillDirectoryNames
    }
}

public struct SourceScanContext {
    public let fileManager: FileManager
    public let now: Date

    public init(fileManager: FileManager = .default, now: Date = Date()) {
        self.fileManager = fileManager
        self.now = now
    }
}

/// Result of an install or remove operation.
public enum SkillLifecycleResult {
    case success(SkillRecord)
    case removed(skillId: String)
}

/// Error thrown when a lifecycle operation cannot be performed.
public struct SkillLifecycleError: Error {
    public enum Code: Equatable {
        case notSupported
        case permissionDenied
        case sourceNotFound
        case skillNotFound
        case ioFailure
    }

    public let code: Code
    public let message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }
}

public protocol SourceAdapter {
    var type: SkillSourceType { get }

    /// Whether skills from this source type support enable/disable state toggling.
    var supportsEnableDisable: Bool { get }

    /// Whether skills from this source type support install/remove operations.
    var supportsInstallRemove: Bool { get }

    /// Whether skills from this source type support version change (upgrade/downgrade).
    var supportsVersionChange: Bool { get }

    func detectSources(context: SourceDetectionContext) -> [SkillSource]
    func scan(source: SkillSource, context: SourceScanContext) -> SourceScanResult

    /// Install a skill package (directory) into the given source root.
    /// - Parameters:
    ///   - packageURL: Path to a skill directory to be installed.
    ///   - source: The target source to install into.
    ///   - context: Scan context (fileManager, timestamp).
    /// - Returns: The indexed `SkillRecord` for the newly installed skill.
    /// - Throws: `SkillLifecycleError` on failure.
    func install(packageURL: URL, into source: SkillSource, context: SourceScanContext) throws -> SkillRecord

    /// Remove an installed skill from its source root.
    /// - Parameters:
    ///   - skill: The record to remove.
    ///   - context: Scan context (fileManager, timestamp).
    /// - Throws: `SkillLifecycleError` on failure.
    func remove(skill: SkillRecord, context: SourceScanContext) throws

    /// Replace an installed skill with a different version package.
    ///
    /// The default implementation removes the existing skill directory then installs the new package.
    /// Adapters that support atomic replacement may override this.
    ///
    /// - Parameters:
    ///   - skill: The currently installed skill record to replace.
    ///   - newPackageURL: Path to the new version skill directory.
    ///   - source: The source that owns the skill.
    ///   - context: Scan context (fileManager, timestamp).
    /// - Returns: The updated `SkillRecord` reflecting the new version.
    /// - Throws: `SkillLifecycleError` on failure.
    func changeVersion(of skill: SkillRecord, to newPackageURL: URL, in source: SkillSource, context: SourceScanContext) throws -> SkillRecord
}
