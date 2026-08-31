import SwiftUI

/// Custom modules — build a paper out of any modules in either bank, then run it.
///
/// This screen is the list and the two confirmations; the picking itself is
/// `ModuleBuilderSheet`, shared with Faceoff so a duel host can build a paper without leaving
/// the lobby.
///
/// The list holds both profiles' papers: either of them can run, edit or delete anything in it,
/// and the pill on each card says who built it.
public struct CustomModulesView: View {
    @ObservedObject private var store = MedxCustomModuleStore.shared
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var appState = AppState.shared

    @State private var draft: MedxCustomModule?
    @State private var isEditingExisting = false
    @State private var runTarget: MedxCustomModule?
    @State private var confirmDelete: MedxCustomModule?
    @State private var buildFailed: String?
    @State private var isBuilding = false

    public init() {}

    private var uid: String? { authService.currentSession?.uid }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                MedxPageHeader(
                    section: .custom,
                    title: "Custom modules",
                    lead: "Pick any modules from either bank, shuffle them together, cap the "
                        + "length. It runs exactly like a QBank sitting — and whatever either of "
                        + "you saves shows up here for both."
                )

                newButton

                if store.isLoading, store.modules.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else if store.modules.isEmpty {
                    emptyState
                } else {
                    ForEach(store.modules) { module in
                        CustomModuleCard(
                            module: module,
                            onRun: { runTarget = module },
                            onEdit: {
                                draft = module
                                isEditingExisting = true
                            },
                            onDelete: { confirmDelete = module }
                        )
                    }
                }

                if let warning = store.lastDeleteWarning {
                    noteRow(warning, icon: "icloud.slash", tint: MedxTheme.warningOrange)
                }

                if !store.modules.isEmpty {
                    syncFooter
                }
            }
            .padding(.horizontal, MedxSurface.gutter)
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
        .background(MedxSurface.groupedBackground.ignoresSafeArea())
        .medxScrollEdge()
        .navigationTitle("Custom modules")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.reload(uid: uid) }
        .task { await store.loadIfNeeded(uid: uid) }
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
        .sheet(item: $runTarget) { module in
            MedxCustomRunSheet(module: module, isBuilding: isBuilding) { mode in
                run(module, mode: mode)
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

    /// A shared list means the paper being deleted may not be yours, and deleting it takes it
    /// from both of you — so the confirmation says whose it is before it says anything else.
    private var deleteMessage: String {
        var lines: [String] = []
        if let target = confirmDelete, target.uid != uid, let author = target.author {
            lines.append("\(author.displayName) built this one — deleting it removes it for both of you.")
        }
        lines.append("Only the selection goes. The questions belong to the bank, and any sittings you have already run stay in your log.")
        return lines.joined(separator: " ")
    }

    // MARK: - Pieces

    private var newButton: some View {
        Button {
            guard let uid else { return }
            HapticManager.medium()
            isEditingExisting = false
            draft = MedxCustomModule.blank(uid: uid)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.bold))
                Text("New custom module")
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .medxFilled(MedxSection.custom.fill)
        .disabled(uid == nil)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            MedxSticker("filebox", size: 62, tilt: -8)

            Text("No custom modules yet")
                .font(.headline)

            Text("Build one out of the chapters you keep getting wrong — a 40-question mixed paper takes about six taps.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .padding(.horizontal, 12)
    }

    private var syncFooter: some View {
        noteRow(
            store.remoteWorks == false
                ? "Firestore would not take these, so they live on this device only. Everything still works — they just will not appear on the other one."
                : "Mirrored to medx_custom_modules, so both of you see the same list on every device.",
            icon: store.remoteWorks == false ? "icloud.slash" : "checkmark.icloud",
            tint: store.remoteWorks == false ? MedxTheme.warningOrange : .secondary
        )
    }

    private func noteRow(_ text: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private func delete(_ module: MedxCustomModule) {
        guard let uid else { return }
        confirmDelete = nil
        HapticManager.warning()
        Task { await store.delete(id: module.id, uid: uid) }
    }

    /// Assembles the paper, then hands it to the runner through `AppState` — the same route a
    /// Siri shortcut or a search result takes, so the runner is presented by the one host that
    /// owns it rather than from inside a sheet that is about to close.
    private func run(_ module: MedxCustomModule, mode: SittingMode) {
        guard !isBuilding else { return }
        isBuilding = true
        HapticManager.medium()

        Task {
            let built = await store.buildQuestions(for: module)
            isBuilding = false
            runTarget = nil

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
                    questions: built.questions
                )
            )
        }
    }
}

