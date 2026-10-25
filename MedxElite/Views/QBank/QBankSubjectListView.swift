import SwiftUI

/// Both question banks, one screen.
///
/// ARISE is the batch's own 1,211 modules cut by chapter; Marrow FMGE is 960 lesson-sized
/// modules plus 3,554 previous-year questions. They are seeded into the same Firestore
/// collection in the same shape and differ only in the `mw_` prefix on every id, so the
/// segmented control is a filter over one list rather than two code paths — and the runner
/// never learns that a second bank exists.
///
/// A grouped list: the bank switch, three figures, then one row a subject. Search and custom
/// modules are Library doors and bookmarks are under Yours there, so the toolbar holds the
/// profile button and nothing else.
public struct QBankSubjectListView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var appState = AppState.shared

    @State private var subjects: [MedxBankSubject] = []
    @State private var attempts: [SittingAttempt] = []
    /// Module ids that have at least one recorded sitting, and the per-subject tally. Both are
    /// derived once per load: walking 2,171 modules inside `body` was the single most expensive
    /// thing on this screen.
    @State private var practisedModuleIds: Set<String> = []
    @State private var practisedBySubject: [String: Int] = [:]
    @State private var bank: MedxBank = .arise
    @State private var searchText = ""
    @State private var loadState: MedxLoadState = .loading

    public init() {}

    private static let bankKey = "medx.qbank.bank"

    #if DEBUG
    @State private var debugSubject: MedxBankSubject?
    #endif

    private var uid: String? { authService.currentSession?.uid }

    private var isLoading: Bool { loadState == .loading && subjects.isEmpty }

    private func subjects(in bank: MedxBank) -> [MedxBankSubject] {
        subjects.filter { $0.bank == bank }
    }

    private var shownSubjects: [MedxBankSubject] {
        let inBank = subjects(in: bank)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return inBank }
        return inBank.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var bankTotals: (modules: Int, questions: Int) {
        subjects(in: bank).reduce(into: (0, 0)) { totals, subject in
            totals.0 += subject.moduleCount
            totals.1 += subject.questionCount
        }
    }

    public var body: some View {
        Group {
            if case .failed(let message) = loadState, subjects.isEmpty {
                MedxEmptyState(
                    "Couldn't load the bank",
                    symbol: "wifi.exclamationmark",
                    message: message,
                    actionTitle: "Try again"
                ) {
                    HapticManager.light()
                    loadState = .loading
                    Task { await loadData() }
                }
            } else {
                list
            }
        }
        .navigationTitle(MedxFeature.qbank.title)
        .navigationSubtitle(bank.eyebrow)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                MedxProfileButton()
            }
        }
        .searchable(text: $searchText, prompt: "Search subjects")
        .searchToolbarBehavior(.minimize)
        .task {
            guard case .loading = loadState else { return }
            bank = MedxBank(rawValue: UserDefaults.standard.string(forKey: Self.bankKey) ?? "") ?? .arise
            await medxLoadRevalidating { await loadData() }
        }
        .onChange(of: bank) { _, next in
            UserDefaults.standard.set(next.rawValue, forKey: Self.bankKey)
        }
        .onReceive(NotificationCenter.default.publisher(for: .medxContentShouldRefresh)) { _ in
            Task { await loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .medxSittingDidFinish)) { _ in
            Task { await loadData() }
        }
        #if DEBUG
        // Screenshot runs only (`-medxScreen subject`): walks into the first subject once the
        // bank has loaded, so the chapter screen can be captured without a tap.
        .navigationDestination(item: $debugSubject) { subject in
            chapterView(subject)
        }
        .onChange(of: subjects.count) { _, count in
            guard count > 0, debugSubject == nil,
                  UserDefaults.standard.string(forKey: "medxScreen") == "subject" else { return }
            let pool = subjects(in: bank)
            debugSubject = pool.first { $0.name.localizedCaseInsensitiveContains("micro") } ?? pool.first
        }
        #endif
    }

    // MARK: - List

    private var list: some View {
        List {
            Section {
                Picker("Bank", selection: $bank) {
                    ForEach(MedxBank.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                MedxStatRow {
                    MedxStatTile(
                        "\(subjects(in: bank).count)",
                        label: "subjects",
                        symbol: "books.vertical.fill",
                        hue: MedxFeature.qbank.color
                    )
                    MedxStatTile(
                        MedxFormat.count(bankTotals.modules),
                        label: "modules",
                        symbol: "square.grid.2x2.fill",
                        hue: MedxFeature.customModules.color
                    )
                    MedxStatTile(
                        MedxFormat.count(bankTotals.questions),
                        label: "questions",
                        symbol: "questionmark.circle.fill",
                        hue: MedxFeature.search.color
                    )
                }
                .padding(.vertical, MedxSpace.xs)
                .redacted(reason: isLoading ? .placeholder : [])
            }

            if isLoading {
                Section("Subjects") {
                    MedxPlaceholderRows(count: 8)
                }
            } else if shownSubjects.isEmpty {
                Section {
                    emptyBankState
                }
            } else {
                Section("Subjects") {
                    ForEach(shownSubjects) { subject in
                        subjectLink(subject)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            // A pull always reaches the backend: cached copies are kept for offline, never
            // served in place of a fresh read the student asked for.
            await CacheManager.shared.markAllStale()
            await loadData()
        }
    }

    private func chapterView(_ subject: MedxBankSubject) -> some View {
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
    }

    private func subjectLink(_ subject: MedxBankSubject) -> some View {
        NavigationLink {
            chapterView(subject)
        } label: {
            subjectRow(subject)
        }
        // Long press to go straight at the subject without walking its chapter tree first.
        .contextMenu {
            Button {
                HapticManager.light()
                appState.open(route: .search(subject.name))
            } label: {
                Label("Search \(subject.name)", systemImage: MedxFeature.search.symbol)
            }
            Button {
                HapticManager.light()
                appState.open(route: .customModules)
            } label: {
                Label("Build a custom module", systemImage: MedxFeature.customModules.symbol)
            }
        }
    }

    private func subjectRow(_ subject: MedxBankSubject) -> some View {
        let practised = practisedBySubject[subject.id] ?? 0

        return HStack(spacing: MedxSpace.m) {
            MedxSymbolTile(MedxSubjectArt.symbol(for: subject.name), hue: MedxFeature.qbank.color, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(subject.name)
                Text("\(subject.moduleCount) modules · \(MedxFormat.count(subject.questionCount)) questions")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if practised > 0 {
                    ProgressView(value: Double(practised), total: Double(max(subject.moduleCount, 1)))
                        .tint(MedxOutcome.correct)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: MedxSpace.s)

            if practised > 0 {
                Text("\(practised) of \(subject.moduleCount)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subject.name)
        .accessibilityValue("\(subject.bank.label), \(subject.moduleCount) modules, \(practised) practised")
    }

    /// Reached when a bank came back empty. Marrow is the one that can: it is a single seeded
    /// document, and if it has not been written the segment should say so rather than looking
    /// like a failed fetch.
    private var emptyBankState: some View {
        MedxEmptyState(
            searchText.isEmpty ? "\(bank.label) is not seeded yet" : "No matches",
            symbol: searchText.isEmpty ? "tray" : "magnifyingglass",
            message: searchText.isEmpty
                ? "Nothing has been published to this bank. The other one is unaffected."
                : "No subject matches “\(searchText)”."
        )
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
            // The attempts only paint the "practised" badges; a refused read must not take the
            // whole bank down with it — a new profile offline still has the subjects cached.
            async let attemptsTask = FirestoreService.shared.fetchUserAttemptsOrEmpty(uid: uid, idToken: token)

            let (loadedSubjects, loadedAttempts) = try await (subjectsTask, attemptsTask)
            subjects = loadedSubjects
            attempts = loadedAttempts
            recomputePractised()
            loadState = .loaded

            // The subject tree is the only place the module list exists, so this is where
            // Spotlight and the index's progress denominator get their numbers. Both cover both
            // banks: the index keys on `MedxBankSubject.id` as a string, and Spotlight only ever
            // wanted the names.
            MedxQuestionIndexStore.shared.noteExpectations(subjects: loadedSubjects)
            Task { await MedxSpotlightIndexer.shared.indexModules(loadedSubjects) }
        } catch {
            loadState = subjects.isEmpty
                ? .failed("Check your connection and try again.")
                : .loaded
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
        appState.startSitting(
            RunnerPayload(
                kind: "qbank",
                id: moduleId,
                name: moduleName,
                subject: subjectName,
                mode: mode,
                gradable: true
            )
        )
    }
}
