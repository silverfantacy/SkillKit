import Foundation

public final class TemporaryDirectory {
    public let url: URL

    public init(prefix: String = "skill-manager-test") throws {
        let base = FileManager.default.temporaryDirectory
        url = base.appendingPathComponent("\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    public func makeSourceRoot(_ name: String = "skills") throws -> URL {
        let root = url.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @discardableResult
    public func makeSkillPackage(
        name: String,
        version: String,
        directoryName: String? = nil,
        manifestFileName: String = "skill.json"
    ) throws -> URL {
        let dirName = directoryName ?? name
        let dir = url.appendingPathComponent(dirName)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let manifest = #"{"name":"\#(name)","version":"\#(version)"}"#
        try manifest.data(using: .utf8)!.write(to: dir.appendingPathComponent(manifestFileName))
        return dir
    }
}
