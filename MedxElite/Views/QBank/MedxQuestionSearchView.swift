import SwiftUI

/// Full-text search across both question banks, with the filters that make it useful for
/// revision: bank, subject, image-based only, attempted / wrong / unattempted, and bookmarked.
///
/// Search runs against `MedxQuestionIndexStore`, which only knows about modules that have
/// been indexed — so the coverage banner is not decoration, it is the honest answer to "did
/// you really look at all 32,467?".
public struct MedxQuestionSearchView: View {
    @ObservedObject private var index = MedxQuestionIndexStore.shared
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var medxTheme = MedxAccentThemeStore.shared
    @ObservedObject private var appState = AppState.shared

    @State private var query: String
    @State private var filters = MedxQuestionFilters()
    @State private var results: [MedxIndexedQuestion] = []
    @State private var history = MedxAnswerHistory()
    @State private var subjects: [MedxBankSubject] = []
    @State private var isPreparing = true
    @State private var isBuildingSitting = false

    @Environment(\.dismiss) private var dismiss

    public init(seed: String = "") {
        _query = State(initialValue: seed)
    }

    private var uid: String? { authService.currentSession?.uid }

    /// One value the debounced search task can key on.
    private var searchKey: String {
        [
            query,
            filters.subjectKey ?? "all",
            filters.bank?.rawValue ?? "both",
            filters.imageBased ? "img" : "-",
            filters.bookmarkedOnly ? "bm" : "-",
            filters.status.rawValue,
            String(history.attempted.count),
            String(index.indexedCount)
        ].joined(separator: "#")
    }

