import Foundation

/// Shared helpers for install, remove, and version-change operations used by concrete SourceAdapters.
///
/// All methods validate file-system permissions via `PermissionChecker` before
/// touching the file system; they throw `SkillLifecycleError(.permissionDenied)`
/// with a descriptive message when access is missing.
enum SkillInstaller {

    /// Copy a skill package directory into a source root and return the indexed SkillRecord.
    ///
    /// - Parameters:
    ///   - packageURL: The skill directory to install. Must be a directory.
    ///   - source: The destination source; its `rootPath` must be writable.
    ///   - context: Provides the FileManager and timestamp.
    ///   - scanner: Used to re-scan the destination directory after copy.
    /// - Throws: `SkillLifecycleError` for permission, IO, or source-not-found failures.
    static func install(
        packageURL: URL,
        into source: SkillSource,
        context: SourceScanContext,
        scanner: SkillScanner
    ) throws -> SkillRecord {
        let fm = context.fileManager

        // Permission check: source root must exist and be writable.
        try PermissionChecker.requireWritableSourceRoot(source, fileManager: fm, for: "install")

        // Validate package is a directory.
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: packageURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw SkillLifecycleError(
                code: .skillNotFound,
                message: "Package path is not a directory: \(packageURL.path)"
            )
        }

        let destination = source.rootPath.appendingPathComponent(packageURL.lastPathComponent)

        // Fail if a skill with the same directory name already exists.
        if fm.fileExists(atPath: destination.path) {
            throw SkillLifecycleError(
                code: .ioFailure,
                message: "A skill named '\(packageURL.lastPathComponent)' already exists in this source."
            )
        }

        do {
            try fm.copyItem(at: packageURL, to: destination)
        } catch {
            throw SkillLifecycleError(
                code: .ioFailure,
                message: "Failed to copy skill package: \(error.localizedDescription)"
            )
        }

        // Re-scan the installed directory to produce an accurate SkillRecord.
        let result = scanner.scan(source: source, context: context)
        return resolveInstalledRecord(
            scanResult: result,
            destination: destination,
            source: source,
            fileManager: fm,
            preferredManifestFileNames: scanner.manifestFileNames
        )
    }

    /// Replace an installed skill directory with a new version.
    ///
    /// The operation is: remove existing directory → copy new package → re-scan.
    /// If the copy step fails after removal the old directory is gone; callers should
    /// treat that as a partial failure and prompt the user to re-install manually.
    ///
    /// - Parameters:
    ///   - skill: The currently installed skill whose directory will be replaced.
    ///   - newPackageURL: Path to the replacement skill directory.
    ///   - source: The owning source; its `rootPath` must be writable.
    ///   - context: Provides the FileManager and timestamp.
    ///   - scanner: Used to re-scan the destination after copy.
    /// - Returns: An updated `SkillRecord` reflecting the new version.
    /// - Throws: `SkillLifecycleError` on permission, IO, or source-not-found failures.
    static func changeVersion(
        of skill: SkillRecord,
        to newPackageURL: URL,
        in source: SkillSource,
        context: SourceScanContext,
        scanner: SkillScanner
    ) throws -> SkillRecord {
        let fm = context.fileManager

        // Validate new package is a directory.
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: newPackageURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw SkillLifecycleError(
                code: .skillNotFound,
                message: "New package path is not a directory: \(newPackageURL.path)"
            )
        }

        // Permission check: parent directory of the existing skill must be writable.
        try PermissionChecker.requireWritableParent(of: skill.path, fileManager: fm, for: "version change")

        // Remove existing skill directory.
        if fm.fileExists(atPath: skill.path.path) {
            do {
                try fm.removeItem(at: skill.path)
            } catch {
                throw SkillLifecycleError(
                    code: .ioFailure,
                    message: "Failed to remove existing skill before version change: \(error.localizedDescription)"
                )
            }
        }

        // Copy new version into the same parent directory.
        let parent = skill.path.deletingLastPathComponent()
        let destination = parent.appendingPathComponent(newPackageURL.lastPathComponent)
        do {
            try fm.copyItem(at: newPackageURL, to: destination)
        } catch {
            throw SkillLifecycleError(
                code: .ioFailure,
                message: "Failed to copy new skill version: \(error.localizedDescription)"
            )
        }

        // Re-scan to produce an accurate SkillRecord.
        let result = scanner.scan(source: source, context: context)
        return resolveInstalledRecord(
            scanResult: result,
            destination: destination,
            source: source,
            fileManager: fm,
            preferredManifestFileNames: scanner.manifestFileNames
        )
    }

    private static func resolveInstalledRecord(
        scanResult: SourceScanResult,
        destination: URL,
        source: SkillSource,
        fileManager: FileManager,
        preferredManifestFileNames: [String]
    ) -> SkillRecord {
        let manifest = loadManifest(
            in: destination,
            fileManager: fileManager,
            preferredManifestFileNames: preferredManifestFileNames
        )

        guard let scanned = scanResult.skills.first(where: {
            $0.path.standardizedFileURL == destination.standardizedFileURL
        }) else {
            // Scanner miss fallback: build a minimal record from directory name + manifest when available.
            return SkillRecord(
                name: manifest?.name ?? destination.lastPathComponent,
                version: manifest?.version,
                path: destination,
                source: source
            )
        }

        // Scanner may find the directory but still miss metadata (e.g. custom scanner setup).
        // When that happens, enrich with manifest-derived name/version if available.
        let manifestName = manifest?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let scannedIsFallbackName = scanned.name == destination.lastPathComponent

        return SkillRecord(
            id: scanned.id,
            name: (scannedIsFallbackName ? manifestName : scanned.name) ?? scanned.name,
            version: scanned.version ?? manifest?.version,
            path: scanned.path,
            source: source,
            metadata: scanned.metadata
        )
    }

    private static func loadManifest(
        in directory: URL,
        fileManager: FileManager,
        preferredManifestFileNames: [String] = []
    ) -> SkillManifest? {
        let defaults = ["skill.json", "manifest.json"]
        let manifestFileNames = Array(NSOrderedSet(array: preferredManifestFileNames + defaults)) as? [String] ?? defaults

        for fileName in manifestFileNames {
            let manifestURL = directory.appendingPathComponent(fileName)
            guard fileManager.fileExists(atPath: manifestURL.path) else { continue }
            guard let data = try? Data(contentsOf: manifestURL) else { continue }
            if let manifest = try? JSONDecoder().decode(SkillManifest.self, from: data) {
                return manifest
            }
        }
        return nil
    }

    /// Delete an installed skill directory from the file system.
    ///
    /// - Parameters:
    ///   - skill: The record pointing to the skill directory.
    ///   - context: Provides the FileManager.
    /// - Throws: `SkillLifecycleError` for permission or IO failures.
    static func remove(skill: SkillRecord, context: SourceScanContext) throws {
        let fm = context.fileManager
        let path = skill.path

        guard fm.fileExists(atPath: path.path) else {
            throw SkillLifecycleError(
                code: .skillNotFound,
                message: "Skill path does not exist: \(path.path)"
            )
        }

        // Permission check: parent directory must be writable.
        try PermissionChecker.requireWritableParent(of: path, fileManager: fm, for: "remove")

        do {
            try fm.removeItem(at: path)
        } catch {
            throw SkillLifecycleError(
                code: .ioFailure,
                message: "Failed to remove skill: \(error.localizedDescription)"
            )
        }
    }
}
