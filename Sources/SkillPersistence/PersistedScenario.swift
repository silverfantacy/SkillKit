import Foundation
import GRDB

/// Persisted representation of a Scenario stored in SQLite.
public struct PersistedScenario: Codable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "scenarios"

    public var id: String
    public var name: String
    public var scenarioDescription: String
    public var enabledSkillIdsJSON: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String, name: String, description: String, enabledSkillIds: [String], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.scenarioDescription = description
        self.enabledSkillIdsJSON = (try? JSONEncoder().encode(enabledSkillIds)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var enabledSkillIds: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(enabledSkillIdsJSON.utf8))) ?? []
    }
}
