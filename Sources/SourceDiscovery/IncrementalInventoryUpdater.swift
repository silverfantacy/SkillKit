import Foundation

/// Handles incremental inventory updates triggered by file change events.
/// Re-scans only the affected skill directory instead of performing a full source rescan.
public final class IncrementalInventoryUpdater {
    private let scanner: SkillScanner
    private let fileManager: FileManager

    public init(scanner: SkillScanner = SkillScanner(), fileManager: FileManager = .default) {
        self.scanner = scanner
        self.fileManager = fileManager
    }

    /// Process a batch of file change events and return incremental scan results.
    ///
    /// - Returns: An array of `IncrementalUpdateResult` — one per affected skill directory.
    public func process(
        events: [SkillFileChangeEvent],
        context: SourceScanContext
    ) -> [IncrementalUpdateResult] {
        // Deduplicate: one update per (source, skill directory) pair.
        var pending: [String: (source: SkillSource, skillPath: URL, kind: SkillFileChangeEvent.Kind)] = [:]
        for event in events {
            let key = "\(event.source.id)::\(event.path.standardizedFileURL.path)"
            // Prefer removal if any event for this path is a removal; otherwise prefer added > modified.
            if let existing = pending[key] {
                if event.kind == .removed || existing.kind == .modified {
                    pending[key] = (event.source, event.path, event.kind)
                }
            } else {
                pending[key] = (event.source, event.path, event.kind)
            }
        }

        var results: [IncrementalUpdateResult] = []
        for (_, (source, skillPath, kind)) in pending {
            let result = apply(source: source, skillPath: skillPath, kind: kind, context: context)
            results.append(result)
        }
        return results
    }

    // MARK: - Private

    private func apply(
        source: SkillSource,
        skillPath: URL,
        kind: SkillFileChangeEvent.Kind,
        context: SourceScanContext
    ) -> IncrementalUpdateResult {
        switch kind {
        case .removed:
            let skillId = SkillRecord.makeID(sourceId: source.id, skillPath: skillPath)
            return IncrementalUpdateResult(
                source: source,
                skillPath: skillPath,
                change: .removed(skillId: skillId),
                scannedAt: context.now
            )
        case .added, .modified:
            let skill = scanSingleSkill(at: skillPath, source: source, context: context)
            let change: IncrementalUpdateResult.Change = (kind == .added) ? .added(skill) : .updated(skill)
            return IncrementalUpdateResult(
                source: source,
                skillPath: skillPath,
                change: change,
                scannedAt: context.now
            )
        }
    }

    private func scanSingleSkill(
        at path: URL,
        source: SkillSource,
        context: SourceScanContext
    ) -> SkillRecord {
        // Reuse SkillScanner's manifest loading by scanning a synthetic single-entry source.
        let syntheticSource = SkillSource(
            id: source.id,
            type: source.type,
            rootPath: path.deletingLastPathComponent(),
            displayName: source.displayName,
            origin: source.origin,
            metadata: source.metadata
        )
        // Scan the parent directory but filter to only the target subdirectory.
        let fullResult = scanner.scan(source: syntheticSource, context: context)
        let standardized = path.standardizedFileURL
        if let record = fullResult.skills.first(where: { $0.path.standardizedFileURL == standardized }) {
            return record
        }
        // Fallback: directory exists but no manifest found — use folder name.
        return SkillRecord(name: path.lastPathComponent, version: nil, path: path, source: source)
    }
}

/// The outcome of an incremental update for a single skill path.
public struct IncrementalUpdateResult {
    public enum Change {
        case added(SkillRecord)
        case updated(SkillRecord)
        case removed(skillId: String)
    }

    public let source: SkillSource
    public let skillPath: URL
    public let change: Change
    public let scannedAt: Date

    public init(source: SkillSource, skillPath: URL, change: Change, scannedAt: Date) {
        self.source = source
        self.skillPath = skillPath
        self.change = change
        self.scannedAt = scannedAt
    }
}
