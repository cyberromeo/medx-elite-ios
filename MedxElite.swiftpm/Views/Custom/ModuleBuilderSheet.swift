import SwiftUI

/// The custom-module builder, as a sheet.
///
/// It is a sheet rather than its own screen because picking modules is one continuous act: a
/// full-page form would lose the list you are picking against every time you drilled into a
/// subject. Faceoff presents the same sheet, so a duel host can build a fresh paper without
/// leaving the lobby they are setting up.
public struct ModuleBuilderSheet: View {
    @State private var draft: MedxCustomModule
    private let isEditing: Bool
    private let onSave: (MedxCustomModule) -> Void
    private let onCancel: () -> Void

    @ObservedObject private var authService = AuthService.shared

    @State private var subjects: [MedxBankSubject] = []
    @State private var loadState: MedxLoadState = .loading
    @State private var query = ""
    @State private var openSubject: String?
    @State private var showAllPicked = false

    @Environment(\.dismiss) private var dismiss

    /// How many picked modules the sheet lists by name before it summarises.
    ///
    /// Once a whole subject can go in with one tap the chip list is no longer a dozen names, it
    /// is potentially all 2,171 — and an unbounded list pushes the search field and the tree off
    /// the bottom of the sheet, which breaks the very flow the bulk buttons exist to speed up.
    private static let pickedPreview = 10

    private static let caps = [0, 20, 40, 100]

    public init(
        draft: MedxCustomModule,
        isEditing: Bool = false,
        onSave: @escaping (MedxCustomModule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._draft = State(initialValue: draft)
        self.isEditing = isEditing
        self.onSave = onSave
        self.onCancel = onCancel
    }

    private var uid: String? { authService.currentSession?.uid }

    private var pickedIds: Set<String> {
        Set(draft.sources.map(\.moduleId))
    }

    /// Editing is not necessarily your own paper — the list is shared — so the title says whose
    /// it is before you change it.
    private var title: String {
        guard isEditing else { return "Build a module" }
        if let author = draft.author, author.uid != uid {
            return "Edit \(author.displayName)'s module"
        }
        return "Edit module"
    }

    // MARK: - Filtered tree

    /// The tree the sheet is showing, narrowed to the search. A chapter survives if its own name
    /// matches or if any of its modules do; a subject survives if any chapter does, or its own
    /// name matches.
    private var shownSubjects: [MedxBankSubject] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return subjects }

