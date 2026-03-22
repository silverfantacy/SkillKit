import Foundation
import GRDB
import SourceDiscovery

/// Persisted representation of a SkillRecord stored in SQLite.
public struct PersistedSkill: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "skills"

    public var id: String
    public var name: String
    public var version: String?
    public var path: String
    public var sourceId: String
    public var sourceType: String
    public var metadataJSON: String
    public var isEnabled: Bool
    public var indexedAt: Date
    public var tagsJSON: String

    public init(from record: SkillRecord, isEnabled: Bool = true, indexedAt: Date = Date(), tags: [String] = []) {
        self.id = record.id
        self.name = record.name
        self.version = record.version
        self.path = record.path.standardizedFileURL.path
        self.sourceId = record.sourceId
        self.sourceType = record.sourceType.rawValue
        self.metadataJSON = (try? JSONEncoder().encode(record.metadata)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        self.isEnabled = isEnabled
        self.indexedAt = indexedAt
        self.tagsJSON = (try? JSONEncoder().encode(tags)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    public var tags: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(tagsJSON.utf8))) ?? []
    }

    public func toSkillRecord(source: SkillSource) -> SkillRecord {
        let url = URL(fileURLWithPath: path)
        let metadata = (try? JSONDecoder().decode([String: String].self, from: Data(metadataJSON.utf8))) ?? [:]
        return SkillRecord(
            id: id,
            name: name,
            version: version,
            path: url,
            source: source,
            metadata: metadata
        )
    }
}
