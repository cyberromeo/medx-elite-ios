import SwiftUI

/// Custom modules — build a paper out of any modules in either bank, then run it.
///
/// This screen is the list and the two confirmations; the picking itself is
/// `ModuleBuilderSheet`, shared with Faceoff so a duel host can build a paper without leaving
/// the lobby. The mode picker is the one every paper uses.
///
/// The list holds both profiles' papers: either of them can run, edit or delete anything in it,
/// and the detail line on each row says who built it.
public struct CustomModulesView: View {
    @ObservedObject private var store = MedxCustomModuleStore.shared
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var appState = AppState.shared

    @State private var draft: MedxCustomModule?
    @State private var isEditingExisting = false
    @State private var runTarget: MedxCustomModule?
    /// The pick made inside the mode sheet, started once the sheet has gone — see
    /// `StartSessionSheet` for why not sooner.
    @State private var pendingRun: (module: MedxCustomModule, mode: SittingMode)?
    @State private var confirmDelete: MedxCustomModule?
    @State private var buildFailed: String?
    @State private var isBuilding = false

    public init() {}

    private var uid: String? { authService.currentSession?.uid }

    private var subtitle: String {
        let count = store.modules.count
        guard count > 0 else { return "Your own papers, from either bank" }
        return count == 1 ? "1 paper · shared with both of you" : "\(count) papers · shared with both of you"
    }

