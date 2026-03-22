import SwiftUI
import AppKit
import SourceDiscovery

struct SkillDetailView: View {
    let skill: SkillItem
    @EnvironmentObject var store: AppStore
    @State private var showRemoveConfirmation = false
    @State private var showCopySheet = false
    @State private var files: SkillFiles = .empty
    @State private var previewText: String = "…"
    @State private var newTagText: String = ""
    @State private var showTagInput = false
    @State private var showGitURLInput = false
    @State private var gitURLText: String = ""

    private struct SkillFiles {
        let skillDirectory: URL
        let skillDocURL: URL?
        let readmeURL: URL?
        let manifestURL: URL?
        let fileCount: Int?
        let lastModified: Date?

        var primaryDocURL: URL? { skillDocURL ?? readmeURL }

        static var empty: SkillFiles {
            SkillFiles(skillDirectory: URL(fileURLWithPath: "/"), skillDocURL: nil, readmeURL: nil, manifestURL: nil, fileCount: nil, lastModified: nil)
        }
    }

    private var hasAnyDocument: Bool {
        files.primaryDocURL != nil || files.readmeURL != nil
    }

    private nonisolated static func resolveURL(from path: String?, fm: FileManager) -> URL? {
        guard let path else { return nil }
        let url = URL(fileURLWithPath: path)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    private nonisolated static func findExisting(_ names: [String], in dir: URL, fm: FileManager) -> URL? {
        for name in names {
            let url = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private func loadFiles(for skill: SkillItem) async {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: skill.path)
        let skillDocPath = skill.skillDocumentPath
        let readmePath = skill.readmePath
        let manifestPath = skill.manifestPath
        let knownFileCount = skill.fileCount
        let knownModified = skill.lastModified

        let (skillDoc, readme, manifest, count, modified) = await Task.detached(priority: .userInitiated) {
            let skillDoc = Self.resolveURL(from: skillDocPath, fm: fm) ?? Self.findExisting(["SKILL.md", "skill.md"], in: dir, fm: fm)
            let readme = Self.resolveURL(from: readmePath, fm: fm) ?? Self.findExisting(["README.md", "Readme.md", "readme.md"], in: dir, fm: fm)
            let manifest = Self.resolveURL(from: manifestPath, fm: fm) ?? Self.findExisting(["skill.json", "manifest.json"], in: dir, fm: fm)
            let count = knownFileCount ?? (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))?.count
            let modified = knownModified ?? (try? fm.attributesOfItem(atPath: dir.path)[.modificationDate]) as? Date
            return (skillDoc, readme, manifest, count, modified)
        }.value

        let loaded = SkillFiles(
            skillDirectory: dir,
            skillDocURL: skillDoc,
            readmeURL: readme,
            manifestURL: manifest,
            fileCount: count,
            lastModified: modified
        )
        files = loaded

        let primaryURL = loaded.primaryDocURL
        let text = await Task.detached(priority: .userInitiated) { () -> String in
            guard let url = primaryURL,
                  let raw = try? String(contentsOf: url, encoding: .utf8) else {
                return L10n.tr("details.documents.none")
            }
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? L10n.tr("details.documents.none") : String(normalized.prefix(8000))
        }.value
        previewText = text
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                tagsSection
                Divider()
                metadataSection
                Divider()
                documentSection
                Divider()
                fileSection
                if skill.sourceType.supportsEnableDisable || skill.sourceType.supportsInstallRemove {
                    Divider()
                    actionsSection
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: skill.id) {
            await loadFiles(for: skill)
        }
        .confirmationDialog(
            String(format: "%@ %@?", L10n.tr("action.remove"), skill.name),
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.tr("action.remove"), role: .destructive) {
                store.deleteSkill(id: skill.id)
            }
            Button(L10n.tr("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("action.remove.confirm"))
        }

        .sheet(isPresented: $showCopySheet) {
            CopySkillSheet(skill: skill)
                .environmentObject(store)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(skill.sourceType.color.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: "shippingbox.fill")
                    .font(.title3)
                    .foregroundStyle(skill.sourceType.color)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(skill.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                HStack(spacing: 6) {
                    if let version = skill.version {
                        Label("v\(version)", systemImage: "tag")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    Label(skill.sourceName, systemImage: skill.sourceType.icon)
                        .font(.body)
                        .foregroundStyle(skill.sourceType.color)
                }
                statusBadge
            }

            Spacer()
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(skill.isEnabled ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
            Text(skill.isEnabled ? L10n.tr("state.enabled") : L10n.tr("state.disabled"))
                .font(.footnote)
                .foregroundStyle(skill.isEnabled ? .green : .secondary)
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.tr("details.tags.title"))
                    .font(.title3)
                Spacer()
                Button {
                    showTagInput.toggle()
                    newTagText = ""
                } label: {
                    Image(systemName: showTagInput ? "xmark.circle" : "plus.circle")
                }
                .buttonStyle(.borderless)
            }

            FlowLayout(spacing: 6) {
                ForEach(skill.tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                            .font(.callout)
                            .foregroundStyle(.white)
                        Button {
                            let updated = skill.tags.filter { $0 != tag }
                            store.setTags(skillId: skill.id, tags: updated)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor))
                }

                if skill.tags.isEmpty && !showTagInput {
                    Text(L10n.tr("details.tags.empty"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if showTagInput {
                HStack(spacing: 8) {
                    TextField(L10n.tr("details.tags.placeholder"), text: $newTagText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addTag() }
                    Button(L10n.tr("details.tags.add")) { addTag() }
                        .buttonStyle(.bordered)
                        .disabled(newTagText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func saveGitURL() {
        let url = gitURLText.trimmingCharacters(in: .whitespaces)
        var updated = skill.metadata
        updated["git.remoteURL"] = url.isEmpty ? nil : url
        store.setMetadata(skillId: skill.id, metadata: updated)
        showGitURLInput = false
    }

    private func addTag() {
        let tag = newTagText.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !skill.tags.contains(tag) else {
            newTagText = ""
            showTagInput = false
            return
        }
        store.setTags(skillId: skill.id, tags: skill.tags + [tag])
        newTagText = ""
        showTagInput = false
    }

    // MARK: - Metadata

    @ViewBuilder
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("details.title"))
                .font(.title3)

            DetailRow(label: L10n.tr("details.source"), value: skill.sourceName)
            DetailRow(label: L10n.tr("details.type"), value: skill.sourceType.localizedDisplayName)
            DetailRow(label: L10n.tr("details.path"), value: skill.path, isMonospaced: true)
            DetailRow(label: L10n.tr("details.indexed"), value: skill.indexedAt.formatted(date: .abbreviated, time: .shortened))
            if let version = skill.version {
                DetailRow(label: L10n.tr("details.version"), value: version)
            }
            HStack(alignment: .top, spacing: 0) {
                Text(L10n.tr("details.git.remoteURL"))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .leading)
                if showGitURLInput {
                    HStack(spacing: 6) {
                        TextField("https://github.com/…", text: $gitURLText)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.subheadline, design: .monospaced))
                            .onSubmit { saveGitURL() }
                        Button(L10n.tr("details.tags.add")) { saveGitURL() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button { showGitURLInput = false } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                } else if let remoteURL = skill.metadata["git.remoteURL"], !remoteURL.isEmpty {
                    HStack(spacing: 6) {
                        Text(remoteURL)
                            .font(.system(.subheadline, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button { showGitURLInput = true; gitURLText = remoteURL } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                } else {
                    Button(L10n.tr("details.git.setURL")) {
                        showGitURLInput = true
                        gitURLText = ""
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
                }
            }
            if let commit = skill.metadata["git.installedCommit"], !commit.isEmpty {
                DetailRow(label: L10n.tr("details.git.installedCommit"), value: String(commit.prefix(10)), isMonospaced: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))
        )

        if let info = store.skillUpdates[skill.id], info.hasUpdate {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.tr("updates.available"))
                        .font(.callout)
                        .fontWeight(.medium)
                    if let latest = info.latestCommit {
                        Text(String(format: L10n.tr("updates.latestCommit"), String(latest.prefix(10))))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.orange.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))
            )
        }
    }

    private var documentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("details.documents.title"))
                .font(.title3)

            if let primary = files.primaryDocURL {
                DetailRow(label: L10n.tr("details.documents.primary"), value: primary.lastPathComponent, isMonospaced: true)
            } else {
                DetailRow(label: L10n.tr("details.documents.primary"), value: L10n.tr("details.documents.unavailable"))
            }

            if let readme = files.readmeURL {
                DetailRow(label: L10n.tr("details.documents.readme"), value: readme.lastPathComponent, isMonospaced: true)
            } else {
                DetailRow(label: L10n.tr("details.documents.readme"), value: L10n.tr("details.documents.unavailable"))
            }

            if !hasAnyDocument {
                Text(L10n.tr("details.documents.missingHint"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                Text(previewText)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 140, maxHeight: 260)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.05))
            )

            HStack(spacing: 10) {
                Button {
                    revealInFinder(files.skillDirectory)
                } label: {
                    Label(L10n.tr("details.path.openFolder"), systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Button {
                    if let url = files.primaryDocURL { openFile(url) }
                } label: {
                    Label(L10n.tr("details.documents.openPrimary"), systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                .disabled(files.primaryDocURL == nil)

                Button {
                    if let url = files.readmeURL { openFile(url) }
                } label: {
                    Label(L10n.tr("details.documents.openReadme"), systemImage: "book")
                }
                .buttonStyle(.bordered)
                .disabled(files.readmeURL == nil)
            }
        }
    }

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.tr("details.files.title"))
                .font(.title3)

            DetailRow(
                label: L10n.tr("details.path"),
                value: files.skillDirectory.path,
                isMonospaced: true
            )

            DetailRow(
                label: L10n.tr("details.documents.primary"),
                value: files.primaryDocURL?.lastPathComponent ?? L10n.tr("details.documents.unavailable"),
                isMonospaced: true
            )

            if let manifest = files.manifestURL {
                DetailRow(label: "Manifest", value: manifest.lastPathComponent, isMonospaced: true)
            }

            DetailRow(
                label: L10n.tr("details.files.lastModified"),
                value: files.lastModified?.formatted(date: .abbreviated, time: .shortened) ?? L10n.tr("details.documents.unavailable")
            )
            DetailRow(
                label: L10n.tr("details.files.count"),
                value: files.fileCount.map { "\($0)" } ?? L10n.tr("details.documents.unavailable")
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func openFile(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("actions.title"))
                .font(.title3)

            HStack(spacing: 10) {
                if skill.sourceType.supportsEnableDisable {
                    Button {
                        store.toggleEnabled(skillId: skill.id)
                    } label: {
                        Label(skill.isEnabled ? L10n.tr("action.disable") : L10n.tr("action.enable"),
                              systemImage: skill.isEnabled ? "pause.circle" : "play.circle")
                    }
                    .buttonStyle(.bordered)
                }

                if skill.sourceType.supportsInstallRemove {
                    Button {
                        showCopySheet = true
                    } label: {
                        Label(L10n.tr("action.copy"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        showRemoveConfirmation = true
                    } label: {
                        Label(L10n.tr("action.remove"), systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }

            if !skill.sourceType.supportsEnableDisable && !skill.sourceType.supportsInstallRemove {
                Text(L10n.tr("actions.unsupported"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}


private struct CopySkillSheet: View {
    let skill: SkillItem
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTargetId: String = ""
    @State private var isSubmitting = false

    private var targets: [SourceItem] {
        store.copyTargets(for: skill)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(format: L10n.tr("copy.title"), skill.name))
                .font(.headline)

            if targets.isEmpty {
                Text(L10n.tr("copy.empty"))
                    .foregroundStyle(.secondary)
            } else {
                Picker(L10n.tr("copy.target"), selection: $selectedTargetId) {
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

            HStack {
                Spacer()
                Button(L10n.tr("common.cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L10n.tr("action.copy")) {
                    guard !selectedTargetId.isEmpty else { return }
                    isSubmitting = true
                    Task {
                        await store.copySkill(skillId: skill.id, to: selectedTargetId)
                        isSubmitting = false
                        dismiss()
                    }
                }
                .disabled(selectedTargetId.isEmpty || isSubmitting)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }
}

// MARK: - FlowLayout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var rowX: CGFloat = 0
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if rowX + size.width > width, rowX > 0 {
                height += rowHeight + spacing
                rowX = 0
                rowHeight = 0
            }
            rowX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var rowX = bounds.minX
        var rowY = bounds.minY
        var rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if rowX + size.width > bounds.maxX, rowX > bounds.minX {
                rowY += rowHeight + spacing
                rowX = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: rowX, y: rowY), proposal: ProposedViewSize(size))
            rowX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - DetailRow

private struct DetailRow: View {
    let label: String
    let value: String
    var isMonospaced = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(label)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(isMonospaced ? .system(.subheadline, design: .monospaced) : .subheadline)
                .textSelection(.enabled)
                .lineLimit(4)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Preview

#Preview {
    SkillDetailView(skill: SkillItem.sampleSkills[0])
        .environmentObject(AppStore.preview)
        .frame(width: 520, height: 700)
}
