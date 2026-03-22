import Foundation
import SwiftUI
import SkillPersistence
import SourceDiscovery

// MARK: - View model types

struct SkillItem: Identifiable, Hashable {
    let id: String
    let name: String
    let version: String?
    let sourceId: String
    let sourceType: SkillSourceType
    let sourceName: String
    var isEnabled: Bool
    let path: String
    let indexedAt: Date
    let primaryDocumentPath: String?
    let skillDocumentPath: String?
    let readmePath: String?
    let manifestPath: String?
    let fileCount: Int?
    let lastModified: Date?
    var tags: [String]
    let metadata: [String: String]
}

struct ScenarioItem: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let enabledSkillIds: [String]
    let createdAt: Date
}

struct SourceItem: Identifiable, Hashable {
    let id: String
    let type: SkillSourceType
    let displayName: String
    let rootPath: String
    let isActive: Bool
    let lastScanAt: Date?
    let lastScanStatus: String?
    let lastScanError: String?
    let skillCount: Int
}

enum PipelineStep: String {
    case idle
    case refresh
    case sourceScan
    case syncPlan
    case syncApply
    case securityScan
}

// MARK: - AppStore

@MainActor
final class AppStore: ObservableObject {
    static let featureSkillStoreEntryKey = "feature.skillStore.enabled"

    // MARK: Published state

    @Published var skills: [SkillItem] = []
    @Published var sources: [SourceItem] = []
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var sourceActionMessage: String?
    @Published var sourceActionFailed = false
    @Published var currentPipelineStep: PipelineStep = .idle
    @Published var currentPipelineMessage: String?
    @Published var currentPipelineDetail: String?

    /// Last orchestration errors (non-fatal, shown as warnings).
    @Published var orchestrationWarnings: [String] = []

    /// Pending sync plan awaiting user confirmation (nil = no plan computed).
    @Published var pendingSyncPlan: SyncPlan?

    /// Latest security report from the most recent scan.
    @Published var latestSecurityReport: SecurityReport?

    /// All saved scenarios.
    @Published var scenarios: [ScenarioItem] = []

    /// Update info keyed by skillId.
    @Published var skillUpdates: [String: SkillUpdateInfo] = [:]

    /// Whether update check is running.
    @Published var isCheckingUpdates = false

    /// Git backup settings (nil = not configured).
    @Published var gitBackupSettings: GitBackupSettings? = nil

    /// Current git backup status.
    @Published var gitBackupStatus: GitBackupSettings.GitBackupStatus = .idle

    /// Currently active scenario id (nil = no scenario applied).
    @Published var activeScenarioId: String? = nil

    // MARK: Filter state

    @Published var searchText = ""
    @Published var filterSourceId: String? = nil
    @Published var filterEnabled: Bool? = nil
    @Published var filterTags: Set<String> = []

    // MARK: Private

    private var db: AppDatabase?
    private var skillRepo: SkillRepository?
    private var sourceRepo: SourceRepository?
    private var scenarioRepo: ScenarioRepository?
    private var persistenceService: InventoryPersistenceService?
    private var orchestrationService: OrchestrationService?
    private var syncEngine: SyncEngine?
    private var securityService: SecurityService?
    private let sourceOrderKey = "ui.sources.order"

