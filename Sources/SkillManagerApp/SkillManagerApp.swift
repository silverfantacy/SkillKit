import SwiftUI

@main
struct SkillManagerApp: App {
    @StateObject private var store = AppStore()
    @AppStorage(L10n.languageKey) private var appLanguage = "zh-Hant"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .id(appLanguage)
                .frame(minWidth: 760, minHeight: 560)
        }
        .defaultSize(width: 1160, height: 760)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button(L10n.tr("toolbar.refresh")) {
                    Task { await store.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .id(appLanguage)
        }
    }
}
