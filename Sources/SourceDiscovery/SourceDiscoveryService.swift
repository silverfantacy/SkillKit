import Foundation

public final class SourceDiscoveryService {
    private let adapters: [SkillSourceType: SourceAdapter]
    private let scanner: SkillScanner

    public init(adapters: [SourceAdapter], scanner: SkillScanner = SkillScanner()) {
        var adapterMap: [SkillSourceType: SourceAdapter] = [:]
        for adapter in adapters {
            adapterMap[adapter.type] = adapter
        }
        self.adapters = adapterMap
        self.scanner = scanner
    }

    public func detectSources(context: SourceDetectionContext) -> [SkillSource] {
        var discovered: [SkillSource] = []
        for adapter in adapters.values {
            discovered.append(contentsOf: adapter.detectSources(context: context))
        }
        return Array(Set(discovered))
    }

    public func scan(source: SkillSource, context: SourceScanContext) -> SourceScanResult {
        guard let adapter = adapters[source.type] else {
            let error = SourceScanError(
                code: .adapterMissing,
                message: "No adapter registered for source type \(source.type.rawValue).",
                path: source.rootPath
            )
            return SourceScanResult(source: source, skills: [], errors: [error], scannedAt: context.now)
        }
        return adapter.scan(source: source, context: context)
    }

    public func scan(sources: [SkillSource], context: SourceScanContext) -> [SourceScanResult] {
        sources.map { scan(source: $0, context: context) }
    }

    public func discoverAndScan(
        detectionContext: SourceDetectionContext,
        scanContext: SourceScanContext
    ) -> [SourceScanResult] {
        let sources = detectSources(context: detectionContext)
        return scan(sources: sources, context: scanContext)
    }
}
