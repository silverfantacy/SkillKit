import Foundation
import GRDB
import SourceDiscovery

/// Persisted representation of a SkillSource stored in SQLite.
public struct PersistedSource: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "sources"

    public var id: String
    public var type: String
    public var rootPath: String
    public var displayName: String
    public var origin: String
    public var metadataJSON: String
    public var isActive: Bool
    public var lastScanAt: Date?
    public var lastScanStatus: String?
    public var lastScanError: String?

    public init(from source: SkillSource, isActive: Bool = true) {
        self.id = source.id
        self.type = source.type.rawValue
        self.rootPath = source.rootPath.standardizedFileURL.path
        self.displayName = source.displayName
        self.origin = source.origin.rawValue
        self.metadataJSON = (try? JSONEncoder().encode(source.metadata)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        self.isActive = isActive
    }

    public func toSkillSource() -> SkillSource {
        let url = URL(fileURLWithPath: rootPath)
        let sourceType = SkillSourceType(rawValue: type) ?? .project
        let sourceOrigin = SkillSourceOrigin(rawValue: origin) ?? .discovered
        let metadata = (try? JSONDecoder().decode([String: String].self, from: Data(metadataJSON.utf8))) ?? [:]
        return SkillSource(
            id: id,
            type: sourceType,
            rootPath: url,
            displayName: displayName,
            origin: sourceOrigin,
            metadata: metadata
        )
    }
}
