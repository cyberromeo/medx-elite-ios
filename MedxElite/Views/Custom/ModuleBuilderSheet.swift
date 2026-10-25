import SwiftUI

/// The custom-module builder, as a sheet.
///
/// It is a sheet rather than its own screen because picking modules is one continuous act: a
/// full-page form would lose the list you are picking against every time you drilled into a
/// subject. Faceoff presents the same sheet, so a duel host can build a fresh paper without
/// leaving the lobby they are setting up.
///
/// One grouped list: the name, the shape, what is picked so far, then both banks as sections
/// of rows you tick. Save sits in the bar and says how many questions it will be.
public struct ModuleBuilderSheet: View {
    @State private var draft: MedxCustomModule
    private let isEditing: Bool
    private let onSave: (MedxCustomModule) -> Void
    private let onCancel: () -> Void

    @ObservedObject private var authService = AuthService.shared

    @State private var subjects: [MedxBankSubject] = []
    @State private var loadState: MedxLoadState = .loading
    @State private var query = ""
    @State private var expandedSubjects: Set<String> = []
    @State private var showAllPicked = false

    /// How many picked modules the sheet lists by name before it summarises.
    ///
    /// Once a whole subject can go in with one tap the picked list is no longer a dozen names, it
    /// is potentially all 2,171 — and an unbounded list pushes the tree off the bottom of the
    /// sheet, which breaks the very flow the bulk buttons exist to speed up.
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
            List {
                Section {
                    TextField("Name it, like “Weak spots” or “Ortho + Anat”", text: $draft.name)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                } header: {
                    Text("Name")
                }

                Section {
                    Toggle(isOn: $draft.shuffle) {
                        Label("Shuffle", systemImage: "shuffle")
                    }

                    Picker("Cap", selection: capBinding) {
                        ForEach(Self.caps, id: \.self) { value in
                            Text(value == 0 ? "All" : "\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Sitting")
                } footer: {
                    Text("A cap draws that many at random from everything picked.")
                }

                if !draft.sources.isEmpty {
                    pickedSection
                }

                switch loadState {
                case .loaded:
                    Section {
                        bulkRow
                    }

                    ForEach(shownSubjects) { subject in
                        subjectSection(subject)
                    }

                    if shownSubjects.isEmpty {
                        Section {
                            Text("Nothing matches that.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                case .failed(let message):
                    Section {
                        MedxEmptyState(
                            "Couldn't load the banks",
                            symbol: "wifi.exclamationmark",
                            message: message,
                            actionTitle: "Try again"
                        ) {
                            loadState = .loading
                            Task { await load() }
                        }
                    }
                case .loading:
                    Section {
                        MedxPlaceholderRows(count: 6)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Find a chapter or module")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(draft.sources.isEmpty ? "Save" : "Save · \(MedxFormat.count(draft.effectiveCount))") {
                        HapticManager.medium()
                        onSave(draft)
                    }
                    .disabled(draft.sources.isEmpty)
                }
            }
            .task { await load() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationSizing(.page)
    }

    private var capBinding: Binding<Int> {
        Binding(
            get: { draft.limit ?? 0 },
            set: { draft.limit = $0 > 0 ? $0 : nil }
        )
    }

    // MARK: - Picked

    private var pickedSection: some View {
        Section {
            ForEach(showAllPicked ? draft.sources : Array(draft.sources.prefix(Self.pickedPreview))) { source in
                HStack(spacing: MedxSpace.m) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.name)
                            .lineLimit(2)
                        Text(source.subject)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: MedxSpace.s)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        HapticManager.selection()
                        draft.sources.removeAll { $0.moduleId == source.moduleId }
                    } label: {
                        Label("Remove", systemImage: "minus.circle")
                    }
                }
            }

            if draft.sources.count > Self.pickedPreview {
                Button(showAllPicked ? "Show fewer" : "Show all \(draft.sources.count)") {
                    showAllPicked.toggle()
                }
            }
        } header: {
            HStack {
                Text("Picked · \(draft.sources.count)")
                Spacer()
                if draft.sources.count > 1 {
                    // The bulk button below is scoped to what the search is showing, so this is
                    // the only way back to nothing from any state.
                    Button("Clear all", role: .destructive) {
                        HapticManager.warning()
                        draft.sources = []
                        showAllPicked = false
                    }
                    .font(.footnote)
                }
            }
        } footer: {
            Text("Swipe left to drop one.")
        }
    }

    /// It reads the *filtered* tree, and says so, because a "select all" that quietly reached
    /// past the search would be the one control in this sheet you could not trust.
    private var bulkRow: some View {
        HStack(spacing: MedxSpace.m) {
            Text("\(MedxFormat.count(pickedVisible)) of \(MedxFormat.count(visibleIds.count)) "
                 + (query.isEmpty ? "" : "matching ")
                 + (visibleIds.count == 1 ? "module" : "modules"))
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer(minLength: MedxSpace.s)

            Button(allVisiblePicked ? "Clear" : (query.isEmpty ? "Select all" : "Select matches")) {
                toggle(shownSubjects.flatMap { rows(of: $0) })
            }
            .medxSecondary(size: .small)
            .disabled(visibleIds.isEmpty)
        }
    }

    // MARK: - Subject section

    private func subjectSection(_ subject: MedxBankSubject) -> some View {
        let isOpen = expandedSubjects.contains(subject.id) || !query.isEmpty
        let mine = subject.modules
        let picked = pickedIds
        let here = mine.reduce(0) { picked.contains($1.id) ? $0 + 1 : $0 }
        let allHere = !mine.isEmpty && here == mine.count

        return Section {
            // Two controls, not one: the row expands, the button on the end takes the whole
            // subject. Nesting the second inside the first would be an unreachable button.
            HStack(spacing: MedxSpace.m) {
                Button {
                    HapticManager.light()
                    withAnimation(.easeOut(duration: 0.2)) {
                        if expandedSubjects.contains(subject.id) {
                            expandedSubjects.remove(subject.id)
                        } else {
                            expandedSubjects.insert(subject.id)
                        }
                    }
                } label: {
                    HStack(spacing: MedxSpace.m) {
                        MedxSymbolTile(MedxSubjectArt.symbol(for: subject.name), hue: MedxFeature.qbank.color, size: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(subject.name)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            // Under a search the section only holds the matches, so it says so —
                            // otherwise "All" beside a subject listing 2 of 38 modules reads as 38.
                            Text(query.isEmpty
                                 ? "\(subject.bank.label) · \(subject.moduleCount) modules · \(MedxFormat.count(subject.questionCount)) questions"
                                 : "\(subject.bank.label) · \(mine.count) of \(subject.moduleCount) modules match")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: MedxSpace.s)

                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isOpen ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(!query.isEmpty)
                .accessibilityLabel(subject.name)
                .accessibilityValue("\(here) of \(mine.count) picked, \(isOpen ? "expanded" : "collapsed")")

                Button(allHere ? "Clear" : (here > 0 ? "\(here)/\(mine.count)" : "All")) {
                    toggle(rows(of: subject))
                }
                .medxSecondary(size: .small)
                .monospacedDigit()
                .accessibilityLabel("\(allHere ? "Clear" : "Select") every module in \(subject.name)")
            }

            if isOpen {
                ForEach(subject.chapters) { chapter in
                    chapterRows(chapter, in: subject, picked: picked)
                }
            }
        }
    }

    // MARK: - Chapter rows

    @ViewBuilder
    private func chapterRows(_ chapter: MedxBankChapter, in subject: MedxBankSubject, picked: Set<String>) -> some View {
        let on = chapter.modules.reduce(0) { picked.contains($1.id) ? $0 + 1 : $0 }
        let allOn = !chapter.modules.isEmpty && on == chapter.modules.count

        HStack(spacing: MedxSpace.s) {
            Text(chapter.name.isEmpty ? "Modules" : chapter.name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: MedxSpace.s)

            if on > 0 {
                Text("\(on)/\(chapter.modules.count)")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(MedxTheme.accent)
            }

            Button(allOn ? "Clear" : "All") {
                toggle(rows(of: chapter, in: subject))
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.borderless)
            .accessibilityLabel("\(allOn ? "Clear" : "Select") every module in \(chapter.name)")
        }

        ForEach(chapter.modules) { module in
            moduleRow(module, chapter: chapter, subject: subject, isOn: picked.contains(module.id))
        }
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
            HStack(spacing: MedxSpace.m) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? MedxTheme.accent : Color.secondary)

                Text(module.name)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: MedxSpace.s)

                Text("\(module.questionCount)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel(module.name)
        .accessibilityValue("\(module.questionCount) questions, \(isOn ? "picked" : "not picked")")
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
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
