import SwiftUI
import SourceDiscovery

// MARK: - SkillSourceType + UI

extension SkillSourceType {
    var icon: String {
        switch self {
        case .claudeCode: return "terminal.fill"
        case .openClaw: return "bolt.shield.fill"
        case .project: return "hammer.fill"
        }
    }

    var color: Color {
        switch self {
        case .claudeCode: return .orange
        case .openClaw: return .purple
        case .project: return .blue
        }
    }

    var localizedDisplayName: String {
        switch self {
        case .claudeCode: return L10n.tr("source.type.claude")
        case .openClaw: return L10n.tr("source.type.openclaw")
        case .project: return L10n.tr("source.type.workspace")
        }
    }

}

// MARK: - AppStore preview helper

extension AppStore {
    @MainActor
    static var preview: AppStore {
        let store = AppStore()
        // Overwrite with deterministic sample data regardless of DB state.
        store.skills = SkillItem.sampleSkills
        store.sources = SourceItem.sampleSources
        return store
    }
}
