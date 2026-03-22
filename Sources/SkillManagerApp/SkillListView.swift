import SwiftUI
import SourceDiscovery

struct SkillListView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedSkillId: String?
    @State private var compactPane: CompactPane = .list
    @State private var showSaveScenarioSheet = false

    private enum CompactPane: CaseIterable, Identifiable {
        case list
        case detail

        var id: Self { self }

        var title: String {
            switch self {
            case .list: return L10n.tr("pipeline.list")
            case .detail: return L10n.tr("pipeline.detail")
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < 920

            Group {
                if isCompact {
                    compactLayout
                } else {
                    regularLayout
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(navigationTitle)
        .onChange(of: store.filteredSkills.map(\.id)) { ids in
            if let selectedSkillId, !ids.contains(selectedSkillId) {
                self.selectedSkillId = ids.first
            }
        }
        .onChange(of: store.filterSourceId) { _ in
            compactPane = .list
        }
    }

    private var regularLayout: some View {
        HSplitView {
            listPanel
                .frame(minWidth: 220, idealWidth: 300)
            detailPanel(isCompact: false)
                .frame(minWidth: 260)
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 0) {
            compactModeHeader
            Divider()
            if compactPane == .list {
                listPanel
            } else {
                detailPanel(isCompact: true)
            }
        }
    }

    private var compactModeHeader: some View {
        HStack(spacing: 10) {
            Picker(L10n.tr("skills.view.mode"), selection: $compactPane) {
                ForEach(CompactPane.allCases) { pane in
                    Text(pane.title).tag(pane)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var listPanel: some View {
        VStack(spacing: 0) {
            overviewStrip
            Divider()
            filterBar
            Divider()
            if store.filteredSkills.isEmpty {
                emptyState
            } else {
                skillList
            }
        }
    }

    private var overviewStrip: some View {
        GeometryReader { geo in
            let showLabels = geo.size.width > 560
            HStack(spacing: 12) {
                Label(String(format: L10n.tr("skills.shown"), store.filteredSkills.count), systemImage: "shippingbox")
                    .font(.body)
                    .foregroundStyle(.secondary)

                if let sourceId = store.filterSourceId,
                   let source = store.sources.first(where: { $0.id == sourceId }) {
                    Label(source.displayName, systemImage: source.type.icon)
                        .font(.callout)
                        .foregroundStyle(source.type.color)
                }

                if store.filterEnabled != nil {
                    Text(enabledFilterLabel)
                        .font(.body)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.14)))
                }

                Spacer()

                if store.filterSourceId != nil {
                    Button(L10n.tr("skills.clearSource")) {
                        store.filterSourceId = nil
                    }
                    .buttonStyle(.borderless)
                }

                Button {
                    Task { await store.checkForUpdates() }
                } label: {
                    if store.isCheckingUpdates {
                        ProgressView().scaleEffect(0.65).frame(width: 16, height: 16)
                    } else if showLabels {
                        Label(L10n.tr("updates.check"), systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(store.isCheckingUpdates)
                .help(L10n.tr("updates.check"))

                Button {
                    Task { await store.syncToGit() }
                } label: {
                    if showLabels {
                        Label(L10n.tr("gitbackup.sync"), systemImage: "externaldrive.badge.timemachine")
                    } else {
                        Image(systemName: "externaldrive.badge.timemachine")
                    }
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .help(L10n.tr("gitbackup.sync"))

                Button {
                    showSaveScenarioSheet = true
                } label: {
                    if showLabels {
                        Label(L10n.tr("scenario.save.button"), systemImage: "theatermasks")
                    } else {
                        Image(systemName: "theatermasks")
                    }
                }
                .buttonStyle(.borderless)
                .help(L10n.tr("scenario.save.button"))

                Button {
                    Task { await store.refreshAll() }
                } label: {
                    if showLabels {
                        Label(L10n.tr("toolbar.refresh"), systemImage: "arrow.clockwise")
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(store.isRefreshing)
                .help(L10n.tr("toolbar.refresh"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(height: 40)
        .background(.bar)
        .sheet(isPresented: $showSaveScenarioSheet) {
            SaveScenarioSheet()
                .environmentObject(store)
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L10n.tr("skills.search.placeholder"), text: $store.searchText)
                .textFieldStyle(.plain)
            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Divider().frame(height: 16)
            enabledFilterPicker
            if !store.allTags.isEmpty {
                Divider().frame(height: 16)
                tagFilterPicker
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var enabledFilterPicker: some View {
        Menu {
            Button(L10n.tr("skills.filter.all")) { store.filterEnabled = nil }
            Button(L10n.tr("skills.filter.enabled")) { store.filterEnabled = true }
            Button(L10n.tr("skills.filter.disabled")) { store.filterEnabled = false }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease")
                Text(enabledFilterLabel)
                    .font(.body)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var tagFilterPicker: some View {
        Menu {
            Button(L10n.tr("skills.filter.tags.all")) {
                store.filterTags = []
            }
            Divider()
            ForEach(store.allTags, id: \.self) { tag in
                Button {
                    if store.filterTags.contains(tag) {
                        store.filterTags.remove(tag)
                    } else {
                        store.filterTags.insert(tag)
                    }
                } label: {
                    HStack {
                        Text(tag)
                        if store.filterTags.contains(tag) {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tag")
                Text(store.filterTags.isEmpty ? L10n.tr("skills.filter.tags") : "\(L10n.tr("skills.filter.tags")) (\(store.filterTags.count))")
                    .font(.body)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var enabledFilterLabel: String {
        switch store.filterEnabled {
        case .some(true): return L10n.tr("skills.filter.enabled")
        case .some(false): return L10n.tr("skills.filter.disabled")
        case .none: return L10n.tr("skills.filter.all")
        }
    }

    private var skillList: some View {
        List(store.filteredSkills, selection: $selectedSkillId) { skill in
            SkillRowView(skill: skill, isSelected: selectedSkillId == skill.id)
                .environmentObject(store)
                .tag(skill.id)
                .contextMenu {
                    if skill.sourceType.supportsEnableDisable {
                        Button(skill.isEnabled ? L10n.tr("action.disable") : L10n.tr("action.enable")) {
                            store.toggleEnabled(skillId: skill.id)
                        }
                    }
                }
                .onTapGesture {
                    selectedSkillId = skill.id
                }
                .onTapGesture(count: 2) {
                    selectedSkillId = skill.id
                    compactPane = .detail
                }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .onAppear {
            if selectedSkillId == nil {
                selectedSkillId = store.filteredSkills.first?.id
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(emptyStateMessage)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateMessage: String {
        if !store.searchText.isEmpty {
            return String(format: L10n.tr("skills.empty.noMatch"), store.searchText)
        }
        return L10n.tr("skills.empty.noSkill")
    }

    @ViewBuilder
    private func detailPanel(isCompact: Bool) -> some View {
        if let id = selectedSkillId, let skill = store.skills.first(where: { $0.id == id }) {
            if isCompact {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Button {
                            compactPane = .list
                        } label: {
                            Label(L10n.tr("skills.backToList"), systemImage: "chevron.left")
                        }
                        .buttonStyle(.borderless)

                        Menu {
                            ForEach(store.filteredSkills) { item in
                                Button {
                                    selectedSkillId = item.id
                                    compactPane = .list
                                } label: {
                                    Text("\(item.name) · \(item.sourceName)")
                                }
                            }
                        } label: {
                            Label(skill.name, systemImage: "arrow.triangle.2.circlepath")
                                .lineLimit(1)
                        }
                        .menuStyle(.borderlessButton)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.bar)

                    Divider()

                    SkillDetailView(skill: skill)
                        .environmentObject(store)
                }
            } else {
                SkillDetailView(skill: skill)
                    .environmentObject(store)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text(L10n.tr("skills.select"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var navigationTitle: String {
        if let sourceId = store.filterSourceId,
           let source = store.sources.first(where: { $0.id == sourceId }) {
            return source.displayName
        }
        return String(format: L10n.tr("skills.all.title"), store.filteredSkills.count)
    }
}

struct SkillRowView: View {
    let skill: SkillItem
    let isSelected: Bool
    @EnvironmentObject var store: AppStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: skill.sourceType.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(skill.sourceType.color)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(skill.sourceType.color.opacity(0.14))
                )
                .help(skill.sourceType.localizedDisplayName)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(skill.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if let version = skill.version {
                        Text("v\(version)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }

                Text(skill.sourceName)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if store.skillUpdates[skill.id]?.hasUpdate == true {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.orange)
                    .help(L10n.tr("updates.available"))
            }

            if skill.sourceType.supportsEnableDisable {
                Toggle("", isOn: Binding(
                    get: { skill.isEnabled },
                    set: { _ in store.toggleEnabled(skillId: skill.id) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.75)
                .help(skill.isEnabled ? L10n.tr("action.disable") : L10n.tr("action.enable"))
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.clear)
        )
    }
}

#Preview {
    SkillListView()
        .environmentObject(AppStore.preview)
        .frame(width: 800, height: 550)
}
