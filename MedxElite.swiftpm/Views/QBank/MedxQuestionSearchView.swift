import SwiftUI

/// Full-text search across both question banks, with the filters that make it useful for
/// revision: bank, subject, image-based only, attempted / wrong / unattempted, and bookmarked.
///
/// Search runs against `MedxQuestionIndexStore`, which only knows about modules that have
/// been indexed — so the subtitle and the coverage row are not decoration, they are the honest
/// answer to "did you really look at all of them?". Pushed from Library; the search field is the
/// navigation bar's own.
public struct MedxQuestionSearchView: View {
    @ObservedObject private var index = MedxQuestionIndexStore.shared
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var appState = AppState.shared

    @State private var query: String
    @State private var filters = MedxQuestionFilters()
    @State private var results: [MedxIndexedQuestion] = []
    @State private var history = MedxAnswerHistory()
    @State private var subjects: [MedxBankSubject] = []
    @State private var isPreparing = true
    @State private var isBuildingSitting = false

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

    /// The one count the prompt, the subtitle and the empty state share.
    private var searchPrompt: String {
        let count = index.isEmpty ? index.expectedQuestions : index.indexedCount
        return count > 0 ? "Search \(MedxFormat.count(count)) questions" : "Search questions"
    }

    private var subtitle: String {
        if index.isEmpty { return "Not downloaded yet" }
        if index.isComplete { return "\(MedxFormat.count(index.indexedCount)) questions on this device" }
        return "\(MedxFormat.count(index.indexedCount)) of \(MedxFormat.count(index.expectedQuestions)) questions on this device"
    }

