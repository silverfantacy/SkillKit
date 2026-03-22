import Foundation

public struct SkillScanner {
    public let manifestFileNames: [String]

    public init(manifestFileNames: [String] = ["skill.json", "manifest.json"]) {
        self.manifestFileNames = manifestFileNames
    }

    public func scan(source: SkillSource, context: SourceScanContext) -> SourceScanResult {
        let fileManager = context.fileManager
        var errors: [SourceScanError] = []

        var isDirectory: ObjCBool = false
        let rootPath = source.rootPath.path
        guard fileManager.fileExists(atPath: rootPath, isDirectory: &isDirectory) else {
            errors.append(SourceScanError(code: .rootNotFound, message: "Root path does not exist.", path: source.rootPath))
            return SourceScanResult(source: source, skills: [], errors: errors, scannedAt: context.now)
        }

        guard isDirectory.boolValue else {
            errors.append(SourceScanError(code: .rootNotDirectory, message: "Root path is not a directory.", path: source.rootPath))
            return SourceScanResult(source: source, skills: [], errors: errors, scannedAt: context.now)
        }

        guard fileManager.isReadableFile(atPath: rootPath) else {
            errors.append(SourceScanError(code: .rootNotReadable, message: "Root path is not readable.", path: source.rootPath))
            return SourceScanResult(source: source, skills: [], errors: errors, scannedAt: context.now)
        }

        let skillDirectories: [URL]
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: source.rootPath,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            skillDirectories = contents.filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            }
        } catch {
            errors.append(SourceScanError(code: .ioFailure, message: "Failed to list contents: \(error.localizedDescription)", path: source.rootPath))
            return SourceScanResult(source: source, skills: [], errors: errors, scannedAt: context.now)
        }

        var records: [SkillRecord] = []
        for directory in skillDirectories {
            let manifestResult = loadManifest(in: directory, fileManager: fileManager)
            if let manifestError = manifestResult.error {
                errors.append(manifestError)
            }
            let name = manifestResult.manifest?.name ?? directory.lastPathComponent
            let version = manifestResult.manifest?.version
            let metadata = collectMetadata(
                in: directory,
                manifestURL: manifestResult.manifestURL,
                fileManager: fileManager
            )
            records.append(
                SkillRecord(
                    name: name,
                    version: version,
                    path: directory,
                    source: source,
                    metadata: metadata
                )
            )
        }

        return SourceScanResult(source: source, skills: records, errors: errors, scannedAt: context.now)
    }

    private func loadManifest(in directory: URL, fileManager: FileManager) -> (manifest: SkillManifest?, manifestURL: URL?, error: SourceScanError?) {
        for fileName in manifestFileNames {
            let manifestURL = directory.appendingPathComponent(fileName)
            guard fileManager.fileExists(atPath: manifestURL.path) else { continue }
            do {
                let data = try Data(contentsOf: manifestURL)
                let manifest = try JSONDecoder().decode(SkillManifest.self, from: data)
                return (manifest, manifestURL, nil)
            } catch {
                return (
                    nil,
                    manifestURL,
                    SourceScanError(
                        code: .metadataInvalid,
                        message: "Failed to decode manifest: \(error.localizedDescription)",
                        path: manifestURL
                    )
                )
            }
        }
        return (nil, nil, nil)
    }

    private func collectMetadata(in directory: URL, manifestURL: URL?, fileManager: FileManager) -> [String: String] {
        var metadata: [String: String] = [:]

        if let skillDoc = findFirstExisting(in: directory, names: ["SKILL.md", "skill.md"], fileManager: fileManager) {
            metadata["documents.skill"] = skillDoc.standardizedFileURL.path
            metadata["documents.primary"] = skillDoc.standardizedFileURL.path
        }

        if let readme = findFirstExisting(in: directory, names: ["README.md", "Readme.md", "readme.md"], fileManager: fileManager) {
            metadata["documents.readme"] = readme.standardizedFileURL.path
            if metadata["documents.primary"] == nil {
                metadata["documents.primary"] = readme.standardizedFileURL.path
            }
        }

        if let manifestURL {
            metadata["manifest.path"] = manifestURL.standardizedFileURL.path
        }

        if let entries = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            metadata["filesystem.fileCount"] = String(entries.count)
        }

        if let modified = (try? fileManager.attributesOfItem(atPath: directory.path)[.modificationDate]) as? Date {
            metadata["filesystem.lastModified"] = ISO8601DateFormatter().string(from: modified)
        }

        return metadata
    }

    private func findFirstExisting(in directory: URL, names: [String], fileManager: FileManager) -> URL? {
        for name in names {
            let url = directory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}

struct SkillManifest: Decodable {
    let name: String?
    let version: String?
}