    public var body: some View {
        List {
            Section {
                Button {
                    guard let uid else { return }
                    HapticManager.medium()
                    isEditingExisting = false
                    draft = MedxCustomModule.blank(uid: uid)
                } label: {
                    HStack(spacing: MedxSpace.m) {
                        MedxTileLabel(
                            "New custom module",
                            detail: "Mix modules from both banks into one paper",
                            symbol: "plus",
                            hue: MedxFeature.customModules.color
                        )
                        .foregroundStyle(.primary)
                        Spacer(minLength: MedxSpace.s)
                        MedxRowChevron()
                    }
                }
                .disabled(uid == nil)
            }

            if store.isLoading, store.modules.isEmpty {
                Section {
                    MedxPlaceholderRows(count: 3)
                }
            } else if store.modules.isEmpty {
                Section {
                    MedxEmptyState(
                        "No custom modules yet",
                        symbol: MedxFeature.customModules.symbol,
                        message: "Build one out of the chapters you keep getting wrong. A 40-question mixed paper takes about six taps."
                    )
                }
            } else {
                Section {
                    ForEach(store.modules) { module in
                        moduleRow(module)
                    }
                } header: {
                    Text("Papers")
                } footer: {
                    Text(syncNote)
                }
            }

            if let warning = store.lastDeleteWarning {
                Section {
                    Label(warning, systemImage: "icloud.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(MedxFeature.customModules.title)
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await store.reload(uid: uid) }
        .task { await store.loadIfNeeded(uid: uid) }
        .onReceive(NotificationCenter.default.publisher(for: .medxContentShouldRefresh)) { _ in
            Task { await store.reload(uid: uid) }
        }
        .overlay {
            if isBuilding {
                ProgressView("Reading the modules…")
                    .padding(MedxSpace.xl)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: MedxRadius.card, style: .continuous))
            }
        }
        .sheet(item: $draft) { editing in
            ModuleBuilderSheet(draft: editing, isEditing: isEditingExisting) { saved in
                draft = nil
                isEditingExisting = false
                if let uid {
                    Task { await store.save(saved, uid: uid) }
                }
            } onCancel: {
                draft = nil
                isEditingExisting = false
            }
        }
        .sheet(item: $runTarget, onDismiss: startPendingRun) { module in
            StartSessionSheet(
                title: module.name,
                subtitle: subjectLine(module),
                questionCount: module.effectiveCount,
                examDetail: "One \(module.effectiveCount)-minute clock for the paper. Answers after you submit."
            ) { mode in
                pendingRun = (module: module, mode: mode)
            }
        }
        .confirmationDialog(
            confirmDelete.map { "Delete “\($0.name)”?" } ?? "",
            isPresented: Binding(
                get: { confirmDelete != nil },
                set: { if !$0 { confirmDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete it", role: .destructive) {
                if let target = confirmDelete { delete(target) }
            }
            Button("Keep it", role: .cancel) { confirmDelete = nil }
        } message: {
            Text(deleteMessage)
        }
        .alert(
            "Couldn't build that paper",
            isPresented: Binding(
                get: { buildFailed != nil },
                set: { if !$0 { buildFailed = nil } }
            )
        ) {
            Button("OK", role: .cancel) { buildFailed = nil }
        } message: {
            Text(buildFailed ?? "")
        }
    }

    private func startPendingRun() {
        guard let pending = pendingRun else { return }
        pendingRun = nil
        run(pending.module, mode: pending.mode)
    }

    // MARK: - Rows

    private func moduleRow(_ module: MedxCustomModule) -> some View {
        Button {
            HapticManager.light()
            runTarget = module
        } label: {
            HStack(spacing: MedxSpace.m) {
                MedxSymbolTile(MedxFeature.customModules.symbol, hue: MedxFeature.customModules.color, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(module.name)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(metaLine(module))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(sourcesLine(module))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !module.note.isEmpty {
                        Text(module.note)
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: MedxSpace.s)

                if module.synced == false {
                    Image(systemName: "icloud.slash")
                        .font(.footnote)
                        .foregroundStyle(MedxOutcome.flagged)
                        .accessibilityLabel("On this device only")
                }

                Image(systemName: "play.circle.fill")
                    .font(.title3)
                    .foregroundStyle(MedxTheme.accent)
            }
            .padding(.vertical, 2)
        }
        .swipeActions(edge: .leading) {
            Button {
                HapticManager.light()
                draft = module
                isEditingExisting = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(MedxTheme.accent)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                confirmDelete = module
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                HapticManager.medium()
                run(module, mode: .revision)
            } label: {
                Label("Revision mode", systemImage: "bolt")
            }
            Button {
                HapticManager.medium()
                run(module, mode: .exam)
            } label: {
                Label("Exam mode", systemImage: "timer")
            }
            Divider()
            Button {
                draft = module
                isEditingExisting = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) {
                confirmDelete = module
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(module.name)
        .accessibilityValue(metaLine(module))
        .accessibilityHint("Opens the mode picker. Swipe right to edit, left to delete.")
    }

    private func metaLine(_ module: MedxCustomModule) -> String {
        var parts = [
            module.sources.count == 1 ? "1 module" : "\(module.sources.count) modules",
            "\(MedxFormat.count(module.effectiveCount)) questions"
        ]
        if module.limit != nil, module.questionCount > module.effectiveCount {
            parts.append("capped from \(MedxFormat.count(module.questionCount))")
        }
        if module.shuffle { parts.append("shuffled") }
        return parts.joined(separator: " · ")
    }

    /// The subjects in the paper, then who built it.
    private func sourcesLine(_ module: MedxCustomModule) -> String {
        var subjects: [String] = []
        for source in module.sources where !subjects.contains(source.subject) {
            subjects.append(source.subject)
        }
        var text = subjects.prefix(3).joined(separator: ", ")
        if subjects.count > 3 { text += " +\(subjects.count - 3)" }
        if let author = module.author {
            text += text.isEmpty ? "Built by \(author.displayName)" : " · built by \(author.displayName)"
        }
        return text
    }

    private func subjectLine(_ module: MedxCustomModule) -> String {
        let subjects = Set(module.sources.map(\.subject))
        if subjects.count == 1, let only = subjects.first { return only }
        return "\(module.sources.count) modules across \(subjects.count) subjects"
    }

    private var syncNote: String {
        store.remoteWorks == false
            ? "These could not be saved online, so they live on this device only. Everything still works; they just will not appear on the other phone."
            : "Saved online, so both of you see the same list on every device. Swipe right to edit a paper, left to delete it."
    }

    /// A shared list means the paper being deleted may not be yours, and deleting it takes it
    /// from both of you — so the confirmation says whose it is before it says anything else.
    private var deleteMessage: String {
        var lines: [String] = []
        if let target = confirmDelete, target.uid != uid, let author = target.author {
            lines.append("\(author.displayName) built this one, deleting it removes it for both of you.")
        }
        lines.append("Only the selection goes. The questions belong to the bank, and any sittings you have already run stay in your log.")
        return lines.joined(separator: " ")
    }

    // MARK: - Actions

    private func delete(_ module: MedxCustomModule) {
        guard let uid else { return }
        confirmDelete = nil
        HapticManager.warning()
        Task { await store.delete(id: module.id, uid: uid) }
    }

    /// Assembles the paper, then hands it to the runner through `AppState` — the one host that
    /// owns it.
    private func run(_ module: MedxCustomModule, mode: SittingMode) {
        guard !isBuilding else { return }
        isBuilding = true
        HapticManager.medium()

        Task {
            let built = await store.buildQuestions(for: module)
            isBuilding = false

            guard !built.questions.isEmpty else {
                HapticManager.error()
                buildFailed = built.missing.isEmpty
                    ? "Every module in this paper came back empty."
                    : "None of the \(built.missing.count) modules in this paper could be read. They may have been retired by a re-seed."
                return
            }

            if !built.missing.isEmpty {
                // Losing one chapter is better than losing the paper, but it is not silent.
                HapticManager.warning()
            }

            appState.startSitting(
                RunnerPayload(
                    kind: "custom",
                    id: module.id,
                    name: module.name,
                    subject: module.sources.count == 1 ? module.sources[0].subject : "Custom",
                    mode: mode,
                    gradable: true,
                    questions: built.questions,
                    questionTags: built.tags
                )
            )
        }
    }
}
