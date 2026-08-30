import SwiftUI

/// Both question banks, one screen.
///
/// ARISE is the batch's own 1,211 modules cut by chapter; Marrow FMGE is 960 lesson-sized
/// modules plus 3,554 previous-year questions. They are seeded into the same Firestore
/// collection in the same shape and differ only in the `mw_` prefix on every id, so the
/// segmented control is a filter over one list rather than two code paths — and the runner
/// never learns that a second bank exists.
public struct QBankSubjectListView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var medxTheme = MedxAccentThemeStore.shared

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
    @State private var activeRunnerPayload: RunnerPayload?

    public init() {}

    private static let bankKey = "medx.qbank.bank"

    private var uid: String? { authService.currentSession?.uid }

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

    private var allQuestions: Int {
        subjects.reduce(0) { $0 + $1.questionCount }
    }

    public var body: some View {
        Group {
            switch loadState {
            case .loading:
                ProgressView("Loading both banks…")
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                failedState(message: message)
            case .loaded:
                if subjects.isEmpty {
                    ContentUnavailableView(
                        "No Subjects",
                        systemImage: "books.vertical",
                        description: Text("Question-bank subjects will appear here once they are published.")
                    )
                } else {
                    content
                }
            }
        }
        .background(MedxSurface.groupedBackground.ignoresSafeArea())
        .navigationTitle("Question Bank")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    HapticManager.light()
                    appState.open(route: .customModules)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Custom modules")

                Button {
                    HapticManager.light()
                    appState.open(route: .search(nil))
                } label: {
                    Image(systemName: "text.magnifyingglass")
                }
                .accessibilityLabel("Search all questions")

                ProfileSettingsButton()
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
        .fullScreenCover(item: $activeRunnerPayload) { (payload: RunnerPayload) in
            QuizRunnerView(payload: payload) {
                Task { await loadData() }
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                MedxPageHeader(
                    section: .qbank,
                    eyebrow: bank.eyebrow,
                    title: "Question Bank",
                    lead: "\(allQuestions.formatted()) questions across two banks. "
                        + "Marrow's ids are prefixed, so a module runs the same either way.",
                    sticker: bank.sticker
                )

                MedxSegmented(
                    section: .qbank,
                    segments: MedxBank.allCases.map {
                        MedxSegment(value: $0, label: $0.label, count: subjects(in: $0).count)
                    },
                    selection: $bank
                )
                .onChange(of: bank) { _, next in
                    UserDefaults.standard.set(next.rawValue, forKey: Self.bankKey)
                }

                MedxMetricsRow {
                    MedxMetric(
                        icon: "books.vertical.fill",
                        value: "\(subjects(in: bank).count)",
                        label: "subjects",
                        color: MedxTheme.primaryBlue
                    )
                    MedxMetric(
                        icon: "square.grid.2x2.fill",
                        value: bankTotals.modules.formatted(),
                        label: "modules",
                        color: MedxTheme.indigoAccent
                    )
                    MedxMetric(
                        icon: "questionmark.circle.fill",
                        value: bankTotals.questions.formatted(),
                        label: "questions",
                        color: MedxTheme.cyanAccent
                    )
                }

                bookmarksRow

                if shownSubjects.isEmpty {
                    emptyBankState
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        MedxSectionHeader("Subjects")

                        ForEach(Array(shownSubjects.enumerated()), id: \.element.id) { offset, subject in
                            subjectLink(subject, tilt: offset.isMultiple(of: 2) ? -6 : 6)
                        }
                    }
                }
            }
            .padding(.horizontal, MedxSurface.gutter)
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
        .refreshable {
            await loadData()
        }
    }

    private func subjectLink(_ subject: MedxBankSubject, tilt: Double) -> some View {
        NavigationLink {
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
            subjectRow(subject, tilt: tilt)
        }
        .buttonStyle(.plain)
        .medxScrollReveal()
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
    }

    private func subjectRow(_ subject: MedxBankSubject, tilt: Double) -> some View {
        let practised = practisedBySubject[subject.id] ?? 0
        let fraction = subject.moduleCount > 0
            ? Double(practised) / Double(subject.moduleCount)
            : 0

        return HStack(spacing: 14) {
            MedxSticker(MedxSubjectArt.sticker(for: subject.name), size: 30, tilt: tilt)
                .frame(width: 40, height: 40)
                .background(MedxSection.qbank.soft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(subject.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text("\(subject.moduleCount) modules · \(subject.questionCount.formatted()) questions")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if practised > 0 {
                    HStack(spacing: 6) {
                        ProgressView(value: fraction)
                            .tint(MedxTheme.successGreen)
                            .frame(maxWidth: 92)
                        Text("\(practised) done")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(MedxTheme.successGreen)
                    }
                }
            }

            Spacer(minLength: 0)

            MedxDisclosure()
        }
        .padding(14)
        .frame(minHeight: 68)
        .medxCard()
        .contentShape(RoundedRectangle(cornerRadius: MedxSurface.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subject.name)
        .accessibilityValue("\(subject.bank.label), \(subject.moduleCount) modules, \(practised) practised")
    }

    private var bookmarksRow: some View {
        NavigationLink {
            BookmarkedQuestionsView(uid: uid)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MedxTheme.primaryPurple)
                    .frame(width: 34, height: 34)
                    .background(MedxTheme.primaryPurple.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                Text("Bookmarked questions")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Text("\(activityStore.bookmarks(for: uid).count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)

                MedxDisclosure()
            }
            .padding(14)
            .medxCard()
            .contentShape(RoundedRectangle(cornerRadius: MedxSurface.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bookmarked questions")
        .accessibilityValue("\(activityStore.bookmarks(for: uid).count) saved")
    }

    // MARK: - States

    /// Reached when a bank came back empty. Marrow is the one that can: it is a single seeded
    /// document, and if it has not been written the segment should say so rather than looking
    /// like a failed fetch.
    private var emptyBankState: some View {
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
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
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
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
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
            loadState = .loaded

            // The subject tree is the only place the module list exists, so this is where
            // Spotlight and the index's progress denominator get their numbers. Both are still
            // ARISE-only — they are keyed on an integer subject id — so the Marrow subjects
            // drop out here rather than being coerced into a shape they do not fit.
            let ariseTree = loadedSubjects.compactMap { $0.asQBankSubject }
            MedxQuestionIndexStore.shared.noteExpectations(subjects: ariseTree)
            Task { await MedxSpotlightIndexer.shared.indexModules(ariseTree) }
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
