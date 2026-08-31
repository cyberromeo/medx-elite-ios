import SwiftUI

/// Both question banks, one screen.
///
/// ARISE is the batch's own 1,211 modules cut by chapter; Marrow FMGE is 960 lesson-sized modules plus
/// 3,554 previous-year questions. They are seeded into the same Firestore collection in the same shape
/// and differ only in the `mw_` prefix on every id, so the picker is a filter over one list rather than
/// two code paths — and the runner never learns that a second bank exists.
///
/// The hero is coverage: one cell per subject, filled once every module in it has been sat. 32,467
/// questions is not a number anyone can act on, but "four of twenty subjects touched" is.
public struct QBankSubjectListView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var appState = AppState.shared

    @State private var subjects: [MedxBankSubject] = []
    @State private var attempts: [SittingAttempt] = []
    /// Module ids that have at least one recorded sitting, and the per-subject tally. Both are derived
    /// once per load: walking 2,171 modules inside `body` was the single most expensive thing here.
    @State private var practisedModuleIds: Set<String> = []
    @State private var practisedBySubject: [String: Int] = [:]
    @State private var bank: MedxBank = .arise
    @State private var searchText = ""
    @State private var loadState: MedxLoadState = .loading
    @State private var activeRunnerPayload: RunnerPayload?

    /// The filtered subject list and the bank's totals, folded in `refilter()`. Both were computed
    /// properties read from `body`, so they re-ran on every keystroke and every unrelated publish.
    @State private var shownSubjects: [MedxBankSubject] = []
    @State private var bankTotals = (modules: 0, questions: 0, subjects: 0)

    public init() {}

    private static let bankKey = "medx.qbank.bank"

    private var uid: String? { authService.currentSession?.uid }

    // MARK: - Body

    public var body: some View {
        Group {
            switch loadState {
            case .loading:
                ProgressView("Loading both banks…")
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .medxPage()
            case .failed(let message):
                failedState(message: message)
            case .loaded:
                content
            }
        }
        .navigationTitle("Question Bank")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    HapticManager.light()
                    appState.open(route: .search(nil))
                } label: {
                    Image(systemName: "text.magnifyingglass")
                }
                .accessibilityLabel("Search all questions")

                MedxSettingsMonogram()
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search subjects"
        )
        .task {
            guard case .loading = loadState else { return }
            bank = MedxBank(rawValue: UserDefaults.standard.string(forKey: Self.bankKey) ?? "") ?? .arise
            await loadData()
        }
        .onChange(of: bank) { _, next in
            UserDefaults.standard.set(next.rawValue, forKey: Self.bankKey)
            refilter()
        }
        .onChange(of: searchText) { _, _ in
            refilter()
        }
        .fullScreenCover(item: $activeRunnerPayload) { (payload: RunnerPayload) in
            QuizRunnerView(payload: payload) {
                Task { await loadData() }
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        List {
            heroSection

            Section {
                bookmarksRow
                customModulesRow
            }

            if shownSubjects.isEmpty {
                emptyBankSection
            } else {
                Section {
                    ForEach(shownSubjects) { subject in
                        subjectRow(subject)
                    }
                } header: {
                    MedxHeader("Subjects", count: shownSubjects.count)
                }
            }
        }
        .medxList()
        .refreshable {
            await loadData()
        }
    }

    /// The bank's size, its coverage sheet, and the picker.
    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text(bankTotals.questions.formatted())
                    .font(MedxType.display)
                    .contentTransition(.numericText())

                Text("\(bank.eyebrow) · \(bankTotals.modules.formatted()) modules")
                    .medxTag()

                MedxAnswerSheet(cells: coverageCells, scale: .sheet, label: coverageSummary)

                Picker("Bank", selection: $bank) {
                    ForEach(MedxBank.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .medxPlainRow()
        }
    }

    /// One cell per subject in the bank, in the order the list shows them — so a cell on the sheet and a
    /// row below it are the same subject, and the sheet is a legend for the list rather than an
    /// ornament. Filled once every module in that subject has been sat; the accent means started.
    private var coverageCells: [MedxSheetCell] {
        let inBank = subjects.filter { $0.bank == bank }
        guard !inBank.isEmpty else { return [MedxSheetCell](repeating: .pending, count: 24) }

        return inBank.map { subject in
            let practised = practisedBySubject[subject.id] ?? 0
            if practised == 0 { return .pending }
            return practised >= subject.moduleCount ? .correct : .answered
        }
    }

    private var coverageSummary: String {
        let cells = coverageCells
        let done = cells.filter { $0 == .correct }.count
        let started = cells.filter { $0 == .answered }.count
        return "\(done) subjects finished, \(started) started, of \(cells.count)"
    }

    // MARK: - Rows

    private func subjectRow(_ subject: MedxBankSubject) -> some View {
        let practised = practisedBySubject[subject.id] ?? 0
        let fraction = subject.moduleCount > 0 ? Double(practised) / Double(subject.moduleCount) : 0

        return NavigationLink {
            QBankChapterView(
                subject: subject,
                practisedModuleIds: practisedModuleIds,
                attempts: attempts
            ) { module, mode in
                startSession(
                    moduleId: module.id,
                    subjectName: subject.name,
                    moduleName: module.name,
                    mode: mode
                )
            }
        } label: {
            MedxRow(
                lead: subject.moduleCount.formatted(),
                title: subject.name,
                detail: "\(subject.questionCount.formatted()) questions"
            ) {
                if practised > 0 {
                    MedxAnswerSheet(
                        fraction: fraction,
                        label: "\(practised) of \(subject.moduleCount) modules sat"
                    )
                } else {
                    EmptyView()
                }
            }
        }
        .medxListRow()
        // Long press to go straight at the subject without walking its chapter tree first.
        .contextMenu {
            Button {
                HapticManager.light()
                appState.open(route: .search(subject.name))
            } label: {
                Label("Search \(subject.name)", systemImage: "text.magnifyingglass")
            }
            Button {
                HapticManager.light()
                appState.open(route: .customModules)
            } label: {
                Label("Build a custom module", systemImage: "slider.horizontal.3")
            }
        }
        .accessibilityValue("\(subject.bank.label), \(subject.moduleCount) modules, \(practised) practised")
    }

    private var bookmarksRow: some View {
        NavigationLink {
            BookmarkedQuestionsView(uid: uid)
        } label: {
            MedxRow(title: "Bookmarked questions", detail: "Questions you kept") {
                let count = activityStore.bookmarks(for: uid).count
                if count > 0 {
                    MedxBadge("\(count)")
                } else {
                    EmptyView()
                }
            }
        }
        .medxListRow()
    }

    /// Moved out of the toolbar, where it was an unlabelled slider glyph next to two others. A row with
    /// the words on it is discoverable; three abstract icons in a navigation bar are a guessing game.
    private var customModulesRow: some View {
        Button {
            HapticManager.light()
            appState.open(route: .customModules)
        } label: {
            MedxRow(title: "Custom modules", detail: "Papers either of you saved")
        }
        .buttonStyle(.plain)
        .medxListRow()
    }

    // MARK: - States

    /// Reached when a bank came back empty. Marrow is the one that can: it is a single seeded document,
    /// and if it has not been written the segment should say so rather than looking like a failed fetch.
    private var emptyBankSection: some View {
        Section {
            ContentUnavailableView {
                Label(
                    searchText.isEmpty ? "\(bank.label) is not seeded yet" : "No Matches",
                    systemImage: searchText.isEmpty ? "tray" : "magnifyingglass"
                )
            } description: {
                Text(searchText.isEmpty
                     ? "Nothing has been published to this bank. The other one is unaffected."
                     : "No subject matches “\(searchText)”.")
            }
            .medxPlainRow()
        }
    }

    private func failedState(message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't Load the Bank", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                HapticManager.light()
                loadState = .loading
                Task { await loadData() }
            }
            .medxFilledButton()
            .buttonBorderShape(.capsule)
        }
        .medxPage()
    }

    // MARK: - Data

    private func loadData() async {
        guard let uid else {
            loadState = .loaded
            return
        }
        do {
            let token = try await authService.getValidIdToken()
            async let subjectsTask = FirestoreService.shared.fetchQBankBanks(idToken: token)
            async let attemptsTask = FirestoreService.shared.fetchUserAttempts(uid: uid, idToken: token)

            let (loadedSubjects, loadedAttempts) = try await (subjectsTask, attemptsTask)
            subjects = loadedSubjects
            attempts = loadedAttempts
            recomputePractised()
            refilter()
            loadState = .loaded

            // The subject tree is the only place the module list exists, so this is where Spotlight and
            // the index's progress denominator get their numbers.
            MedxQuestionIndexStore.shared.noteExpectations(subjects: loadedSubjects)
            Task { await MedxSpotlightIndexer.shared.indexModules(loadedSubjects) }
        } catch {
            loadState = subjects.isEmpty
                ? .failed("Check your connection and try again.")
                : .loaded
        }
    }

    /// Filter by bank, then by query, then total what is left. The one place any of that happens.
    private func refilter() {
        let inBank = subjects.filter { $0.bank == bank }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        shownSubjects = query.isEmpty
            ? inBank
            : inBank.filter { $0.name.localizedCaseInsensitiveContains(query) }

        bankTotals = inBank.reduce(into: (modules: 0, questions: 0, subjects: 0)) { totals, subject in
            totals.modules += subject.moduleCount
            totals.questions += subject.questionCount
            totals.subjects += 1
        }
    }

    private func recomputePractised() {
        let practised = Set(attempts.filter { $0.kind == "qbank" }.map(\.sourceId))
        practisedModuleIds = practised

        var tally: [String: Int] = [:]
        for subject in subjects {
            tally[subject.id] = subject.modules.reduce(0) {
                practised.contains($1.id) ? $0 + 1 : $0
            }
        }
        practisedBySubject = tally
    }

    private func startSession(moduleId: String, subjectName: String, moduleName: String, mode: SittingMode) {
        activeRunnerPayload = RunnerPayload(
            kind: "qbank",
            id: moduleId,
            name: moduleName,
            subject: subjectName,
            mode: mode,
            gradable: true
        )
    }
}
