import Foundation

/// Validates file-system permissions before lifecycle operations are applied.
///
/// All lifecycle operations (install, remove, changeVersion) go through
/// `PermissionChecker` before touching the file system.  If the required
/// access is absent the check throws a `SkillLifecycleError` with code
/// `.permissionDenied` and a message that names the missing permission
/// and the path that requires it.
public enum PermissionChecker {

    /// Verify that the given path is writable.
    ///
    /// - Parameters:
    ///   - path: The path that the operation needs to write to.
    ///   - fileManager: Injected `FileManager` (defaults to `.default`).
    ///   - operationName: Human-readable label used in the error message.
    /// - Throws: `SkillLifecycleError(.permissionDenied)` when the path is not writable.
    public static func requireWritable(
        _ path: URL,
        fileManager: FileManager = .default,
        for operationName: String = "lifecycle operation"
    ) throws {
        guard fileManager.isWritableFile(atPath: path.path) else {
            throw SkillLifecycleError(
                code: .permissionDenied,
                message: "'\(operationName)' requires write access to '\(path.path)'. " +
                         "Grant write permission and try again."
            )
        }
    }

    /// Verify that the given path exists and is readable.
    ///
    /// - Parameters:
    ///   - path: The path that must exist and be readable.
    ///   - fileManager: Injected `FileManager` (defaults to `.default`).
    ///   - operationName: Human-readable label used in the error message.
    /// - Throws: `SkillLifecycleError(.permissionDenied)` when the path is not readable.
    public static func requireReadable(
        _ path: URL,
        fileManager: FileManager = .default,
        for operationName: String = "lifecycle operation"
    ) throws {
        guard fileManager.isReadableFile(atPath: path.path) else {
            throw SkillLifecycleError(
                code: .permissionDenied,
                message: "'\(operationName)' requires read access to '\(path.path)'. " +
                         "Grant read permission and try again."
            )
        }
    }

    /// Verify that the source root exists and is writable before an install or version-change.
    ///
    /// - Parameters:
    ///   - source: The target `SkillSource` whose `rootPath` must be writable.
    ///   - fileManager: Injected `FileManager`.
    ///   - operationName: Human-readable label used in the error message.
    /// - Throws: `SkillLifecycleError(.sourceNotFound)` when the root is absent;
    ///           `SkillLifecycleError(.permissionDenied)` when write access is missing.
    public static func requireWritableSourceRoot(
        _ source: SkillSource,
        fileManager: FileManager = .default,
        for operationName: String = "lifecycle operation"
    ) throws {
        guard fileManager.fileExists(atPath: source.rootPath.path) else {
            throw SkillLifecycleError(
                code: .sourceNotFound,
                message: "Source root does not exist: '\(source.rootPath.path)'."
            )
        }
        try requireWritable(source.rootPath, fileManager: fileManager, for: operationName)
    }

    /// Verify that the parent directory of a skill path is writable (needed for remove / replace).
    ///
    /// - Parameters:
    ///   - skillPath: Path to the skill directory being removed or replaced.
    ///   - fileManager: Injected `FileManager`.
    ///   - operationName: Human-readable label used in the error message.
    /// - Throws: `SkillLifecycleError(.permissionDenied)` when write access is missing.
    public static func requireWritableParent(
        of skillPath: URL,
        fileManager: FileManager = .default,
        for operationName: String = "lifecycle operation"
    ) throws {
        let parent = skillPath.deletingLastPathComponent()
        try requireWritable(parent, fileManager: fileManager, for: operationName)
    }
}
