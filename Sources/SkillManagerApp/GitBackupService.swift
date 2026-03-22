import Foundation

/// Errors from git backup operations.
enum GitBackupError: LocalizedError {
    case gitNotFound
    case commandFailed(Int32, String)
    case invalidRemoteURL

    var errorDescription: String? {
        switch self {
        case .gitNotFound:
            return "git executable not found. Install Xcode Command Line Tools."
        case .commandFailed(let code, let stderr):
            return "git exited with code \(code): \(stderr)"
        case .invalidRemoteURL:
            return "Invalid remote URL."
        }
    }
}

/// Settings for the git backup feature, stored in UserDefaults.
struct GitBackupSettings: Codable {
    var remoteURL: String
    var localRepoPath: String
    var lastSyncAt: Date?
    var lastSyncStatus: GitBackupStatus

    enum GitBackupStatus: String, Codable {
        case idle, success, failed
    }
}

/// Encapsulates git operations for backing up skill sources.
final class GitBackupService {
    private let gitPath: String

    init() throws {
        let candidates = ["/usr/bin/git", "/usr/local/bin/git", "/opt/homebrew/bin/git"]
        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            self.gitPath = found
        } else if let path = (try? run(launchPath: "/usr/bin/which", args: ["git"]))?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !path.isEmpty {
            self.gitPath = path
        } else {
            throw GitBackupError.gitNotFound
        }
    }

    /// Clone remote into localPath, or initialise + set remote if localPath already exists.
    func initRepo(localPath: String, remoteURL: String) throws {
        let fm = FileManager.default
        let dotGit = URL(fileURLWithPath: localPath).appendingPathComponent(".git").path

        if fm.fileExists(atPath: dotGit) {
            // Already a repo — update remote origin
            _ = try git(args: ["remote", "set-url", "origin", remoteURL], cwd: localPath)
        } else {
            try fm.createDirectory(atPath: localPath, withIntermediateDirectories: true)
            // Try clone first; fall back to init if clone fails (e.g. empty remote)
            do {
                _ = try git(args: ["clone", remoteURL, "."], cwd: localPath)
            } catch {
                _ = try git(args: ["init"], cwd: localPath)
                _ = try git(args: ["remote", "add", "origin", remoteURL], cwd: localPath)
            }
        }
    }

    /// Stage all changes, commit with timestamp, pull --rebase, push.
    func sync(repoPath: String) throws {
        _ = try git(args: ["add", "-A"], cwd: repoPath)

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let status = try git(args: ["status", "--porcelain"], cwd: repoPath)
        guard !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Nothing to commit — still try pull + push
            _ = try? git(args: ["pull", "--rebase", "origin", "HEAD"], cwd: repoPath)
            return
        }

        _ = try git(args: ["commit", "-m", "SkillKit backup \(timestamp)"], cwd: repoPath)
        _ = try? git(args: ["pull", "--rebase", "origin", "HEAD"], cwd: repoPath)
        _ = try git(args: ["push", "origin", "HEAD"], cwd: repoPath)
    }

    // MARK: - Private

    @discardableResult
    private func git(args: [String], cwd: String) throws -> String {
        try run(launchPath: gitPath, args: args, cwd: cwd)
    }
}

// MARK: - Process helper

@discardableResult
private func run(launchPath: String, args: [String], cwd: String? = nil) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchPath)
    process.arguments = args
    if let cwd {
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
    }

    var env = ProcessInfo.processInfo.environment
    // Ensure git uses the user's SSH agent / credentials
    env["GIT_TERMINAL_PROMPT"] = "0"
    process.environment = env

    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe

    try process.run()
    process.waitUntilExit()

    let stdout = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    if process.terminationStatus != 0 {
        throw GitBackupError.commandFailed(process.terminationStatus, stderr)
    }
    return stdout
}
