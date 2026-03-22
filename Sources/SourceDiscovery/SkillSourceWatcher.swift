import Foundation

/// Represents a single file change event within a watched source.
public struct SkillFileChangeEvent {
    public enum Kind {
        case added
        case modified
        case removed
    }

    public let path: URL
    public let kind: Kind
    public let source: SkillSource

    public init(path: URL, kind: Kind, source: SkillSource) {
        self.path = path
        self.kind = kind
        self.source = source
    }
}

/// Watches one or more source root directories for file system changes using FSEvents.
public final class SkillSourceWatcher {
    public typealias ChangeHandler = ([SkillFileChangeEvent]) -> Void

    private var eventStream: FSEventStreamRef?
    private let handler: ChangeHandler
    private let sources: [URL: SkillSource]
    private let fileManager: FileManager
    private var knownPaths: [URL: Set<URL>] = [:]
    private let latency: CFTimeInterval
    private let eventQueue = DispatchQueue(label: "ai.openclaw.skillmanager.fsevents")

    public init(
        sources: [SkillSource],
        fileManager: FileManager = .default,
        latency: CFTimeInterval = 1.0,
        handler: @escaping ChangeHandler
    ) {
        self.handler = handler
        self.fileManager = fileManager
        self.latency = latency
        var map: [URL: SkillSource] = [:]
        for source in sources {
            map[source.rootPath.standardizedFileURL] = source
        }
        self.sources = map
        for source in sources {
            knownPaths[source.rootPath.standardizedFileURL] = collectTopLevelPaths(in: source.rootPath)
        }
    }

    /// Start watching. Safe to call multiple times (no-op if already running).
    public func start() {
        guard eventStream == nil else { return }
        let paths = sources.keys.map { $0.path } as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, numEvents, eventPaths, _, _ in
                guard let info else { return }
                let watcher = Unmanaged<SkillSourceWatcher>.fromOpaque(info).takeUnretainedValue()
                let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]
                let changedDirs = Array(paths.prefix(numEvents)).map { URL(fileURLWithPath: $0) }
                watcher.handleFSEvents(changedDirectories: changedDirs)
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )
        if let stream {
            FSEventStreamSetDispatchQueue(stream, eventQueue)
            FSEventStreamStart(stream)
            eventStream = stream
        }
    }

    /// Stop watching and release FSEvents resources.
    public func stop() {
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        eventStream = nil
    }

    deinit {
        stop()
    }

    // MARK: - Private

    private func handleFSEvents(changedDirectories: [URL]) {
        var events: [SkillFileChangeEvent] = []
        for changedDir in changedDirectories {
            guard let source = resolveSource(for: changedDir) else { continue }
            let root = source.rootPath.standardizedFileURL
            let current = collectTopLevelPaths(in: root)
            let previous = knownPaths[root] ?? []
            let added = current.subtracting(previous)
            let removed = previous.subtracting(current)
            let modified = current.intersection(previous).filter { path in
                hasModificationChanged(at: path)
            }
            for path in added {
                events.append(SkillFileChangeEvent(path: path, kind: .added, source: source))
            }
            for path in removed {
                events.append(SkillFileChangeEvent(path: path, kind: .removed, source: source))
            }
            for path in modified {
                events.append(SkillFileChangeEvent(path: path, kind: .modified, source: source))
            }
            knownPaths[root] = current
        }
        if !events.isEmpty {
            handler(events)
        }
    }

    private func resolveSource(for changedPath: URL) -> SkillSource? {
        let standardized = changedPath.standardizedFileURL
        for (root, source) in sources {
            if standardized.path.hasPrefix(root.path) {
                return source
            }
        }
        return nil
    }

    private func collectTopLevelPaths(in root: URL) -> Set<URL> {
        let contents = (try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let dirs = contents.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        }
        return Set(dirs.map { $0.standardizedFileURL })
    }

    private var modDates: [URL: Date] = [:]

    private func hasModificationChanged(at path: URL) -> Bool {
        let attrs = try? fileManager.attributesOfItem(atPath: path.path)
        let modDate = attrs?[.modificationDate] as? Date
        let prev = modDates[path]
        modDates[path] = modDate
        if let modDate, let prev {
            return modDate > prev
        }
        return false
    }
}
