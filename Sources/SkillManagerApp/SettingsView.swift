import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label(L10n.tr("settings.general"), systemImage: "gearshape") }
            GitBackupSettingsView()
                .environmentObject(store)
                .tabItem { Label(L10n.tr("settings.gitBackup.tab"), systemImage: "externaldrive.badge.timemachine") }
        }
        .frame(minWidth: 560, minHeight: 360)
    }
}

private struct GitBackupSettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var remoteURL: String = ""
    @State private var isInitializing = false

    var body: some View {
        Form {
            Section(L10n.tr("settings.gitBackup.remote")) {
                TextField(L10n.tr("settings.gitBackup.remoteURL"), text: $remoteURL)
                    .textFieldStyle(.roundedBorder)
                    .onAppear {
                        remoteURL = store.gitBackupSettings?.remoteURL ?? ""
                    }

                Button {
                    guard !remoteURL.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    isInitializing = true
                    Task {
                        await store.initializeBackupRepo(remoteURL: remoteURL)
                        isInitializing = false
                    }
                } label: {
                    if isInitializing {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Text(L10n.tr("settings.gitBackup.init"))
                    }
                }
                .disabled(remoteURL.trimmingCharacters(in: .whitespaces).isEmpty || isInitializing)

                Text(L10n.tr("settings.gitBackup.hint"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let settings = store.gitBackupSettings {
                Section(L10n.tr("settings.gitBackup.status")) {
                    LabeledContent(L10n.tr("settings.gitBackup.repoPath"), value: settings.localRepoPath)
                        .font(.callout)

                    if let lastSync = settings.lastSyncAt {
                        LabeledContent(L10n.tr("settings.gitBackup.lastSync"),
                                       value: lastSync.formatted(date: .abbreviated, time: .shortened))
                    }

                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusLabel)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 280)
    }

    private var statusColor: Color {
        switch store.gitBackupStatus {
        case .idle: return .secondary
        case .success: return .green
        case .failed: return .red
        }
    }

    private var statusLabel: String {
        switch store.gitBackupStatus {
        case .idle: return L10n.tr("settings.gitBackup.status.idle")
        case .success: return L10n.tr("settings.gitBackup.status.success")
        case .failed: return L10n.tr("settings.gitBackup.status.failed")
        }
    }
}

private struct GeneralSettingsView: View {
    @AppStorage(L10n.languageKey) private var appLanguage = "zh-Hant"
    @AppStorage(AppStore.featureSkillStoreEntryKey) private var enableSkillStoreEntry = false

    var body: some View {
        Form {
            Section(L10n.tr("settings.language.title")) {
                Picker(L10n.tr("settings.language.picker"), selection: $appLanguage) {
                    Text(L10n.tr("settings.language.system")).tag("system")
                    Text(L10n.tr("settings.language.zhHant")).tag("zh-Hant")
                    Text(L10n.tr("settings.language.en")).tag("en")
                }
                .pickerStyle(.menu)

                Text(L10n.tr("settings.language.applies"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(L10n.tr("settings.other.title")) {
                Toggle(L10n.tr("settings.skillStoreToggle"), isOn: $enableSkillStoreEntry)

                Text(L10n.tr("settings.skillStoreHint"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, minHeight: 260)
    }
}
