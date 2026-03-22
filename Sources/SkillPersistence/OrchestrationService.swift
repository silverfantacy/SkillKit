import Foundation
import SourceDiscovery

/// The result of a full end-to-end orchestration run.
public struct OrchestrationResult {
    /// Sources discovered and indexed.
    public let discoveredSources: [SkillSource]
    /// Scan results per source.
    public let scanResults: [SourceScanResult]
    /// Total number of skills indexed across all sources.
    public let indexedSkillCount: Int
    /// Security report from the post-scan security pass, or nil if skipped.
    public let securityReport: SecurityReport?
    /// Any non-fatal errors that occurred during discovery or indexing.
    public let errors: [OrchestrationError]

    public var hasErrors: Bool { !errors.isEmpty }
}

/// A non-fatal error surfaced during orchestration.
public struct OrchestrationError: Error {
    public enum Stage: String {
        case discovery
        case indexing
        case securityScan
    }

    public let stage: Stage
    public let sourceId: String?
    public let underlying: Error

    public var localizedDescription: String {
        let loc = sourceId.map { " (source: \($0))" } ?? ""
        return "[\(stage.rawValue)]\(loc) \(underlying.localizedDescription)"
    }
}

/// Wires source discovery, inventory indexing, and security scanning into a
/// single end-to-end pipeline.  Each stage is best-effort: failures are
/// collected and returned rather than aborting the whole run.
public final class OrchestrationService {
    private let discoveryService: SourceDiscoveryService
    private let persistenceService: InventoryPersistenceService
    private let securityService: SecurityService?

    public init(
        discoveryService: SourceDiscoveryService,
        persistenceService: InventoryPersistenceService,
        securityService: SecurityService? = nil
    ) {
        self.discoveryService = discoveryService
        self.persistenceService = persistenceService
        self.securityService = securityService
    }

    // MARK: - Full pipeline

    /// Run the full pipeline:
    /// 1. Discover sources using the provided detection context.
    /// 2. Scan each discovered source and persist results.
    /// 3. Optionally run a security scan over the updated inventory.
    ///
    /// - Parameters:
    ///   - detectionContext: Environment hints for source discovery.
    ///   - scanContext:  File-system and timestamp context for scanning.
    ///   - runSecurityScan: Whether to run the security scan stage.
    /// - Returns: An `OrchestrationResult` summarising all stages.
    @discardableResult
    public func runFullPipeline(
        detectionContext: SourceDetectionContext = SourceDetectionContext(),
        scanContext: SourceScanContext = SourceScanContext(),
        runSecurityScan: Bool = true
    ) -> OrchestrationResult {
        var errors: [OrchestrationError] = []

        // Stage 1: Discover sources
        let sources = discoveryService.detectSources(context: detectionContext)

        // Stage 2: Register discovered sources (idempotent)
        for source in sources {
            do {
                try persistenceService.registerSource(source)
            } catch {
                errors.append(OrchestrationError(stage: .discovery, sourceId: source.id, underlying: error))
            }
        }

        // Stage 3: Scan and index each source
        let scanResults = discoveryService.scan(sources: sources, context: scanContext)
        var indexedCount = 0
        for result in scanResults {
            do {
                try persistenceService.apply(scanResult: result)
                indexedCount += result.skills.count
            } catch {
                errors.append(OrchestrationError(stage: .indexing, sourceId: result.source.id, underlying: error))
            }
        }

        // Stage 4: Security scan (optional, over the full updated inventory)
        var securityReport: SecurityReport?
        if runSecurityScan, let secService = securityService {
            do {
                securityReport = try secService.runScan()
            } catch {
                errors.append(OrchestrationError(stage: .securityScan, sourceId: nil, underlying: error))
            }
        }

        return OrchestrationResult(
            discoveredSources: sources,
            scanResults: scanResults,
            indexedSkillCount: indexedCount,
            securityReport: securityReport,
            errors: errors
        )
    }

    // MARK: - Incremental: re-scan a single source

    /// Re-scan a single already-registered source and update the inventory.
    /// Also runs an optional targeted security scan for that source afterwards.
    @discardableResult
    public func rescan(
        source: SkillSource,
        scanContext: SourceScanContext = SourceScanContext(),
        runSecurityScan: Bool = true
    ) -> OrchestrationResult {
        var errors: [OrchestrationError] = []

        let result = discoveryService.scan(source: source, context: scanContext)
        var indexedCount = 0
        do {
            try persistenceService.apply(scanResult: result)
            indexedCount = result.skills.count
        } catch {
            errors.append(OrchestrationError(stage: .indexing, sourceId: source.id, underlying: error))
        }

        var securityReport: SecurityReport?
        if runSecurityScan, let secService = securityService {
            do {
                securityReport = try secService.runScan(sourceId: source.id)
            } catch {
                errors.append(OrchestrationError(stage: .securityScan, sourceId: source.id, underlying: error))
            }
        }

        return OrchestrationResult(
            discoveredSources: [source],
            scanResults: [result],
            indexedSkillCount: indexedCount,
            securityReport: securityReport,
            errors: errors
        )
    }
}
