import SwiftUI
import SourceDiscovery

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedTab: Tab = .skills
    @State private var showSaveScenarioSheet = false
    @State private var applyScenarioCandidate: ScenarioItem? = nil

    enum Tab: String, CaseIterable {
        case skills
        case sources
        case skillStore

        var title: String {
            switch self {
            case .skills: return L10n.tr("nav.skills")
            case .sources: return L10n.tr("nav.sources")
            case .skillStore: return L10n.tr("nav.skillStore")
            }
        }

        var icon: String {
            switch self {
            case .skills: return "shippingbox.fill"
            case .sources: return "folder.fill.badge.gearshape"
            case .skillStore: return "bag.fill"
            }
        }

        static func availableTabs(skillStoreEnabled: Bool) -> [Tab] {
            skillStoreEnabled ? [.skills, .sources, .skillStore] : [.skills, .sources]
        }
    }

    var body: some View {
        HSplitView {
            sidebarPane

            VStack(spacing: 0) {
                Group {
                    switch selectedTab {
                    case .skills:
                        SkillListView()
                            .environmentObject(store)
                    case .sources:
                        SourcesView()
                            .environmentObject(store)
                    case .skillStore:
                        SkillStoreEntryView()
                            .environmentObject(store)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                pipelineStatusBar
                    .animation(.easeInOut(duration: 0.2), value: store.currentPipelineStep)
            }
            .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 800, minHeight: 560)
        .onAppear {
            ensureValidSelectedTab()
        }
        .onChange(of: store.isSkillStoreEntryEnabled) { _ in
            ensureValidSelectedTab()
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if store.isRefreshing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .help(L10n.tr("toolbar.refreshing.help"))
                } else {
                    Button {
                        Task { await store.refreshAll() }
                    } label: {
                        Label(L10n.tr("toolbar.refresh"), systemImage: "arrow.clockwise")
                    }
                    .help(L10n.tr("toolbar.refresh.help"))
                }
            }
        }
    }

    @ViewBuilder
    private var pipelineStatusBar: some View {
        if let message = store.currentPipelineMessage,
           store.currentPipelineStep != .idle {
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.65)
                        .frame(width: 16, height: 16)

                    Text(pipelineStepLabel(for: store.currentPipelineStep))
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let detail = store.currentPipelineDetail, !detail.isEmpty {
                        Text("–")
                            .foregroundStyle(.tertiary)
                        Text(detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(.bar)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func pipelineStepLabel(for step: PipelineStep) -> String {
        switch step {
        case .idle: return L10n.tr("pipeline.step.idle")
        case .refresh: return L10n.tr("pipeline.step.refresh")
        case .sourceScan: return L10n.tr("pipeline.step.sourceScan")
        case .syncPlan: return L10n.tr("pipeline.step.syncPlan")
        case .syncApply: return L10n.tr("pipeline.step.syncApply")
        case .securityScan: return L10n.tr("pipeline.step.securityScan")
        }
    }

    private func ensureValidSelectedTab() {
        if selectedTab == .skillStore, !store.isSkillStoreEntryEnabled {
            selectedTab = .skills
        }
    }

    private var sidebarPane: some View {
        List {
            Section(L10n.tr("nav.section.view")) {
                ForEach(Tab.availableTabs(skillStoreEnabled: store.isSkillStoreEntryEnabled), id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 10) {
                            Label(tab.title, systemImage: tab.icon)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if selectedTab == tab {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? Color.accentColor.opacity(0.12) : .clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                }
            }

            Section(L10n.tr("nav.section.sources")) {
                if store.isRefreshing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.55)
                            .frame(width: 14, height: 14)
                        Text(L10n.tr("nav.sources.refreshing"))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                }

                Button {
                    store.filterSourceId = nil
                    selectedTab = .skills
                } label: {
                    HStack(spacing: 10) {
                        Label(L10n.tr("nav.allSources"), systemImage: "line.3.horizontal.decrease.circle")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if store.filterSourceId == nil {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(store.filterSourceId == nil ? Color.accentColor.opacity(0.12) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))

                ForEach(store.sources) { source in
                    Button {
                        store.filterSourceId = source.id
                        selectedTab = .skills
                    } label: {
                        SourceSidebarRow(source: source, isSelected: store.filterSourceId == source.id)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(store.filterSourceId == source.id ? Color.accentColor.opacity(0.12) : .clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                }
            }
            if !store.scenarios.isEmpty {
                Section(L10n.tr("nav.section.scenarios")) {
                    ForEach(store.scenarios) { scenario in
                        Button {
                            applyScenarioCandidate = scenario
                        } label: {
                            HStack(spacing: 10) {
                                Label(scenario.name, systemImage: "theatermasks")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if store.activeScenarioId == scenario.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(store.activeScenarioId == scenario.id ? Color.accentColor.opacity(0.12) : .clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                        .contextMenu {
                            Button(L10n.tr("scenario.delete"), role: .destructive) {
                                store.deleteScenario(id: scenario.id)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 260, idealWidth: 300, maxWidth: 340, maxHeight: .infinity)
        .navigationTitle(L10n.tr("nav.title"))
        .confirmationDialog(
            applyScenarioCandidate.map { String(format: L10n.tr("scenario.apply.confirm"), $0.name) } ?? "",
            isPresented: Binding(get: { applyScenarioCandidate != nil }, set: { if !$0 { applyScenarioCandidate = nil } }),
            titleVisibility: .visible
        ) {
            if let scenario = applyScenarioCandidate {
                Button(L10n.tr("scenario.apply")) {
                    store.applyScenario(id: scenario.id)
                    applyScenarioCandidate = nil
                }
                Button(L10n.tr("common.cancel"), role: .cancel) {
                    applyScenarioCandidate = nil
                }
            }
        } message: {
            Text(L10n.tr("scenario.apply.message"))
        }
        .sheet(isPresented: $showSaveScenarioSheet) {
            SaveScenarioSheet()
                .environmentObject(store)
        }
    }
}

struct SaveScenarioSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.tr("scenario.save.title"))
                .font(.headline)

            TextField(L10n.tr("scenario.save.name"), text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { save() }

            Text(String(format: L10n.tr("scenario.save.hint"), store.skills.filter(\.isEnabled).count))
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button(L10n.tr("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.tr("scenario.save.confirm")) { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 340)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        store.saveCurrentAsScenario(name: trimmed)
        dismiss()
    }
}

private struct SkillStoreEntryView: View {
    @EnvironmentObject var store: AppStore
    @State private var catalogItems: [StoreSkillItem] = []
    @State private var installCandidate: StoreSkillItem?

    private let catalogService = StoreCatalogService(adapters: [MockSkillStoreAdapter()])

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("store.entry.title"))
                .font(.title2)
                .fontWeight(.semibold)

            Text(L10n.tr("store.entry.description"))
                .foregroundStyle(.secondary)

            if catalogItems.isEmpty {
                Text(L10n.tr("store.entry.empty"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
                List(catalogItems) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(item.name)
                                .font(.headline)
                            Spacer()
                            if let version = item.version {
                                Text(version)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(item.summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.shield")
                                    .font(.caption2)
                                Text(String(format: L10n.tr("store.entry.provider"), item.providerDisplayName))
                                    .font(.caption)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.secondary.opacity(0.12))
                            )
                            .foregroundStyle(.secondary)

                        HStack {
                            Spacer()
                            Button {
                                installCandidate = item
                            } label: {
                                Label(L10n.tr("store.entry.install"), systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
                .frame(maxHeight: 320)
            }

            Text(L10n.tr("store.entry.installHint"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            catalogItems = catalogService.listItems()
        }
        .sheet(item: $installCandidate) { item in
            StoreInstallSheet(item: item)
                .environmentObject(store)
        }
    }
}

private struct StoreInstallSheet: View {
    let item: StoreSkillItem

    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTargetId: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var safetyConfirmed = false

    private var targets: [SourceItem] {
        store.storeInstallTargets()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(format: L10n.tr("store.install.title"), item.name))
                .font(.headline)

            if targets.isEmpty {
                Text(L10n.tr("store.install.noTargets"))
                    .foregroundStyle(.secondary)
            } else {
                Picker(L10n.tr("store.install.target"), selection: $selectedTargetId) {
                    ForEach(targets) { target in
                        Text("\(target.displayName) (\(target.type.localizedDisplayName))").tag(target.id)
                    }
                }
                .pickerStyle(.menu)
                .onAppear {
                    if selectedTargetId.isEmpty {
                        selectedTargetId = targets.first?.id ?? ""
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Text(L10n.tr("store.install.warning"))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Toggle(L10n.tr("store.install.confirm"), isOn: $safetyConfirmed)
                .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button(L10n.tr("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.tr("store.entry.install")) {
                    guard !selectedTargetId.isEmpty else { return }
                    isSubmitting = true
                    errorMessage = nil
                    Task {
                        do {
                            try await store.installStoreSkill(item, to: selectedTargetId)
                            isSubmitting = false
                            dismiss()
                        } catch {
                            isSubmitting = false
                            errorMessage = String(format: L10n.tr("store.install.failed"), error.localizedDescription)
                        }
                    }
                }
                .disabled(selectedTargetId.isEmpty || isSubmitting || !safetyConfirmed)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }
}

private struct SourceSidebarRow: View {
    let source: SourceItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: source.type.icon)
                .foregroundStyle(source.type.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(source.skillCount)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

#Preview {
    ContentView()
        .environmentObject(AppStore.preview)
        .frame(width: 1200, height: 780)
}