    public var body: some View {
        List {
            if index.isEmpty {
                emptyIndexSection
            } else if !index.isComplete {
                coverageSection
            }

            if filters.isActive {
                filterSection
            }

            if isPreparing {
                Section {
                    MedxPlaceholderRows(count: 6)
                }
            } else if index.isEmpty {
                EmptyView()
            } else if results.isEmpty {
                Section {
                    noMatchState
                }
            } else {
                Section {
                    ForEach(results) { entry in
                        resultLink(entry)
                    }
                } header: {
                    Text(results.count == 1 ? "1 match" : "\(MedxFormat.count(results.count)) matches")
                } footer: {
                    if results.count >= 300 {
                        Text("Showing the first 300. Add a filter or a longer word to narrow it.")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle(MedxFeature.search.title)
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar { toolbarContent }
        .searchable(text: $query, prompt: searchPrompt)
        .task { await prepare() }
        .task(id: searchKey) { await runSearch() }
        // A subject belonging to the other bank, left set behind a bank filter, is a pair of
        // filters that can never match anything — and the screen would blame the query for it.
        .onChange(of: filters.bank) { _, bank in
            guard let bank, let key = filters.subjectKey else { return }
            if subjects.first(where: { $0.id == key })?.bank != bank {
                filters.subjectKey = nil
            }
        }
    }

    // MARK: - Results

    private func resultLink(_ entry: MedxIndexedQuestion) -> some View {
        NavigationLink {
            MedxSearchResultDetailView(entry: entry, uid: uid)
        } label: {
            VStack(alignment: .leading, spacing: MedxSpace.xs) {
                Text(entry.text)
                    .lineLimit(3)

                HStack(spacing: MedxSpace.s) {
                    // Both banks have an Anatomy, a Pathology and a Medicine, so the subject name
                    // alone does not say where a hit came from.
                    Text("\(entry.bank.label) · \(entry.subject) · \(entry.moduleName)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: MedxSpace.xs)

                    if entry.hasImage {
                        Image(systemName: "photo")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("Has a figure")
                    }

                    statusGlyph(for: entry)
                }
            }
            .padding(.vertical, 2)
        }
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

    /// Routed through the store rather than reading `history` directly, because deciding whether
    /// a bare question id belongs to this entry needs the index's own two-bank ambiguity table.
    @ViewBuilder
    private func statusGlyph(for entry: MedxIndexedQuestion) -> some View {
        if index.isBookmarked(entry, history: history) {
            Image(systemName: "bookmark.fill")
                .font(.caption)
                .foregroundStyle(MedxOutcome.flagged)
                .accessibilityLabel("Bookmarked")
        } else if index.isWrong(entry, history: history) {
            Image(systemName: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(MedxOutcome.wrong)
                .accessibilityLabel("Answered wrong before")
        } else if index.isAttempted(entry, history: history) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(MedxOutcome.correct)
                .accessibilityLabel("Attempted")
        }
    }

    // MARK: - Filters

    /// The filters live in a toolbar menu; this row says what is set, and clears it.
    private var filterSection: some View {
        Section {
            HStack(spacing: MedxSpace.m) {
                Label(filterSummary, systemImage: "line.3.horizontal.decrease")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: MedxSpace.s)
                Button("Clear") {
                    HapticManager.light()
                    withAnimation(.snappy) { filters = MedxQuestionFilters() }
                }
                .medxSecondary(size: .small)
            }
        }
    }

    private var filterSummary: String {
        var parts: [String] = []
        if let bank = filters.bank { parts.append(bank.label) }
        if let key = filters.subjectKey, let subject = subjects.first(where: { $0.id == key }) {
            parts.append(subject.name)
        }
        if filters.status != .any { parts.append(filters.status.label) }
        if filters.imageBased { parts.append("Image-based") }
        if filters.bookmarkedOnly { parts.append("Bookmarked") }
        return parts.joined(separator: " · ")
    }

    /// Narrowed by the bank filter, so picking Marrow and then opening the subject menu does not
    /// offer forty entries half of which would contradict the filter beside it.
    private var pickableSubjects: [MedxBankSubject] {
        guard let bank = filters.bank else { return subjects }
        return subjects.filter { $0.bank == bank }
    }

    /// The bank is only worth spelling out when both are on the menu — with the bank filter set,
    /// every row would carry the same prefix.
    private func subjectLabel(_ subject: MedxBankSubject) -> String {
        filters.bank == nil ? "\(subject.name) · \(subject.bank.label)" : subject.name
    }

    // MARK: - Coverage and empty states

    private var coverageSection: some View {
        Section {
            HStack(spacing: MedxSpace.m) {
                MedxSymbolTile(
                    index.isBuilding ? "arrow.down.circle" : "exclamationmark.circle",
                    hue: MedxOutcome.flagged,
                    size: 36
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(index.isBuilding ? "Downloading…" : "Partly downloaded")
                    Text(index.coverageSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }

                Spacer(minLength: MedxSpace.s)

                if index.isBuilding {
                    Button("Stop") { index.cancelBuild() }
                        .medxSecondary(size: .small)
                } else {
                    Button("Finish") {
                        HapticManager.light()
                        index.build(subjects: subjects)
                    }
                    .medxSecondary(size: .small)
                    .disabled(subjects.isEmpty)
                }
            }
            .padding(.vertical, 2)

            ProgressView(value: index.coverage)
                .listRowSeparator(.hidden)
        } footer: {
            Text("Only the downloaded questions can be searched.")
        }
        .animation(.snappy, value: index.indexedCount)
    }

    private var emptyIndexSection: some View {
        Section {
            MedxEmptyState(
                "Not downloaded yet",
                symbol: MedxFeature.search.symbol,
                message: "Searching every question needs their text on this device once. Downloading them takes a few minutes and can be paused.",
                actionTitle: index.isBuilding ? "Downloading…" : "Set up offline search"
            ) {
                guard !index.isBuilding else { return }
                HapticManager.medium()
                index.build(subjects: subjects)
            }
        }
    }

    private var noMatchState: some View {
        MedxEmptyState(
            query.isEmpty && !filters.isActive ? "Search the bank" : "No matches",
            symbol: "magnifyingglass",
            message: query.isEmpty && !filters.isActive
                ? "Type at least two letters, or set a filter to browse — every image-based question you have got wrong, say."
                : "None of the \(MedxFormat.count(index.indexedCount)) questions matches that."
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Bank", selection: $filters.bank) {
                    Text("Both banks").tag(MedxBank?.none)
                    ForEach(MedxBank.allCases) { bank in
                        Text(bank.label).tag(MedxBank?.some(bank))
                    }
                }
                Picker("Subject", selection: $filters.subjectKey) {
                    Text("All subjects").tag(String?.none)
                    ForEach(pickableSubjects) { subject in
                        Text(subjectLabel(subject)).tag(String?.some(subject.id))
                    }
                }
                Picker("Status", selection: $filters.status) {
                    ForEach(MedxQuestionFilters.Status.allCases) { status in
                        Label(status.label, systemImage: status.icon).tag(status)
                    }
                }
                Divider()
                Toggle(isOn: $filters.imageBased) {
                    Label("Image-based only", systemImage: "photo")
                }
                Toggle(isOn: $filters.bookmarkedOnly) {
                    Label("Bookmarked only", systemImage: "bookmark")
                }
            } label: {
                Image(systemName: filters.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel("Filters")
            .accessibilityValue(filters.isActive ? filterSummary : "None")
        }

        ToolbarItem(placement: .topBarTrailing) {
            if isBuildingSitting {
                ProgressView()
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
                    Image(systemName: "play.circle")
                }
                .disabled(results.count < 2)
                .accessibilityLabel("Practise these")
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
    /// three-hundred-question paper by accident. The id is a hash of the questions, so the same
    /// search practised twice finds its saved sitting instead of orphaning it.
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
            let key = questions.map { String($0.id) }.sorted().joined(separator: ",")
            appState.startSitting(
                RunnerPayload(
                    kind: "qbank",
                    id: "search-" + MedxStableHash.of(key),
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
/// explanation, drawn with the runner's own rows. The module document is fetched on demand (and
/// cached by `FirestoreService`, so opening a second hit from the same module is instant).
struct MedxSearchResultDetailView: View {
    let entry: MedxIndexedQuestion
    let uid: String?

    @State private var question: Question?
    @State private var loadState: MedxLoadState = .loading
    @ObservedObject private var activityStore = ActivityStore.shared

    private var isBookmarked: Bool {
        guard let question else { return false }
        return activityStore.isBookmarked(questionId: question.id, sourceId: entry.moduleId, uid: uid)
    }

    private var reference: String {
        question?.reference?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var body: some View {
        List {
            switch loadState {
            case .loading:
                Section {
                    MedxPlaceholderRows(count: 4)
                }
            case .failed(let message):
                Section {
                    MedxEmptyState("Couldn't load it", symbol: "wifi.exclamationmark", message: message)
                }
            case .loaded:
                if let question {
                    Section {
                        questionBody(question)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(entry.subject)
        .navigationSubtitle("\(entry.bank.label) · \(entry.moduleName)")
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

    private func questionBody(_ question: Question) -> some View {
        VStack(alignment: .leading, spacing: MedxSpace.m) {
            if !entry.chapter.isEmpty {
                Text(entry.chapter)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HTMLRichTextView(html: question.displayText, fontSize: 16, weight: .semibold)

            if let images = question.images, !images.isEmpty {
                ForEach(images, id: \.self) { raw in
                    RunnerFigure(raw: raw)
                }
            }

            VStack(spacing: MedxSpace.s) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { pair in
                    QuestionOptionButton(
                        option: pair.element,
                        index: pair.offset,
                        isChosen: false,
                        isCorrect: question.isCorrect(optionId: pair.element.id),
                        isRevealed: true,
                        isLocked: true
                    ) {}
                }
            }

            if (question.explanation?.isEmpty == false) || !reference.isEmpty {
                VStack(alignment: .leading, spacing: MedxSpace.s) {
                    Label("Explanation", systemImage: "lightbulb.fill")
                        .font(.subheadline.weight(.semibold))

                    if let explanation = question.explanation, !explanation.isEmpty {
                        HTMLRichTextView(html: explanation, fontSize: 15, weight: .regular, textColor: .secondary)
                    }

                    if !reference.isEmpty {
                        Label(reference, systemImage: "book.closed")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.top, MedxSpace.xs)
            }
        }
        .padding(.vertical, MedxSpace.xs)
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
            loadState = .failed("Sign-in expired. Go back and try again.")
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
