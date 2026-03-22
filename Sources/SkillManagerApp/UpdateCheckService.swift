import Foundation

struct SkillUpdateInfo: Identifiable {
    let skillId: String
    let skillName: String
    let remoteURL: String
    let installedCommit: String?
    let latestCommit: String?
    let hasUpdate: Bool

    var id: String { skillId }
}

/// Checks for updates to git-based skills using `git ls-remote`.
final class UpdateCheckService {
    private let gitPath: String

    init() {
        let candidates = ["/usr/bin/git", "/usr/local/bin/git", "/opt/homebrew/bin/git"]
        self.gitPath = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) ?? "/usr/bin/git"
    }

    /// Check all skills that have `git.remoteURL` metadata.
    func checkAll(skills: [SkillItem]) async -> [SkillUpdateInfo] {
        let gitSkills = skills.filter { !($0.metadata["git.remoteURL"] ?? "").isEmpty }

        return await withTaskGroup(of: SkillUpdateInfo?.self) { group in
            for skill in gitSkills {
                group.addTask {
                    await self.check(skill: skill)
                }
            }
            var results: [SkillUpdateInfo] = []
            for await result in group {
                if let r = result { results.append(r) }
            }
            return results
        }
    }

    private func check(skill: SkillItem) async -> SkillUpdateInfo? {
        guard let remoteURL = skill.metadata["git.remoteURL"], !remoteURL.isEmpty else { return nil }
        let installedCommit = skill.metadata["git.installedCommit"]

        let latestCommit = await Task.detached(priority: .utility) { [gitPath] in
            try? self.lsRemoteHead(gitPath: gitPath, remoteURL: remoteURL)
        }.value

        let hasUpdate: Bool
        if let latest = latestCommit, let installed = installedCommit {
            hasUpdate = !latest.hasPrefix(installed) && !installed.hasPrefix(latest)
        } else {
            hasUpdate = false
        }

        return SkillUpdateInfo(
            skillId: skill.id,
            skillName: skill.name,
            remoteURL: remoteURL,
            installedCommit: installedCommit,
            latestCommit: latestCommit,
            hasUpdate: hasUpdate
        )
    }

    private func lsRemoteHead(gitPath: String, remoteURL: String) throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = ["ls-remote", remoteURL, "HEAD"]
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = env

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        let output = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // Format: "<commit>\tHEAD"
        return output.components(separatedBy: "\t").first?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