    private var watcher: SkillSourceWatcher?
    private let incrementalUpdater = IncrementalInventoryUpdater()
    private var watcherDebounceTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        do {
            guard let appSupportBase = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first else {
                loadMockData()
                return
            }
            let appSupport = appSupportBase
                .appendingPathComponent("SkillManager", isDirectory: true)
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            let dbPath = appSupport.appendingPathComponent("skills.db").path
            let database = try AppDatabase.open(at: dbPath)
            let sRepo = SourceRepository(database: database)
            let skRepo = SkillRepository(database: database)
            let dsRepo = DesiredStateRepository(database: database)
            let auditRepo = SyncAuditRepository(database: database)
            let secRepo = SecurityReportRepository(database: database)

            self.db = database
            self.sourceRepo = sRepo
            self.skillRepo = skRepo
            self.scenarioRepo = ScenarioRepository(database: database)

            let persistence = InventoryPersistenceService(sourceRepository: sRepo, skillRepository: skRepo)
            self.persistenceService = persistence

            let security = SecurityService(skillRepository: skRepo, securityRepository: secRepo)
            self.securityService = security

            self.syncEngine = SyncEngine(
                skillRepository: skRepo,
                desiredStateRepository: dsRepo,
                auditRepository: auditRepo
            )

            let adapters: [any SourceAdapter] = [
                ClaudeCodeSourceAdapter(),
                OpenClawSourceAdapter(),
                ProjectSourceAdapter()
            ]
            let discoveryService = SourceDiscoveryService(adapters: adapters)
            self.orchestrationService = OrchestrationService(
                discoveryService: discoveryService,
                persistenceService: persistence,
                securityService: security
            )

            loadFromDB()
            loadScenarios()
            loadGitBackupSettings()
            startWatcher()
        } catch {
            // Fall back to preview/mock data so the app is still usable
            loadMockData()
        }
    }

    // MARK: - Loading

    private func loadFromDB() {
        guard let skillRepo, let sourceRepo else { return }

        let persistedSources = (try? sourceRepo.fetchPersistedAll()) ?? []
        let persistedSkills = (try? skillRepo.fetchAll()) ?? []

        // If empty, keep real empty state instead of seeding mock data.
        if persistedSources.isEmpty {
            self.sources = []
            self.skills = []
            return
        }

        let sourceMap: [String: PersistedSource] = Dictionary(
            uniqueKeysWithValues: persistedSources.map { ($0.id, $0) }
        )
        var skillCountMap: [String: Int] = [:]
        for skill in persistedSkills {
            skillCountMap[skill.sourceId, default: 0] += 1
        }

        var mappedSources = persistedSources.map { source in
            SourceItem(
                id: source.id,
                type: SkillSourceType(rawValue: source.type) ?? .project,
                displayName: source.displayName,
                rootPath: source.rootPath,
                isActive: source.isActive,
                lastScanAt: source.lastScanAt,
                lastScanStatus: source.lastScanStatus,
                lastScanError: source.lastScanError,
                skillCount: skillCountMap[source.id] ?? 0
            )
        }

        let savedOrder = UserDefaults.standard.stringArray(forKey: sourceOrderKey) ?? []
        if !savedOrder.isEmpty {
            let rank = Dictionary(uniqueKeysWithValues: savedOrder.enumerated().map { ($0.element, $0.offset) })
            mappedSources.sort { lhs, rhs in
                let li = rank[lhs.id] ?? Int.max
                let ri = rank[rhs.id] ?? Int.max
                if li == ri { return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending }
                return li < ri
            }
        }

        self.sources = mappedSources

        self.skills = persistedSkills.compactMap { ps in
            let sourceName = sourceMap[ps.sourceId]?.displayName ?? ps.sourceId
            let sourceType = SkillSourceType(rawValue: ps.sourceType) ?? .project
            let metadata = Self.decodeMetadata(ps.metadataJSON)
            return SkillItem(
                id: ps.id,
                name: ps.name,
                version: ps.version,
                sourceId: ps.sourceId,
                sourceType: sourceType,
                sourceName: sourceName,
                isEnabled: ps.isEnabled,
                path: ps.path,
                indexedAt: ps.indexedAt,
                primaryDocumentPath: metadata["documents.primary"],
                skillDocumentPath: metadata["documents.skill"],
                readmePath: metadata["documents.readme"],
                manifestPath: metadata["manifest.path"],
                fileCount: metadata["filesystem.fileCount"].flatMap(Int.init),
                lastModified: metadata["filesystem.lastModified"].flatMap(Self.parseISO8601Date),
                tags: ps.tags,
                metadata: metadata
            )
        }
    }

    private func loadMockData() {
        self.sources = SourceItem.sampleSources
        self.skills = SkillItem.sampleSkills
    }

    private func seedMockData(skillRepo: SkillRepository, sourceRepo: SourceRepository) {
        let mockSources = SkillSource.sampleSources
        let mockSkills = SkillItem.sampleSkills

        for source in mockSources {
            try? sourceRepo.save(source)
        }
        for skill in mockSkills {
            let source = mockSources.first { $0.id == skill.sourceId } ?? mockSources[0]
            let record = SkillRecord(
                id: skill.id,
                name: skill.name,
                version: skill.version,
                path: URL(fileURLWithPath: skill.path),
                source: source
            )
            try? skillRepo.save(record, isEnabled: skill.isEnabled)
        }
    }

    private static func decodeMetadata(_ rawJSON: String) -> [String: String] {
        let rawData = Data(rawJSON.utf8)

        if let stringMap = try? JSONDecoder().decode([String: String].self, from: rawData) {
            return stringMap
        }

        guard let object = try? JSONSerialization.jsonObject(with: rawData),
              let map = object as? [String: Any] else {
            return [:]
        }

        var normalized: [String: String] = [:]
        for (key, value) in map {
            switch value {
            case let string as String:
                normalized[key] = string
            case let number as NSNumber:
                normalized[key] = number.stringValue
            default:
                continue
            }
        }
        return normalized
    }

    private static func parseISO8601Date(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    // MARK: - Computed

    var filteredSkills: [SkillItem] {
        skills.filter { skill in
            if let sourceId = filterSourceId, skill.sourceId != sourceId { return false }
            if let enabled = filterEnabled, skill.isEnabled != enabled { return false }
            if !searchText.isEmpty,
               !skill.name.localizedCaseInsensitiveContains(searchText) { return false }
            if !filterTags.isEmpty, filterTags.isDisjoint(with: skill.tags) { return false }
            return true
        }
    }

    var allTags: [String] {
        var seen: Set<String> = []
        return skills.flatMap(\.tags).filter { seen.insert($0).inserted }.sorted()
    }

    var isSkillStoreEntryEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.featureSkillStoreEntryKey)
    }

    // MARK: - Actions

    // MARK: - Scenarios

    private func loadScenarios() {
        let persisted = (try? scenarioRepo?.fetchAll()) ?? []
        scenarios = persisted.map {
            ScenarioItem(id: $0.id, name: $0.name, description: $0.scenarioDescription, enabledSkillIds: $0.enabledSkillIds, createdAt: $0.createdAt)
        }
    }

    func createScenario(name: String, description: String = "", skillIds: [String]) {
        let id = UUID().uuidString
        let now = Date()
        let persisted = PersistedScenario(id: id, name: name, description: description, enabledSkillIds: skillIds, createdAt: now, updatedAt: now)
        let repo = scenarioRepo
        Task.detached(priority: .userInitiated) {
            try? repo?.save(persisted)
        }
        scenarios.append(ScenarioItem(id: id, name: name, description: description, enabledSkillIds: skillIds, createdAt: now))
    }

    func saveCurrentAsScenario(name: String) {
        let enabledIds = skills.filter(\.isEnabled).map(\.id)
        createScenario(name: name, skillIds: enabledIds)
    }

    func applyScenario(id: String) {
        guard let scenario = scenarios.first(where: { $0.id == id }) else { return }
        let enabledSet = Set(scenario.enabledSkillIds)
        for idx in skills.indices {
            skills[idx].isEnabled = enabledSet.contains(skills[idx].id)
        }
        activeScenarioId = id
        let repo = skillRepo
        Task.detached(priority: .userInitiated) {
            try? repo?.batchSetEnabled(enabledIds: enabledSet)
        }
    }

    func deleteScenario(id: String) {
        scenarios.removeAll { $0.id == id }
        if activeScenarioId == id { activeScenarioId = nil }
        let repo = scenarioRepo
        Task.detached(priority: .userInitiated) {
            try? repo?.delete(id: id)
        }
    }

    func renameScenario(id: String, name: String) {
        guard let idx = scenarios.firstIndex(where: { $0.id == id }) else { return }
        let old = scenarios[idx]
        scenarios[idx] = ScenarioItem(id: old.id, name: name, description: old.description, enabledSkillIds: old.enabledSkillIds, createdAt: old.createdAt)
        let repo = scenarioRepo
        let updatedAt = Date()
        let enabledIds = old.enabledSkillIds
        let desc = old.description
        Task.detached(priority: .userInitiated) {
            let persisted = PersistedScenario(id: id, name: name, description: desc, enabledSkillIds: enabledIds, createdAt: old.createdAt, updatedAt: updatedAt)
            try? repo?.save(persisted)
        }
    }

    // MARK: - Git Backup

    private static let gitBackupSettingsKey = "gitBackup.settings"

    func loadGitBackupSettings() {
        guard let data = UserDefaults.standard.data(forKey: Self.gitBackupSettingsKey),
              let settings = try? JSONDecoder().decode(GitBackupSettings.self, from: data) else { return }
        gitBackupSettings = settings
        gitBackupStatus = settings.lastSyncStatus
    }

    private func saveGitBackupSettings(_ settings: GitBackupSettings) {
        gitBackupSettings = settings
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.gitBackupSettingsKey)
        }
    }

    func initializeBackupRepo(remoteURL: String) async {
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("SkillManager/GitBackup").path ?? "/tmp/SkillManagerGitBackup"

        var settings = GitBackupSettings(remoteURL: remoteURL, localRepoPath: appSupport, lastSyncAt: nil, lastSyncStatus: .idle)
        saveGitBackupSettings(settings)

        do {
            let service = try GitBackupService()
            let localPath = appSupport
            let remote = remoteURL
            try await Task.detached(priority: .utility) {
                try service.initRepo(localPath: localPath, remoteURL: remote)
            }.value
            settings.lastSyncStatus = .success
            saveGitBackupSettings(settings)
            setSourceAction(message: "Git backup repository initialised.", failed: false)
        } catch {
            settings.lastSyncStatus = .failed
            saveGitBackupSettings(settings)
            setSourceAction(message: "Git backup init failed: \(error.localizedDescription)", failed: true)
        }
    }

    func syncToGit() async {
        guard var settings = gitBackupSettings else {
            setSourceAction(message: "Git backup not configured. Set a remote URL in Settings.", failed: true)
            return
        }
        gitBackupStatus = .idle
        setSourceAction(message: "Syncing to git…", failed: false)

        do {
            let service = try GitBackupService()
            let repoPath = settings.localRepoPath
            try await Task.detached(priority: .utility) {
                try service.sync(repoPath: repoPath)
            }.value
            settings.lastSyncAt = Date()
            settings.lastSyncStatus = .success
            saveGitBackupSettings(settings)
            gitBackupStatus = .success
            setSourceAction(message: "Sync to git succeeded.", failed: false)
        } catch {
            settings.lastSyncStatus = .failed
            saveGitBackupSettings(settings)
            gitBackupStatus = .failed
            setSourceAction(message: "Sync to git failed: \(error.localizedDescription)", failed: true)
        }
    }

    // MARK: - Update Tracking

    func checkForUpdates() async {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        setSourceAction(message: "Checking for skill updates…", failed: false)

        let currentSkills = skills
        let service = UpdateCheckService()
        let results = await service.checkAll(skills: currentSkills)

        var map: [String: SkillUpdateInfo] = [:]
        for info in results {
            map[info.skillId] = info
        }
        skillUpdates = map
        isCheckingUpdates = false

        let updateCount = results.filter(\.hasUpdate).count
        if updateCount > 0 {
            setSourceAction(message: "\(updateCount) skill\(updateCount == 1 ? "" : "s") have updates available.", failed: false)
        } else {
            setSourceAction(message: "All skills are up to date.", failed: false)
        }
    }

    func setMetadata(skillId: String, metadata: [String: String]) {
        guard let idx = skills.firstIndex(where: { $0.id == skillId }) else { return }
        skills[idx] = SkillItem(
            id: skills[idx].id, name: skills[idx].name, version: skills[idx].version,
            sourceId: skills[idx].sourceId, sourceType: skills[idx].sourceType,
            sourceName: skills[idx].sourceName, isEnabled: skills[idx].isEnabled,
            path: skills[idx].path, indexedAt: skills[idx].indexedAt,
            primaryDocumentPath: skills[idx].primaryDocumentPath,
            skillDocumentPath: skills[idx].skillDocumentPath,
            readmePath: skills[idx].readmePath, manifestPath: skills[idx].manifestPath,
            fileCount: skills[idx].fileCount, lastModified: skills[idx].lastModified,
            tags: skills[idx].tags, metadata: metadata
        )
        let repo = skillRepo
        let json = (try? JSONEncoder().encode(metadata)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        Task.detached(priority: .userInitiated) {
            try? repo?.setMetadataJSON(skillId: skillId, json: json)
        }
    }

    func setTags(skillId: String, tags: [String]) {
        guard let idx = skills.firstIndex(where: { $0.id == skillId }) else { return }
        skills[idx].tags = tags
        let repo = skillRepo
        Task.detached(priority: .userInitiated) {
            try? repo?.setTags(skillId: skillId, tags: tags)
        }
    }

    func toggleEnabled(skillId: String) {
        guard let idx = skills.firstIndex(where: { $0.id == skillId }) else { return }
        let newValue = !skills[idx].isEnabled
        skills[idx].isEnabled = newValue
        let service = persistenceService
        Task.detached(priority: .userInitiated) {
            do {
                try service?.setSkillEnabled(skillId: skillId, isEnabled: newValue)
            } catch {
                print("[AppStore] toggleEnabled failed for \(skillId): \(error)")
            }
        }
    }

    func deleteSource(id: String) {
        sources.removeAll { $0.id == id }
        skills.removeAll { $0.sourceId == id }
        UserDefaults.standard.set(sources.map(\.id), forKey: sourceOrderKey)
        let repo = sourceRepo
        Task.detached(priority: .userInitiated) {
            try? repo?.delete(sourceId: id)
        }
        restartWatcher()
    }

    func addSource(_ source: SkillSource) {
        let service = persistenceService
        let sourceRepo = sourceRepo
        let orchestration = orchestrationService

        Task { [weak self] in
            guard let self else { return }
            do {
                try service?.registerSource(source)

                guard let sourceRepo,
                      let orchestration,
                      let persistedSource = try sourceRepo.fetch(id: source.id) else {
                    loadFromDB()
                    return
                }

                isRefreshing = true
                sourceActionMessage = nil
                beginPipeline(
                    .sourceScan,
                    formatted: String(format: L10n.tr("pipeline.scan.newSource"), persistedSource.displayName),
                    detail: persistedSource.id
                )
                defer {
                    isRefreshing = false
                    clearPipeline()
                }

                let result = await Task.detached(priority: .userInitiated) {
                    orchestration.rescan(source: persistedSource, runSecurityScan: false)
                }.value

                orchestrationWarnings = result.errors.map(\.localizedDescription)
                if let firstError = orchestrationWarnings.first {
                    setSourceAction(message: String(format: L10n.tr("action.scan.failed"), firstError), failed: true)
                } else {
                    setSourceAction(message: String(format: L10n.tr("action.scan.success"), persistedSource.displayName), failed: false)
                }

                loadFromDB()
                restartWatcher()
            } catch {
                setSourceAction(message: String(format: L10n.tr("action.scan.failed"), error.localizedDescription), failed: true)
                loadFromDB()
            }
        }
    }


    private func adapter(for type: SkillSourceType) -> (any SourceAdapter)? {
        switch type {
        case .claudeCode: return ClaudeCodeSourceAdapter()
        case .openClaw: return OpenClawSourceAdapter()
        case .project: return ProjectSourceAdapter()
        }
    }

    private func beginPipeline(_ step: PipelineStep, messageKey: String, detail: String? = nil) {
        currentPipelineStep = step
        currentPipelineMessage = L10n.tr(messageKey)
        currentPipelineDetail = detail
    }

    private func beginPipeline(_ step: PipelineStep, formatted message: String, detail: String? = nil) {
        currentPipelineStep = step
        currentPipelineMessage = message
        currentPipelineDetail = detail
    }

    private func clearPipeline() {
        currentPipelineStep = .idle
        currentPipelineMessage = nil
        currentPipelineDetail = nil
    }

    // MARK: - File Watcher

    private func startWatcher() {
        guard let sourceRepo else { return }
        let activeSources = (try? sourceRepo.fetchActive()) ?? []
        guard !activeSources.isEmpty else { return }
        let skillSources = activeSources
        guard !skillSources.isEmpty else { return }
        watcher = SkillSourceWatcher(sources: skillSources) { [weak self] events in
            Task { @MainActor [weak self] in
                self?.handleWatcherEvents(events)
            }
        }
        watcher?.start()
    }

    private func restartWatcher() {
        watcher?.stop()
        watcher = nil
        startWatcher()
    }

    private func handleWatcherEvents(_ events: [SkillFileChangeEvent]) {
        watcherDebounceTask?.cancel()
        watcherDebounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s debounce
            } catch {
                return // cancelled
            }
            guard let persistence = self.persistenceService else { return }
            let updater = self.incrementalUpdater
            let context = SourceScanContext()
            let results = await Task.detached(priority: .utility) {
                updater.process(events: events, context: context)
            }.value
            do {
                try persistence.apply(incrementalResults: results)
            } catch {
                print("[AppStore] incremental update failed: \(error)")
            }
            self.loadFromDB()
        }
    }

    func retryScan(sourceId: String) async {
        guard let orchestration = orchestrationService,
              let sourceRepo,
              let source = try? sourceRepo.fetch(id: sourceId) else {
            return
        }

        isRefreshing = true
        sourceActionMessage = nil
        beginPipeline(.sourceScan, formatted: String(format: L10n.tr("pipeline.scan.retry"), source.displayName), detail: source.id)
        defer {
            isRefreshing = false
            clearPipeline()
        }

        let result = await Task.detached(priority: .userInitiated) {
            orchestration.rescan(source: source, runSecurityScan: false)
        }.value

        orchestrationWarnings = result.errors.map(\.localizedDescription)
        if let firstError = orchestrationWarnings.first {
            setSourceAction(message: String(format: L10n.tr("action.retry.failed"), firstError), failed: true)
        } else {
            setSourceAction(message: String(format: L10n.tr("action.retry.success"), source.displayName), failed: false)
        }

        loadFromDB()
    }

    func retryFailedSources() async {
        guard let orchestration = orchestrationService,
              let sourceRepo else {
            return
        }

        let failedSources = sources.filter { $0.lastScanStatus == "failure" || $0.lastScanStatus == "partialFailure" }
        guard !failedSources.isEmpty else {
            setSourceAction(message: L10n.tr("action.retry.noFailed"), failed: false)
            return
        }

        isRefreshing = true
        sourceActionMessage = nil
        beginPipeline(
            .sourceScan,
            formatted: String(format: L10n.tr("pipeline.retry.batch.start"), failedSources.count),
            detail: String(format: L10n.tr("pipeline.retry.batch.progress"), 0, failedSources.count)
        )
        defer {
            isRefreshing = false
            clearPipeline()
        }

        var errors: [String] = []
        for (index, sourceItem) in failedSources.enumerated() {
            beginPipeline(
                .sourceScan,
                formatted: String(format: L10n.tr("pipeline.scan.retry"), sourceItem.displayName),
                detail: String(format: L10n.tr("pipeline.retry.batch.progress"), index + 1, failedSources.count)
            )

            guard let source = try? sourceRepo.fetch(id: sourceItem.id) else {
                errors.append("[sourceScan] (source: \(sourceItem.id)) \(L10n.tr("action.retry.failed.missingSource"))")
                continue
            }

            let result = await Task.detached(priority: .userInitiated) {
                orchestration.rescan(source: source, runSecurityScan: false)
            }
            .value

            errors.append(contentsOf: result.errors.map { $0.localizedDescription })
        }

        orchestrationWarnings = errors
        if let firstError = errors.first {
            setSourceAction(message: String(format: L10n.tr("action.retry.failed"), firstError), failed: true)
        } else {
            let key = failedSources.count == 1 ? "action.retry.count" : "action.retry.count.plural"
            setSourceAction(message: String(format: L10n.tr(key), failedSources.count), failed: false)
        }

        loadFromDB()
    }

    func copyTargets(for skill: SkillItem) -> [SourceItem] {
        sources.filter {
            $0.id != skill.sourceId &&
            $0.isActive &&
            $0.type.supportsInstallRemove
        }
    }

    func storeInstallTargets() -> [SourceItem] {
        sources
            .filter { $0.isActive && $0.type.supportsInstallRemove }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    struct StoreInstallError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func installStoreSkill(_ item: StoreSkillItem, to targetSourceId: String) async throws {
        guard let service = persistenceService,
              let sourceRepo,
              let targetSource = try? sourceRepo.fetch(id: targetSourceId),
              let adapter = adapter(for: targetSource.type) else {
            throw StoreInstallError(message: L10n.tr("store.install.error.targetMissing"))
        }

        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("skill-store", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let packageURL = tempRoot.appendingPathComponent(item.installSlug, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)

            let manifest: [String: String] = [
                "name": item.name,
                "version": item.version ?? "0.1.0"
            ]
            let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try manifestData.write(to: packageURL.appendingPathComponent("skill.json"))

            let doc = "# \(item.name)\n\n\(item.summary)\n"
            try doc.write(to: packageURL.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

            beginPipeline(
                .syncApply,
                formatted: String(format: L10n.tr("pipeline.store.install.start"), item.name, targetSource.displayName),
                detail: targetSource.id
            )
            defer { clearPipeline() }

            _ = try await Task.detached(priority: .userInitiated) {
                try service.installSkill(
                    packageURL: packageURL,
                    into: targetSource,
                    using: adapter
                )
            }.value

            setSourceAction(message: String(format: L10n.tr("store.install.success"), item.name, targetSource.displayName), failed: false)
            loadFromDB()
        } catch {
            setSourceAction(message: String(format: L10n.tr("store.install.failed"), error.localizedDescription), failed: true)
            throw error
        }

        try? FileManager.default.removeItem(at: tempRoot)
    }

    func copySkill(skillId: String, to targetSourceId: String) async {
        guard let service = persistenceService,
              let sourceRepo,
              let skillRepo,
              let skill = try? skillRepo.fetch(id: skillId),
              let targetSource = try? sourceRepo.fetch(id: targetSourceId),
              let adapter = adapter(for: targetSource.type) else {
            setSourceAction(message: L10n.tr("action.copy.failed.missing"), failed: true)
            return
        }

        beginPipeline(
            .syncApply,
            formatted: String(format: L10n.tr("pipeline.copy.start"), skill.name, targetSource.displayName),
            detail: targetSource.id
        )
        defer { clearPipeline() }

        do {
            _ = try await Task.detached(priority: .userInitiated) {
                try service.installSkill(
                    packageURL: URL(fileURLWithPath: skill.path),
                    into: targetSource,
                    using: adapter
                )
            }.value
            setSourceAction(message: String(format: L10n.tr("action.copy.success"), skill.name, targetSource.displayName), failed: false)
            loadFromDB()
        } catch {
            setSourceAction(message: String(format: L10n.tr("action.copy.failed"), error.localizedDescription), failed: true)
        }
    }

    func moveSources(fromOffsets: IndexSet, toOffset: Int) {
        sources.move(fromOffsets: fromOffsets, toOffset: toOffset)
        let order = sources.map(\.id)
        UserDefaults.standard.set(order, forKey: sourceOrderKey)
    }

    func clearSourceActionMessage() {
        sourceActionMessage = nil
        sourceActionFailed = false
    }

    private func setSourceAction(message: String, failed: Bool) {
        sourceActionMessage = message
        sourceActionFailed = failed
    }

    func deleteSkill(id: String) {
        skills.removeAll { $0.id == id }
        let repo = skillRepo
        Task.detached(priority: .userInitiated) {
            do {
                try repo?.delete(skillId: id)
            } catch {
                print("[AppStore] deleteSkill failed for \(id): \(error)")
            }
        }
    }

    /// Run the full discovery → indexing → security scan pipeline, then reload UI.
    func refreshAll() async {
        isRefreshing = true
        orchestrationWarnings = []
        beginPipeline(.refresh, messageKey: "pipeline.refresh.start")
        defer {
            isRefreshing = false
            clearPipeline()
        }

        guard let orchestration = orchestrationService else {
            // No real DB — just reload mock data after a brief delay.
            try? await Task.sleep(nanoseconds: 600_000_000)
            loadFromDB()
            return
        }

        // Run the pipeline on a background thread.
        let result = await Task.detached(priority: .userInitiated) {
            orchestration.runFullPipeline(runSecurityScan: true)
        }.value

        beginPipeline(.securityScan, messageKey: "pipeline.refresh.security", detail: result.securityReport == nil ? nil : L10n.tr("pipeline.security.completed"))

        // Also rescan persisted active sources that are user-registered and not part of auto-discovery.
        var combinedErrors = result.errors
        if let sourceRepo {
            let discoveredIDs = Set(result.discoveredSources.map(\.id))
            let persistedSources = (try? sourceRepo.fetchActive()) ?? []
            let extraSources = persistedSources.filter { !discoveredIDs.contains($0.id) }

            for source in extraSources {
                let extra = await Task.detached(priority: .userInitiated) {
                    orchestration.rescan(source: source, runSecurityScan: false)
                }.value
                combinedErrors.append(contentsOf: extra.errors)
            }
        }

        // Surface non-fatal errors as warnings.
        orchestrationWarnings = combinedErrors.map(\.localizedDescription)
        if let report = result.securityReport {
            latestSecurityReport = report
        }

        loadFromDB()
    }

    /// Compute a sync plan for the given profile (non-destructive).
    func computeSyncPlan(profileId: String) {
        guard let engine = syncEngine else { return }
        beginPipeline(.syncPlan, messageKey: "pipeline.sync.plan")
        defer {
            if currentPipelineStep == .syncPlan {
                clearPipeline()
            }
        }
        do {
            pendingSyncPlan = try engine.plan(profileId: profileId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Apply the pending sync plan (must be conflict-free).
    func applyPendingSyncPlan() {
        guard let engine = syncEngine, let plan = pendingSyncPlan else { return }
        beginPipeline(.syncApply, messageKey: "pipeline.sync.apply")
        defer {
            if currentPipelineStep == .syncApply {
                clearPipeline()
            }
        }
        do {
            let entries = try engine.apply(plan: plan)
            var newWarnings: [String] = []
            var successCount = 0
            var failCount = 0

            for entry in entries where entry.outcome == .skipped {
                do {
                    switch entry.action {
                    case .install:
                        try applyInstall(entry: entry)
                        successCount += 1
                    case .remove:
                        try applyRemove(entry: entry)
                        successCount += 1
                    case .changeVersion:
                        try applyChangeVersion(entry: entry)
                        successCount += 1
                    case .enable, .disable:
                        newWarnings.append("[sync] '\(entry.action.rawValue)' for '\(entry.skillName)' skipped unexpectedly")
                    }
                } catch {
                    failCount += 1
                    newWarnings.append("[sync] \(entry.action.rawValue) '\(entry.skillName)' failed: \(error.localizedDescription)")
                }
            }

            if successCount > 0 || failCount > 0 {
                let msg = "[sync] \(successCount) filesystem operation(s) completed, \(failCount) failed"
                newWarnings.insert(msg, at: 0)
            }
            orchestrationWarnings.append(contentsOf: newWarnings)
            pendingSyncPlan = nil
            loadFromDB()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func applyInstall(entry: SyncAuditEntry) throws {
        guard let service = persistenceService,
              let sourceRepo,
              let skillRepo,
              let targetSource = try? sourceRepo.fetch(id: entry.sourceId),
              let adpt = adapter(for: targetSource.type) else {
            throw SyncApplyError(message: "Cannot resolve target source for install: \(entry.sourceId)")
        }
        // Find an existing skill with this name in any other source to use as packageURL.
        let allSkills = (try? skillRepo.fetchAll()) ?? []
        guard let existing = allSkills.first(where: { $0.name == entry.skillName && $0.sourceId != entry.sourceId }) else {
            throw SyncApplyError(message: "No source skill found to install '\(entry.skillName)' from")
        }
        let packageURL = URL(fileURLWithPath: existing.path)
        _ = try service.installSkill(packageURL: packageURL, into: targetSource, using: adpt)
    }

    private func applyRemove(entry: SyncAuditEntry) throws {
        guard let service = persistenceService,
              let skillRepo else {
            throw SyncApplyError(message: "Persistence service unavailable")
        }
        let allSkills = (try? skillRepo.fetchAll()) ?? []
        guard let target = allSkills.first(where: { $0.name == entry.skillName && $0.sourceId == entry.sourceId }),
              let sourceType = SkillSourceType(rawValue: target.sourceType),
              let adpt = adapter(for: sourceType) else {
            throw SyncApplyError(message: "Cannot find skill '\(entry.skillName)' in source '\(entry.sourceId)' for removal")
        }
        try service.removeSkill(skillId: target.id, using: adpt)
    }

    private func applyChangeVersion(entry: SyncAuditEntry) throws {
        guard let service = persistenceService,
              let skillRepo else {
            throw SyncApplyError(message: "Persistence service unavailable")
        }
        let allSkills = (try? skillRepo.fetchAll()) ?? []
        guard let target = allSkills.first(where: { $0.name == entry.skillName && $0.sourceId == entry.sourceId }),
              let sourceType = SkillSourceType(rawValue: target.sourceType),
              let adpt = adapter(for: sourceType) else {
            throw SyncApplyError(message: "Cannot find skill '\(entry.skillName)' for version change")
        }
        // Use the skill's current path as the package URL (re-scans in place).
        // A proper implementation would download/locate the target version first.
        let newPackageURL = URL(fileURLWithPath: target.path)
        _ = try service.changeSkillVersion(skillId: target.id, to: newPackageURL, using: adpt)
    }

    private struct SyncApplyError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Dismiss the pending sync plan without applying it.
    func dismissSyncPlan() {
        pendingSyncPlan = nil
    }

    /// Run a security scan over the current inventory.
    func runSecurityScan() async {
        guard let security = securityService else { return }
        beginPipeline(.securityScan, messageKey: "pipeline.refresh.security")
        defer {
            if currentPipelineStep == .securityScan {
                clearPipeline()
            }
        }
        let report = await Task.detached(priority: .userInitiated) {
            try? security.runScan()
        }.value
        latestSecurityReport = report
        currentPipelineDetail = report == nil ? nil : L10n.tr("pipeline.security.completed")
    }
}

// MARK: - Sample / Preview data

extension SkillSource {
    static var sampleSources: [SkillSource] {
        [
            SkillSource(
                id: "claude-code::/Users/demo/.claude",
                type: .claudeCode,
                rootPath: URL(fileURLWithPath: "/Users/demo/.claude"),
                displayName: "Claude Code (Global)",
                origin: .discovered
            ),
            SkillSource(
                id: "project::/Users/demo/Projects/my-app/.claude",
                type: .project,
                rootPath: URL(fileURLWithPath: "/Users/demo/Projects/my-app/.claude"),
                displayName: "my-app",
                origin: .discovered
            ),
            SkillSource(
                id: "openclaw::/Users/demo/.openclaw",
                type: .openClaw,
                rootPath: URL(fileURLWithPath: "/Users/demo/.openclaw"),
                displayName: "OpenClaw (Global)",
                origin: .discovered
            )
        ]
    }
}

extension SkillItem {
    static var sampleSkills: [SkillItem] {
        let cc = "claude-code::/Users/demo/.claude"
        let proj = "project::/Users/demo/Projects/my-app/.claude"
        let oc = "openclaw::/Users/demo/.openclaw"
        return [
            SkillItem(id: "\(cc)::commit", name: "commit", version: "1.2.0", sourceId: cc, sourceType: .claudeCode, sourceName: "Claude Code (Global)", isEnabled: true, path: "/Users/demo/.claude/skills/commit", indexedAt: Date(), primaryDocumentPath: nil, skillDocumentPath: nil, readmePath: nil, manifestPath: nil, fileCount: nil, lastModified: nil, tags: [], metadata: [:]),
            SkillItem(id: "\(cc)::review-pr", name: "review-pr", version: "2.0.1", sourceId: cc, sourceType: .claudeCode, sourceName: "Claude Code (Global)", isEnabled: true, path: "/Users/demo/.claude/skills/review-pr", indexedAt: Date(), primaryDocumentPath: nil, skillDocumentPath: nil, readmePath: nil, manifestPath: nil, fileCount: nil, lastModified: nil, tags: [], metadata: [:]),
            SkillItem(id: "\(cc)::debug", name: "debug", version: "1.0.0", sourceId: cc, sourceType: .claudeCode, sourceName: "Claude Code (Global)", isEnabled: false, path: "/Users/demo/.claude/skills/debug", indexedAt: Date(), primaryDocumentPath: nil, skillDocumentPath: nil, readmePath: nil, manifestPath: nil, fileCount: nil, lastModified: nil, tags: [], metadata: [:]),
            SkillItem(id: "\(cc)::test-runner", name: "test-runner", version: nil, sourceId: cc, sourceType: .claudeCode, sourceName: "Claude Code (Global)", isEnabled: true, path: "/Users/demo/.claude/skills/test-runner", indexedAt: Date(), primaryDocumentPath: nil, skillDocumentPath: nil, readmePath: nil, manifestPath: nil, fileCount: nil, lastModified: nil, tags: [], metadata: [:]),
            SkillItem(id: "\(proj)::deploy", name: "deploy", version: "0.3.0", sourceId: proj, sourceType: .project, sourceName: "my-app", isEnabled: true, path: "/Users/demo/Projects/my-app/.claude/skills/deploy", indexedAt: Date(), primaryDocumentPath: nil, skillDocumentPath: nil, readmePath: nil, manifestPath: nil, fileCount: nil, lastModified: nil, tags: [], metadata: [:]),
            SkillItem(id: "\(proj)::seed-db", name: "seed-db", version: nil, sourceId: proj, sourceType: .project, sourceName: "my-app", isEnabled: false, path: "/Users/demo/Projects/my-app/.claude/skills/seed-db", indexedAt: Date(), primaryDocumentPath: nil, skillDocumentPath: nil, readmePath: nil, manifestPath: nil, fileCount: nil, lastModified: nil, tags: [], metadata: [:]),
            SkillItem(id: "\(oc)::format", name: "format", version: "3.1.0", sourceId: oc, sourceType: .openClaw, sourceName: "OpenClaw (Global)", isEnabled: true, path: "/Users/demo/.openclaw/skills/format", indexedAt: Date(), primaryDocumentPath: nil, skillDocumentPath: nil, readmePath: nil, manifestPath: nil, fileCount: nil, lastModified: nil, tags: [], metadata: [:]),
            SkillItem(id: "\(oc)::lint", name: "lint", version: "1.5.2", sourceId: oc, sourceType: .openClaw, sourceName: "OpenClaw (Global)", isEnabled: true, path: "/Users/demo/.openclaw/skills/lint", indexedAt: Date(), primaryDocumentPath: nil, skillDocumentPath: nil, readmePath: nil, manifestPath: nil, fileCount: nil, lastModified: nil, tags: [], metadata: [:]),
        ]
    }
}

extension SourceItem {
    static var sampleSources: [SourceItem] {
        [
            SourceItem(id: "claude-code::/Users/demo/.claude", type: .claudeCode, displayName: "Claude Code (Global)", rootPath: "/Users/demo/.claude", isActive: true, lastScanAt: Date(), lastScanStatus: "success", lastScanError: nil, skillCount: 4),
            SourceItem(id: "project::/Users/demo/Projects/my-app/.claude", type: .project, displayName: "my-app", rootPath: "/Users/demo/Projects/my-app/.claude", isActive: true, lastScanAt: Date(), lastScanStatus: "success", lastScanError: nil, skillCount: 2),
            SourceItem(id: "openclaw::/Users/demo/.openclaw", type: .openClaw, displayName: "OpenClaw (Global)", rootPath: "/Users/demo/.openclaw", isActive: true, lastScanAt: nil, lastScanStatus: nil, lastScanError: nil, skillCount: 2),
        ]
    }
}
