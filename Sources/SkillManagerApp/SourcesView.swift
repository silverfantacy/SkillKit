import SwiftUI
import SourceDiscovery

struct SourcesView: View {
    @EnvironmentObject var store: AppStore
    @State private var showAddSheet = false
    @State private var sourceToDelete: SourceItem?

    private var failedSourceCount: Int {
        store.sources.filter { $0.lastScanStatus == "failure" || $0.lastScanStatus == "partialFailure" }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            statusBanner

            if store.isRefreshing && store.sources.isEmpty {
                loadingState
            } else if store.sources.isEmpty {
                emptyState
            } else {
                sourceList
            }
        }
        .navigationTitle(L10n.tr("sources.title"))
        .sheet(isPresented: $showAddSheet) {
            AddSourceSheet()
                .environmentObject(store)
        }
        .confirmationDialog(
            L10n.tr("sources.remove.title"),
            isPresented: Binding(
                get: { sourceToDelete != nil },
                set: { if !$0 { sourceToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: sourceToDelete
        ) { source in
            Button(L10n.tr("sources.remove.confirm"), role: .destructive) {
                store.deleteSource(id: source.id)
                sourceToDelete = nil
            }
            Button(L10n.tr("common.cancel"), role: .cancel) { sourceToDelete = nil }
        } message: { source in
            Text(String(format: L10n.tr("sources.remove.message"), source.displayName))
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Text(store.sources.count == 1
                 ? String(format: L10n.tr("sources.count"), store.sources.count)
                 : String(format: L10n.tr("sources.count.plural"), store.sources.count))
                .foregroundStyle(.secondary)
                .font(.body)

            if failedSourceCount > 0 {
                Text(String(format: L10n.tr("sources.failed"), failedSourceCount))
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.14)))
            }

            Spacer()

            Button {
                Task { await store.retryFailedSources() }
            } label: {
                Label(L10n.tr("sources.toolbar.retry"), systemImage: "arrow.clockwise.circle")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(failedSourceCount == 0 || store.isRefreshing)

            Text(L10n.tr("sources.toolbar.reorderHint"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                showAddSheet = true
            } label: {
                Label(L10n.tr("sources.toolbar.add"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("n", modifiers: [.command])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var statusBanner: some View {
        VStack(spacing: 0) {
            if let msg = store.sourceActionMessage, !store.isRefreshing {
                let isFailed = store.sourceActionFailed
                bannerRow(
                    text: msg,
                    color: isFailed ? .red : .green,
                    systemImage: isFailed ? "exclamationmark.triangle" : "checkmark.circle"
                )
            } else if let warning = store.orchestrationWarnings.first {
                bannerRow(text: warning, color: .orange, systemImage: "exclamationmark.triangle")
            }
        }
        .animation(.easeInOut(duration: 0.18), value: store.isRefreshing)
        .animation(.easeInOut(duration: 0.18), value: store.sourceActionMessage)
        .animation(.easeInOut(duration: 0.18), value: store.orchestrationWarnings)
    }

    private func bannerRow(text: String, color: Color, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(text)
                .font(.body)
                .lineLimit(2)
                .foregroundStyle(.primary)
            Spacer()
            Button(L10n.tr("sources.banner.dismiss")) {
                store.clearSourceActionMessage()
                store.orchestrationWarnings = []
            }
            .font(.footnote)
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Source list

    private var sourceList: some View {
        List {
            ForEach(store.sources) { source in
                SourceRowView(
                    source: source,
                    onRetry: {
                        Task { await store.retryScan(sourceId: source.id) }
                    },
                    onDelete: {
                        sourceToDelete = source
                    }
                )
            }
            .onMove(perform: store.moveSources)
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - States

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L10n.tr("sources.loading"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            VStack(spacing: 6) {
                Text(L10n.tr("sources.empty.title"))
                    .font(.headline)
                Text(L10n.tr("sources.empty.subtitle"))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(L10n.tr("sources.empty.add")) { showAddSheet = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - SourceRowView

struct SourceRowView: View {
    let source: SourceItem
    let onRetry: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(source.type.color.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: source.type.icon)
                    .foregroundStyle(source.type.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(source.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                    SourceTypeBadge(type: source.type)
                }
                Text(source.rootPath)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let err = source.lastScanError, !err.isEmpty {
                    Text(err)
                        .font(.body)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(source.skillCount == 1
                     ? String(format: L10n.tr("sources.skills.count"), source.skillCount)
                     : String(format: L10n.tr("sources.skills.count.plural"), source.skillCount))
                    .font(.body)
                    .foregroundStyle(.secondary)

                scanStatusView
            }

            if source.lastScanStatus == nil || source.lastScanStatus == "failure" || source.lastScanStatus == "partialFailure" {
                Button {
                    onRetry()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help(source.lastScanStatus == nil ? L10n.tr("sources.scan.now.help") : L10n.tr("sources.scan.retry.help"))
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red.opacity(0.8))
            }
            .buttonStyle(.plain)
            .help(L10n.tr("sources.scan.remove.help"))
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var scanStatusView: some View {
        if let status = source.lastScanStatus {
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor(status))
                    .frame(width: 6, height: 6)
                Text(statusText(status))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let lastScanAt = source.lastScanAt {
                Text(lastScanAt, style: .relative)
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        } else {
            Text(L10n.tr("sources.scan.notScanned"))
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "success": return .green
        case "partialFailure": return .orange
        case "failure": return .red
        default: return .secondary
        }
    }

    private func statusText(_ status: String) -> String {
        switch status {
        case "success": return L10n.tr("sources.scan.success")
        case "partialFailure": return L10n.tr("sources.scan.partial")
        case "failure": return L10n.tr("sources.scan.failure")
        default: return status.capitalized
        }
    }
}

// MARK: - SourceTypeBadge

struct SourceTypeBadge: View {
    let type: SkillSourceType

    var body: some View {
        Text(type.localizedDisplayName)
            .font(.footnote)
            .fontWeight(.medium)
            .foregroundStyle(type.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(type.color.opacity(0.12)))
    }
}

// MARK: - AddSourceSheet

struct AddSourceSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: SkillSourceType = .claudeCode
    @State private var displayName = ""
    @State private var rootPath = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(L10n.tr("addsource.title"))
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(L10n.tr("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            Divider()

            // Form
            Form {
                Picker(L10n.tr("addsource.type"), selection: $selectedType) {
                    ForEach(SkillSourceType.allCases, id: \.self) { type in
                        Label(type.localizedDisplayName, systemImage: type.icon).tag(type)
                    }
                }
                .onChange(of: selectedType) { newType in
                    if newType != .project {
                        rootPath = defaultPath(for: newType)
                    }
                }

                TextField(L10n.tr("addsource.name"), text: $displayName, prompt: Text(selectedType.localizedDisplayName))

                HStack {
                    TextField(L10n.tr("addsource.path"), text: $rootPath, prompt: Text(defaultPath(for: selectedType)))
                    Button(L10n.tr("addsource.browse")) { pickFolder() }
                        .buttonStyle(.bordered)
                }

                Text(sourceTypeHint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .onAppear {
                if selectedType != .project {
                    rootPath = defaultPath(for: selectedType)
                }
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button(L10n.tr("addsource.add")) { addSource() }
                    .buttonStyle(.borderedProminent)
                    .disabled(rootPath.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 480)
    }

    private func defaultPath(for type: SkillSourceType) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch type {
        case .claudeCode: return "\(home)/.claude/skills"
        case .openClaw: return "\(home)/.openclaw/skills"
        case .project: return ""
        }
    }

    private var sourceTypeHint: String {
        switch selectedType {
        case .claudeCode: return L10n.tr("addsource.claudecode.hint")
        case .openClaw: return L10n.tr("addsource.openclaw.hint")
        case .project: return L10n.tr("addsource.project.hint")
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = L10n.tr("addsource.browse")
        if panel.runModal() == .OK, let url = panel.url {
            rootPath = url.path
            if displayName.isEmpty {
                displayName = url.lastPathComponent
            }
        }
    }

    private func addSource() {
        let expandedPath = (rootPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        let source = SkillSource(
            type: selectedType,
            rootPath: url,
            displayName: displayName.isEmpty ? selectedType.localizedDisplayName : displayName,
            origin: .userRegistered
        )
        store.addSource(source)
        dismiss()
    }
}

// MARK: - Preview

#Preview("Sources") {
    SourcesView()
        .environmentObject(AppStore.preview)
        .frame(width: 700, height: 500)
}

#Preview("Add Source Sheet") {
    AddSourceSheet()
        .environmentObject(AppStore.preview)
}