        return subjects.compactMap { subject in
            let chapters = subject.chapters.compactMap { chapter -> MedxBankChapter? in
                let hits = chapter.modules.filter {
                    $0.name.localizedCaseInsensitiveContains(needle)
                        || chapter.name.localizedCaseInsensitiveContains(needle)
                }
                return hits.isEmpty ? nil : MedxBankChapter(id: chapter.id, name: chapter.name, modules: hits)
            }
            guard !chapters.isEmpty || subject.name.localizedCaseInsensitiveContains(needle) else {
                return nil
            }
            return MedxBankSubject(
                id: subject.id,
                bank: subject.bank,
                name: subject.name,
                slug: subject.slug,
                moduleCount: subject.moduleCount,
                questionCount: subject.questionCount,
                chapters: chapters
            )
        }
    }

    /// Every module id the tree is currently showing. With a search active that is the matches
    /// only, which is what makes a select-all worth having: type "brachial", tap once, done.
    private var visibleIds: [String] {
        shownSubjects.flatMap { $0.modules.map(\.id) }
    }

    private var pickedVisible: Int {
        let picked = pickedIds
        return visibleIds.reduce(0) { picked.contains($1) ? $0 + 1 : $0 }
    }

    private var allVisiblePicked: Bool {
        !visibleIds.isEmpty && pickedVisible == visibleIds.count
    }

    // MARK: - The one primitive

    /// A module, a chapter, a subject and "everything the search is showing" are the same
    /// operation on a different list of rows, and all four are *toggles*: if the group is already
    /// wholly picked, the same tap clears it. Without that, undoing a 38-module subject means 38
    /// taps, which is what made "add all" a dead end on its own.
    private func toggle(_ rows: [MedxModuleSource]) {
        guard !rows.isEmpty else { return }
        if rows.count > 1 { HapticManager.medium() } else { HapticManager.selection() }

        let have = pickedIds
        if rows.allSatisfy({ have.contains($0.moduleId) }) {
            let drop = Set(rows.map(\.moduleId))
            draft.sources.removeAll { drop.contains($0.moduleId) }
        } else {
            draft.sources.append(contentsOf: rows.filter { !have.contains($0.moduleId) })
        }
    }

    private func rows(of chapter: MedxBankChapter, in subject: MedxBankSubject) -> [MedxModuleSource] {
        chapter.modules.map { MedxModuleSource(module: $0, chapter: chapter, subject: subject) }
    }

    private func rows(of subject: MedxBankSubject) -> [MedxModuleSource] {
        subject.chapters.flatMap { rows(of: $0, in: subject) }
    }

    // MARK: - Body

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        nameField
                        optionsRow

                        if !draft.sources.isEmpty {
                            pickedChips
                        }

                        if case .loaded = loadState {
                            bulkBar
                            tree
                        } else if case .failed(let message) = loadState {
                            failed(message)
                        } else {
                            ProgressView("Loading both banks…")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                        }
                    }
                    .padding(.horizontal, MedxDS.gutter)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
                .searchable(
                    text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Find a chapter or module"
                )

                saveBar
            }
            .medxPage()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                }
            }
            .task { await load() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var nameField: some View {
        TextField("Name it — “Weak spots”, “Ortho + Anat”", text: $draft.name)
            .font(.body.weight(.semibold))
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .padding(14)
            .medxCard()
            .accessibilityLabel("Module name")
    }

    private var optionsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $draft.shuffle) {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(MedxTheme.accent)

            VStack(alignment: .leading, spacing: 6) {
                Text("Cap")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                MedxSegmented(
                    section: .custom,
                    segments: Self.caps.map {
                        MedxSegment(value: $0, label: $0 == 0 ? "All" : "\($0)")
                    },
                    selection: Binding(
                        get: { draft.limit ?? 0 },
                        set: { draft.limit = $0 > 0 ? $0 : nil }
                    )
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medxCard()
    }

    private var pickedChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(showAllPicked ? draft.sources : Array(draft.sources.prefix(Self.pickedPreview))) { source in
                        Button {
                            HapticManager.selection()
                            draft.sources.removeAll { $0.moduleId == source.moduleId }
                        } label: {
                            HStack(spacing: 3) {
                                Text(source.name)
                                    .font(.caption2.weight(.bold))
                                    .lineLimit(1)
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .black))
                            }
                            .foregroundStyle(MedxTheme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(MedxTheme.accent.opacity(0.16), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(source.name)")
                    }
                }
            }
            .scrollClipDisabled()

            HStack(spacing: 10) {
                if draft.sources.count > Self.pickedPreview {
                    Button(showAllPicked ? "show fewer" : "+\(draft.sources.count - Self.pickedPreview) more") {
                        showAllPicked.toggle()
                    }
                    .font(.caption.weight(.semibold))
                }

                if draft.sources.count > 1 {
                    // The bulk button below is scoped to what the search is showing, so this is
                    // the only way back to nothing from any state.
                    Button("clear all \(draft.sources.count)", role: .destructive) {
                        HapticManager.warning()
                        draft.sources = []
                        showAllPicked = false
                    }
                    .font(.caption.weight(.semibold))
                }

                Spacer(minLength: 0)
            }
        }
    }

    /// It reads the *filtered* tree, and says so, because a "select all" that quietly reached
    /// past the search would be the one control in this sheet you could not trust.
    private var bulkBar: some View {
        HStack(spacing: 10) {
            Text("\(pickedVisible.formatted()) of \(visibleIds.count.formatted()) "
                 + (query.isEmpty ? "" : "matching ")
                 + (visibleIds.count == 1 ? "module" : "modules"))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button {
                toggle(shownSubjects.flatMap { rows(of: $0) })
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: allVisiblePicked ? "xmark" : "checklist")
                        .font(.system(size: 10, weight: .bold))
                    Text(allVisiblePicked
                         ? "clear"
                         : (query.isEmpty ? "select all" : "select \(visibleIds.count) matches"))
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(MedxTheme.accent)
                .padding(.horizontal, 10)
                .frame(minHeight: 30)
                .background(MedxTheme.accent.opacity(0.16), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(visibleIds.isEmpty)
        }
        .padding(.horizontal, 4)
    }

    private var tree: some View {
        VStack(spacing: 8) {
            ForEach(shownSubjects) { subject in
                subjectBlock(subject)
            }

            if shownSubjects.isEmpty {
                Text("Nothing matches that.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            }
        }
    }

    private func failed(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load the banks", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                loadState = .loading
                Task { await load() }
            }
            .medxFilledButton()
            .buttonBorderShape(.capsule)
        }
    }

    private var saveBar: some View {
        Button {
            HapticManager.medium()
            onSave(draft)
        } label: {
            Text(draft.sources.isEmpty
                 ? "Pick at least one module"
                 : "Save · \(draft.effectiveCount.formatted()) questions")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .medxFilled(MedxTheme.accent)
        .disabled(draft.sources.isEmpty)
        .medxFloatingBar()
    }

    // MARK: - Subject block

    private func subjectBlock(_ subject: MedxBankSubject) -> some View {
        let isOpen = openSubject == subject.id || !query.isEmpty
        let mine = subject.modules
        let picked = pickedIds
        let here = mine.reduce(0) { picked.contains($1.id) ? $0 + 1 : $0 }
        let allHere = !mine.isEmpty && here == mine.count

        return VStack(alignment: .leading, spacing: 8) {
            // Two controls, not one: the row expands, the pill on the end takes the whole
            // subject. Nesting the second inside the first would be an unreachable button.
            HStack(spacing: 8) {
                Button {
                    HapticManager.light()
                    withAnimation(.easeOut(duration: 0.2)) {
                        openSubject = (isOpen && query.isEmpty) ? nil : subject.id
                    }
                } label: {
                    subjectHeader(subject, matched: mine.count, isOpen: isOpen)
                }
                .buttonStyle(.plain)
                .disabled(!query.isEmpty)

                Button {
                    toggle(rows(of: subject))
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: allHere ? "checkmark" : "plus")
                            .font(.system(size: 9, weight: .black))
                        Text(here > 0 ? "\(here)/\(mine.count)" : "all")
                            .font(.caption2.weight(.bold).monospacedDigit())
                    }
                    .foregroundStyle(allHere ? MedxTheme.accent : .secondary)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 30)
                    .background(
                        Capsule().fill(allHere ? MedxTheme.accent.opacity(0.16) : MedxDS.sunken)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(allHere ? "Clear" : "Select") every module in \(subject.name)")
            }

            if isOpen {
                VStack(spacing: 8) {
                    ForEach(subject.chapters) { chapter in
                        chapterBlock(chapter, in: subject)
                    }
                }
                .padding(.leading, 6)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medxCard()
    }

    private func subjectHeader(
        _ subject: MedxBankSubject,
        matched: Int,
        isOpen: Bool
    ) -> some View {
        HStack(spacing: 10) {
            MedxSymbolMark(MedxSubjectArt.symbol(for: subject.name), hue: MedxTheme.accent, size: 32)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(subject.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    MedxPill(subject.bank.label, hue: subject.bank == .marrow ? MedxCandy.butter : MedxCandy.lime)
                }
                // Under a search the row only holds the matches, so it says so — otherwise the
                // "all" pill beside a subject listing 2 of 38 modules reads as all 38.
                Text(query.isEmpty
                     ? "\(subject.questionCount.formatted()) q · \(subject.moduleCount) modules"
                     : "\(matched) of \(subject.moduleCount) modules match")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isOpen ? 90 : 0))
        }
        .contentShape(Rectangle())
    }

    // MARK: - Chapter block

    private func chapterBlock(_ chapter: MedxBankChapter, in subject: MedxBankSubject) -> some View {
        let picked = pickedIds
        let on = chapter.modules.reduce(0) { picked.contains($1.id) ? $0 + 1 : $0 }
        let allOn = !chapter.modules.isEmpty && on == chapter.modules.count

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(chapter.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if on > 0 {
                    Text("\(on)/\(chapter.modules.count)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(MedxTheme.accent)
                }

                Button(allOn ? "clear" : "all") {
                    toggle(rows(of: chapter, in: subject))
                }
                .font(.caption2.weight(.bold))
                .buttonStyle(.plain)
                .foregroundStyle(allOn ? MedxTheme.accent : .secondary)
                .accessibilityLabel("\(allOn ? "Clear" : "Select") every module in \(chapter.name)")
            }

            ForEach(chapter.modules) { module in
                moduleRow(module, chapter: chapter, subject: subject, isOn: picked.contains(module.id))
            }
        }
        .padding(.vertical, 2)
    }

    private func moduleRow(
        _ module: QBankModuleSummary,
        chapter: MedxBankChapter,
        subject: MedxBankSubject,
        isOn: Bool
    ) -> some View {
        Button {
            toggle([MedxModuleSource(module: module, chapter: chapter, subject: subject)])
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isOn ? MedxTheme.accent : Color.secondary)

                Text(module.name)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)

                Text("\(module.questionCount)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(minHeight: 40)
            .medxTile(accentColor: MedxTheme.accent, isSelected: isOn)
            .contentShape(MedxDS.shape(MedxDS.control))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(module.name)
        .accessibilityValue("\(module.questionCount) questions")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Data

    private func load() async {
        guard case .loading = loadState else { return }
        guard let token = try? await authService.getValidIdToken() else {
            loadState = .failed("Sign in again and try once more.")
            return
        }
        do {
            subjects = try await FirestoreService.shared.fetchQBankBanks(idToken: token)
            loadState = .loaded
        } catch {
            loadState = .failed("Check your connection and try again.")
        }
    }
}