    public var body: some View {
        NavigationStack {
            content
                .medxPage(.qbank)
                .navigationTitle("Search questions")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search 32,467 questions")
                .task { await prepare() }
                .task(id: searchKey) { await runSearch() }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if !index.isComplete {
                    coverageBanner
                }

                filterRow

                if isPreparing {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if index.isEmpty {
                    emptyIndexState
                } else if results.isEmpty {
                    noMatchState
                } else {
                    resultsSection
                }
            }
            .padding(.horizontal, MedxDS.gutter)
            .padding(.top, 10)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            MedxSectionHeader(
                results.count == 1 ? "1 match" : "\(results.count) matches",
                subtitle: results.count >= 300 ? "Showing the first 300" : nil
            )

            ForEach(results) { entry in
                NavigationLink {
                    MedxSearchResultDetailView(entry: entry, uid: uid)
                } label: {
                    resultRow(entry)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        practise(with: [entry], mode: .revision, name: entry.moduleName)
                    } label: {
                        Label("Practise this one", systemImage: "bolt")
                    }
                    Button {
                        filters.subjectKey = entry.subjectKey
                    } label: {
                        Label("Only \(entry.subject)", systemImage: "line.3.horizontal.decrease")
                    }
                    Button {
                        filters.bank = entry.bank
                    } label: {
                        Label("Only \(entry.bank.label)", systemImage: "square.stack.3d.up")
                    }
                }
            }
        }
    }

    private func resultRow(_ entry: MedxIndexedQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)

            HStack(spacing: 6) {
                // Both banks have an Anatomy, a Pathology and a Medicine, so the subject name
                // alone does not say where a hit came from.
                MedxChip(entry.bank.label, tint: entry.bank == .marrow ? MedxCandy.violet : MedxCandy.lime)

                MedxChip(entry.subject, tint: MedxTheme.accent)

                Text(entry.moduleName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if entry.hasImage {
                    Image(systemName: "photo")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Has a figure")
                }

                statusGlyph(for: entry)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medxCard()
        .contentShape(MedxDS.shape(MedxDS.card))
        .accessibilityElement(children: .combine)
    }

    /// Routed through the store rather than reading `history` directly, because deciding whether
    /// a bare question id belongs to this entry needs the index's own two-bank ambiguity table.
    @ViewBuilder
    private func statusGlyph(for entry: MedxIndexedQuestion) -> some View {
        if index.isBookmarked(entry, history: history) {
            Image(systemName: "bookmark.fill")
                .font(.caption2)
                .foregroundStyle(MedxDS.warn)
                .accessibilityLabel("Bookmarked")
        } else if index.isWrong(entry, history: history) {
            Image(systemName: "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(MedxDS.wrong)
                .accessibilityLabel("Answered wrong before")
        } else if index.isAttempted(entry, history: history) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(MedxDS.correct)
                .accessibilityLabel("Attempted")
        }
    }

    // MARK: - Filters

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Bank", selection: $filters.bank) {
                        Text("Both banks").tag(MedxBank?.none)
                        ForEach(MedxBank.allCases) { bank in
                            Text(bank.label).tag(MedxBank?.some(bank))
                        }
                    }
                } label: {
                    filterChip(
                        title: filters.bank?.label ?? "Both banks",
                        icon: "square.stack.3d.up",
                        isOn: filters.bank != nil
                    )
                }

                Menu {
                    Picker("Subject", selection: $filters.subjectKey) {
                        Text("All subjects").tag(String?.none)
                        ForEach(pickableSubjects) { subject in
                            Text(subjectLabel(subject)).tag(String?.some(subject.id))
                        }
                    }
                } label: {
                    filterChip(
                        title: subjects.first { $0.id == filters.subjectKey }?.name ?? "All subjects",
                        icon: "books.vertical",
                        isOn: filters.subjectKey != nil
                    )
                }

                Menu {
                    Picker("Status", selection: $filters.status) {
                        ForEach(MedxQuestionFilters.Status.allCases) { status in
                            Label(status.label, systemImage: status.icon).tag(status)
                        }
                    }
                } label: {
                    filterChip(
                        title: filters.status == .any ? "Any status" : filters.status.label,
                        icon: filters.status.icon,
                        isOn: filters.status != .any
                    )
                }

                Button {
                    HapticManager.selection()
                    filters.imageBased.toggle()
                } label: {
                    filterChip(title: "Image-based", icon: "photo", isOn: filters.imageBased)
                }
                .buttonStyle(.plain)

                Button {
                    HapticManager.selection()
                    filters.bookmarkedOnly.toggle()
                } label: {
                    filterChip(title: "Bookmarked", icon: "bookmark", isOn: filters.bookmarkedOnly)
                }
                .buttonStyle(.plain)

                if filters.isActive {
                    Button {
                        HapticManager.light()
                        withAnimation(.snappy) { filters = MedxQuestionFilters() }
                    } label: {
                        filterChip(title: "Clear", icon: "xmark", isOn: false)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
        // A subject belonging to the other bank, left set behind a bank chip, is a pair of filters
        // that can never match anything — and the screen would blame the query for it.
        .onChange(of: filters.bank) { _, bank in
            guard let bank, let key = filters.subjectKey else { return }
            if subjects.first(where: { $0.id == key })?.bank != bank {
                filters.subjectKey = nil
            }
        }
    }

    /// Narrowed by the bank chip, so picking Marrow and then opening the subject menu does not
    /// offer forty entries half of which would contradict the chip beside it.
    private var pickableSubjects: [MedxBankSubject] {
        guard let bank = filters.bank else { return subjects }
        return subjects.filter { $0.bank == bank }
    }

    /// The bank is only worth spelling out when both are on the menu — with the bank chip set,
    /// every row would carry the same prefix.
    private func subjectLabel(_ subject: MedxBankSubject) -> String {
        filters.bank == nil ? "\(subject.name) · \(subject.bank.label)" : subject.name
    }

    private func filterChip(title: String, icon: String, isOn: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(isOn ? Color.white : Color.primary)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(isOn ? MedxTheme.accent : MedxDS.sunken, in: Capsule())
        .contentShape(Capsule())
    }

    // MARK: - Banners and empty states

    private var coverageBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: index.isBuilding ? "arrow.down.circle" : "exclamationmark.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MedxDS.warn)
                    .symbolEffect(.pulse, isActive: index.isBuilding)

                VStack(alignment: .leading, spacing: 2) {
                    Text(index.isBuilding ? "Building the index…" : "Partial index")
                        .font(.subheadline.weight(.semibold))
                    Text(index.coverageSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }

                Spacer(minLength: 8)

                if index.isBuilding {
                    Button("Stop") { index.cancelBuild() }
                        .font(.caption.weight(.semibold))
                        .medxBorderedButton()
                        .buttonBorderShape(.capsule)
                } else {
                    Button("Build") {
                        HapticManager.light()
                        index.build(subjects: subjects)
                    }
                    .font(.caption.weight(.semibold))
                    .medxFilledButton()
                    .buttonBorderShape(.capsule)
                    .disabled(subjects.isEmpty)
                }
            }

            ProgressView(value: index.coverage)
                .tint(MedxTheme.accent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medxCard()
        .animation(.snappy, value: index.indexedCount)
    }

    private var emptyIndexState: some View {
        ContentUnavailableView {
            Label("Nothing indexed yet", systemImage: "magnifyingglass")
        } description: {
            Text("Searching every question needs their text on this device once. "
                 + "Building the index fetches all 2,171 modules across both banks — it can be paused and resumed.")
        } actions: {
            Button {
                HapticManager.medium()
                index.build(subjects: subjects)
            } label: {
                Text("Build the index")
                    .font(.subheadline.weight(.semibold))
                    .frame(minWidth: 170, minHeight: 44)
            }
            .medxFilledButton()
            .buttonBorderShape(.capsule)
            .disabled(subjects.isEmpty || index.isBuilding)
        }
        .padding(.top, 20)
    }

    private var noMatchState: some View {
        ContentUnavailableView {
            Label(query.isEmpty && !filters.isActive ? "Search the bank" : "No matches", systemImage: "magnifyingglass")
        } description: {
            if query.isEmpty && !filters.isActive {
                Text("Type at least two letters, or pick a filter to browse — "
                     + "for example every image-based question you have got wrong.")
            } else {
                Text("Nothing in the indexed \(index.indexedCount.formatted()) questions matches that.")
            }
        }
        .padding(.top, 20)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Done") { dismiss() }
                .font(.body.weight(.semibold))
        }

        ToolbarItem(placement: .topBarTrailing) {
            if isBuildingSitting {
                ProgressView().controlSize(.small)
            } else {
                Menu {
                    Button {
                        practise(with: results, mode: .revision, name: sittingName)
                    } label: {
                        Label("Revision mode", systemImage: "bolt")
                    }
                    Button {
                        practise(with: results, mode: .exam, name: sittingName)
                    } label: {
                        Label("Exam mode", systemImage: "timer")
                    }
                } label: {
                    Label("Practise these", systemImage: "play.circle")
                }
                .disabled(results.count < 2)
            }
        }
    }

    private var sittingName: String {
        if let subjectKey = filters.subjectKey,
           let subject = subjects.first(where: { $0.id == subjectKey }) {
            return "\(subject.name) · search"
        }
        if let bank = filters.bank {
            return "\(bank.label) · search"
        }
        return query.isEmpty ? "Filtered questions" : "“\(query)”"
    }

    // MARK: - Actions

    /// Turns index entries back into a real sitting. Capped at 40 so one tap cannot queue a
    /// three-hundred-question paper by accident.
    private func practise(with entries: [MedxIndexedQuestion], mode: SittingMode, name: String) {
        guard !entries.isEmpty, !isBuildingSitting else { return }
        isBuildingSitting = true
        HapticManager.medium()

        Task {
            let questions = await index.questions(for: entries, limit: 40)
            isBuildingSitting = false
            guard !questions.isEmpty else {
                HapticManager.error()
                return
            }
            appState.startSitting(
                RunnerPayload(
                    kind: "qbank",
                    id: "search-" + String(UUID().uuidString.prefix(8)),
                    name: name,
                    subject: entries.first?.subject ?? "",
                    mode: mode,
                    gradable: true,
                    questions: questions
                )
            )
        }
    }

    // MARK: - Data

    private func prepare() async {
        defer { isPreparing = false }
        guard let uid else { return }

        history = MedxAnswerHistory(attempts: [], bookmarks: activityStore.bookmarks(for: uid))

        guard let token = try? await authService.getValidIdToken() else { return }
        // Both banks: an index that covered only ARISE would quietly answer "no matches" for
        // three-quarters of the Marrow tree.
        async let subjectsTask = FirestoreService.shared.fetchQBankBanks(idToken: token)
        async let attemptsTask = FirestoreService.shared.fetchUserAttempts(uid: uid, idToken: token)

        let loadedSubjects = (try? await subjectsTask) ?? []
        let loadedAttempts = (try? await attemptsTask) ?? []

        subjects = loadedSubjects
        history = MedxAnswerHistory(attempts: loadedAttempts, bookmarks: activityStore.bookmarks(for: uid))
        index.noteExpectations(subjects: loadedSubjects)
    }

    /// Debounced: `task(id:)` cancels the previous run on every keystroke, so the 220 ms
    /// sleep means the full-index scan happens once the typing stops.
    private func runSearch() async {
        try? await Task.sleep(nanoseconds: 220_000_000)
        guard !Task.isCancelled else { return }

        let found = index.search(query, filters: filters, history: history)
        withAnimation(.snappy(duration: 0.2)) { results = found }
    }
}