// MARK: - One saved paper

struct CustomModuleCard: View {
    let module: MedxCustomModule
    let onRun: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private static let previewChips = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                MedxSymbolMark(MedxSection.custom.symbol, hue: MedxSection.custom.fill, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(module.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(metaLine)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if module.synced == false {
                    Image(systemName: "icloud.slash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MedxTheme.warningOrange)
                        .accessibilityLabel("On this device only")
                }
            }

            if !module.note.isEmpty {
                Text(module.note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            chips

            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medxCard()
    }

    private var metaLine: String {
        var parts = [
            module.sources.count == 1 ? "1 module" : "\(module.sources.count) modules",
            "\(module.effectiveCount.formatted()) q"
        ]
        if module.limit != nil, module.questionCount > module.effectiveCount {
            parts.append("capped from \(module.questionCount.formatted())")
        }
        if module.shuffle { parts.append("shuffled") }
        return parts.joined(separator: " · ")
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let author = module.author {
                    MedxPill(author.displayName, hue: author.duelFill, weight: .solid, icon: "person.fill")
                }
                ForEach(module.sources.prefix(Self.previewChips)) { source in
                    MedxPill(source.name, hue: source.bank == .marrow ? MedxCandy.butter : MedxCandy.lime)
                }
                if module.sources.count > Self.previewChips {
                    MedxPill("+\(module.sources.count - Self.previewChips)", weight: .outline)
                }
            }
        }
        .scrollClipDisabled()
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                HapticManager.medium()
                onRun()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.bold))
                    Text("Run")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(minWidth: 66, minHeight: 34)
                .padding(.horizontal, 6)
            }
            .medxFilled(MedxSection.custom.fill)

            Button {
                HapticManager.light()
                onEdit()
            } label: {
                Text("Edit")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 56, minHeight: 34)
            }
            .medxBorderedButton()
            .buttonBorderShape(.capsule)

            Button(role: .destructive) {
                HapticManager.light()
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 40, height: 34)
            }
            .medxBorderedButton()
            .buttonBorderShape(.capsule)
            .accessibilityLabel("Delete \(module.name)")

            Spacer(minLength: 0)

            if let updated = module.updatedDate {
                Text(updated.formatted(.relative(presentation: .numeric)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Run picker

/// The two modes, for a saved paper. Same shape as the series' picker, minus the sectioning —
/// a custom paper is always one clock.
struct MedxCustomRunSheet: View {
    let module: MedxCustomModule
    let isBuilding: Bool
    let onPick: (SittingMode) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MedxPageHeader(
                        section: .custom,
                        eyebrow: "\(module.effectiveCount.formatted()) questions",
                        title: module.name,
                        lead: module.sources.count == 1
                            ? module.sources[0].subject
                            : "\(module.sources.count) modules across "
                                + "\(Set(module.sources.map(\.subject)).count) subjects"
                    )

                    mode(
                        .exam,
                        icon: "timer",
                        title: "Exam mode",
                        blurb: "One \(module.effectiveCount)-minute timer for the paper. Answers after you submit."
                    )
                    mode(
                        .revision,
                        icon: "bolt.fill",
                        title: "Revision mode",
                        blurb: "60 seconds each. Answer and explanation the moment you pick."
                    )

                    if isBuilding {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Reading the modules…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, MedxSurface.gutter)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(MedxSurface.groupedBackground.ignoresSafeArea())
            .navigationTitle(module.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func mode(
        _ value: SittingMode,
        icon: String,
        title: String,
        blurb: String
    ) -> some View {
        Button {
            onPick(value)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MedxSection.custom.onSoft)
                    .frame(width: 42, height: 42)
                    .background(MedxSection.custom.soft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(blurb)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .medxCard()
            .contentShape(RoundedRectangle(cornerRadius: MedxSurface.cardRadius, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
        .disabled(isBuilding)
        .accessibilityLabel(title)
        .accessibilityHint(blurb)
    }
}
