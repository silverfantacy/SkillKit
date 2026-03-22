import Foundation

public enum SkillSourceType: String, Codable, CaseIterable, Hashable {
    case claudeCode = "claude-code"
    case openClaw = "openclaw"
    case project = "project"

    public var displayName: String {
        switch self {
        case .claudeCode:
            return "Claude Code"
        case .openClaw:
            return "OpenClaw"
        case .project:
            return "Workspace"
        }
    }

    /// Whether skills from this source type support enable/disable toggling.
    public var supportsEnableDisable: Bool {
        switch self {
        case .claudeCode, .project:
            return true
        case .openClaw:
            return false
        }
    }

    /// Whether skills from this source type support install/remove operations.
    public var supportsInstallRemove: Bool {
        switch self {
        case .claudeCode, .project:
            return true
        case .openClaw:
            return false
        }
    }

    /// Whether skills from this source type support version change (upgrade/downgrade).
    public var supportsVersionChange: Bool {
        switch self {
        case .claudeCode, .project:
            return true
        case .openClaw:
            return false
        }
    }
}

public enum SkillSourceOrigin: String, Codable, Hashable {
    case discovered
    case userRegistered
}

public struct SkillSource: Codable, Hashable, Identifiable {
    public let id: String
    public let type: SkillSourceType
    public let rootPath: URL
    public let displayName: String
    public let origin: SkillSourceOrigin
    public let metadata: [String: String]

    public init(
        id: String? = nil,
        type: SkillSourceType,
        rootPath: URL,
        displayName: String? = nil,
        origin: SkillSourceOrigin = .discovered,
        metadata: [String: String] = [:]
    ) {
        self.type = type
        self.rootPath = rootPath
        self.displayName = displayName ?? type.displayName
        self.origin = origin
        self.metadata = metadata
        self.id = id ?? SkillSource.makeID(type: type, rootPath: rootPath)
    }

    public static func makeID(type: SkillSourceType, rootPath: URL) -> String {
        let normalizedPath = rootPath.standardizedFileURL.path
        return "\(type.rawValue)::\(normalizedPath)"
    }
}

public struct SkillRecord: Codable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let version: String?
    public let path: URL
    public let sourceId: String
    public let sourceType: SkillSourceType
    public let metadata: [String: String]

    public init(
        id: String? = nil,
        name: String,
        version: String?,
        path: URL,
        source: SkillSource,
        metadata: [String: String] = [:]
    ) {
        self.name = name
        self.version = version
        self.path = path
        self.sourceId = source.id
        self.sourceType = source.type
        self.metadata = metadata
        self.id = id ?? SkillRecord.makeID(sourceId: source.id, skillPath: path)
    }

    public static func makeID(sourceId: String, skillPath: URL) -> String {
        let normalizedPath = skillPath.standardizedFileURL.path
        return "\(sourceId)::\(normalizedPath)"
    }
}

public enum SourceScanStatus: String, Codable, Hashable {
    case success
    case partialFailure
    case failure
}

public struct SourceScanError: Error, Codable, Hashable {
    public enum Code: String, Codable, Hashable {
        case adapterMissing
        case rootNotFound
        case rootNotDirectory
        case rootNotReadable
        case metadataInvalid
        case ioFailure
    }

    public let code: Code
    public let message: String
    public let path: URL?

    public init(code: Code, message: String, path: URL? = nil) {
        self.code = code
        self.message = message
        self.path = path
    }
}

public struct SourceScanResult: Codable, Hashable {
    public let source: SkillSource
    public let skills: [SkillRecord]
    public let errors: [SourceScanError]
    public let scannedAt: Date
    public let status: SourceScanStatus

    public init(
        source: SkillSource,
        skills: [SkillRecord],
        errors: [SourceScanError],
        scannedAt: Date
    ) {
        self.source = source
        self.skills = skills
        self.errors = errors
        self.scannedAt = scannedAt
        if errors.isEmpty {
            self.status = .success
        } else if skills.isEmpty {
            self.status = .failure
        } else {
            self.status = .partialFailure
        }
    }
}