// MARK: - Result detail

/// The full question behind a search hit, read-only: stem, figures, the marked key and the
/// explanation. The module document is fetched on demand (and cached by `FirestoreService`,
/// so opening a second hit from the same module is instant).
struct MedxSearchResultDetailView: View {
    let entry: MedxIndexedQuestion
    let uid: String?

    @State private var question: Question?
    @State private var loadState: MedxLoadState = .loading
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var medxTheme = MedxAccentThemeStore.shared

    private var isBookmarked: Bool {
        guard let question else { return false }
        return activityStore.isBookmarked(questionId: question.id, sourceId: entry.moduleId, uid: uid)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                switch loadState {
                case .loading:
                    ProgressView("Loading the question…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn't load it", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    }
                case .loaded:
                    if let question {
                        questionBody(question)
                    }
                }
            }
            .padding(MedxDS.gutter)
        }
        .medxPage(.qbank)
        .navigationTitle(entry.subject)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if question != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        toggleBookmark()
                    } label: {
                        Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                            .symbolEffect(.bounce, value: isBookmarked)
                    }
                    .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark question")
                }
            }
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                MedxChip(entry.bank.label, tint: entry.bank == .marrow ? MedxCandy.violet : MedxCandy.lime)
                MedxChip(entry.subject, tint: MedxTheme.accent)
                if !entry.chapter.isEmpty {
                    MedxChip(entry.chapter, tint: .secondary)
                }
                Spacer(minLength: 0)
            }

            Text(entry.moduleName)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func questionBody(_ question: Question) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HTMLRichTextView(html: question.displayText, fontSize: 17, weight: .semibold)

                if let images = question.images, !images.isEmpty {
                    ForEach(images, id: \.self) { raw in
                        RunnerFigure(raw: raw)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .medxCard()

            VStack(spacing: 8) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { pair in
                    let option = pair.element
                    let isCorrect = option.correct == true || question.correctIds.contains(option.id)

                    HStack(alignment: .top, spacing: 12) {
                        Text(MedxOptionLetter.of(option, at: pair.offset))
                            .font(.footnote.weight(.bold).monospacedDigit())
                            .foregroundStyle(isCorrect ? Color.white : Color.primary)
                            .frame(width: 26, height: 26)
                            .background(isCorrect ? MedxDS.correct : MedxDS.sunken, in: Circle())

                        HTMLRichTextView(html: option.text, fontSize: 15, weight: .regular)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if isCorrect {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(MedxDS.correct)
                        }
                    }
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .medxTile(accentColor: isCorrect ? MedxDS.correct : nil, isSelected: isCorrect)
                }
            }

            if let explanation = question.explanation, !explanation.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Explanation", systemImage: "lightbulb.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MedxDS.warn)
                    HTMLRichTextView(html: explanation, fontSize: 15, weight: .regular, textColor: .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .medxCard()
            }
        }
        .transition(.opacity)
    }

    private func toggleBookmark() {
        guard let question else { return }
        HapticManager.selection()
        activityStore.toggleBookmark(
            question: question,
            sourceId: entry.moduleId,
            sourceName: entry.moduleName,
            subject: entry.subject,
            uid: uid
        )
    }

    private func load() async {
        guard question == nil else { return }
        guard let token = try? await AuthService.shared.getValidIdToken() else {
            loadState = .failed("Sign-in expired. Pull back and try again.")
            return
        }
        guard let module = try? await FirestoreService.shared.fetchQBankModule(
            moduleId: entry.moduleId,
            idToken: token
        ) else {
            loadState = .failed("Check your connection and try again.")
            return
        }

        question = (module.questions ?? []).first { $0.id == entry.questionId }
        loadState = question == nil
            ? .failed("This question is no longer in its module.")
            : .loaded
    }
}
