import SwiftUI

public struct QBankSubjectListView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var activityStore = ActivityStore.shared

    @State private var subjects: [QBankSubject] = []
    @State private var attempts: [SittingAttempt] = []
    /// Module ids that have at least one recorded sitting, and the per-subject tally.
    /// Both are derived once per load: walking 1,211 modules inside `body` was the single
    /// most expensive thing on this screen.
    @State private var practisedModuleIds: Set<String> = []
    @State private var practisedBySubject: [Int: Int] = [:]
    @State private var searchText = ""
    @State private var loadState: MedxLoadState = .loading
    @State private var activeRunnerPayload: RunnerPayload?

    public init() {}

    private var uid: String? { authService.currentSession?.uid }

    private var filteredSubjects: [QBankSubject] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return subjects }
        return subjects.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private var totalQuestions: Int {
        subjects.reduce(0) { $0 + ($1.questionCount ?? 0) }
    }

    private var totalModules: Int {
        subjects.reduce(0) { $0 + $1.moduleCount }
    }

    public var body: some View {
        Group {
            switch loadState {
            case .loading:
                ProgressView("Loading question bank…")
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
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
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
            await loadData()
        }
        .fullScreenCover(item: $activeRunnerPayload) { (payload: RunnerPayload) in
            QuizRunnerView(payload: payload) {
                Task { await loadData() }
            }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                MedxMetricsRow {
                    MedxMetric(
                        icon: "books.vertical.fill",
                        value: "\(subjects.count)",
                        label: "subjects",
                        color: MedxTheme.primaryBlue
                    )
                    MedxMetric(
                        icon: "square.grid.2x2.fill",
                        value: totalModules.formatted(),
                        label: "modules",
                        color: MedxTheme.indigoAccent
                    )
                    MedxMetric(
                        icon: "questionmark.circle.fill",
                        value: totalQuestions.formatted(),
                        label: "questions",
                        color: MedxTheme.cyanAccent
                    )
                }

                bookmarksRow

                if filteredSubjects.isEmpty {
                    ContentUnavailableView {
                        Label("No Matches", systemImage: "magnifyingglass")
                    } description: {
                        Text("No subject matches “\(searchText)”.")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        MedxSectionHeader("Subjects")

                        ForEach(filteredSubjects) { subject in
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
                                subjectRow(subject)
                            }
                            .buttonStyle(.plain)
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

    private func subjectRow(_ subject: QBankSubject) -> some View {
        let practised = practisedBySubject[subject.subjectId] ?? 0
        let fraction = subject.moduleCount > 0
            ? Double(practised) / Double(subject.moduleCount)
            : 0

        return HStack(spacing: 14) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MedxTheme.primaryBlue)
                .frame(width: 38, height: 38)
                .background(MedxTheme.primaryBlue.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(subject.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text("\(subject.moduleCount) modules · \((subject.questionCount ?? 0).formatted()) questions")
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
        .frame(minHeight: 66)
        .medxCard()
        .contentShape(RoundedRectangle(cornerRadius: MedxSurface.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subject.name)
        .accessibilityValue("\(subject.moduleCount) modules, \(practised) practised")
    }

    // MARK: - Data

    private func loadData() async {
        guard let uid else {
            loadState = .loaded
            return
        }
        do {
            let token = try await authService.getValidIdToken()
            async let subjectsTask = FirestoreService.shared.fetchQBankSubjects(idToken: token)
            async let attemptsTask = FirestoreService.shared.fetchUserAttempts(uid: uid, idToken: token)

            let (loadedSubjects, loadedAttempts) = try await (subjectsTask, attemptsTask)
            subjects = loadedSubjects
            attempts = loadedAttempts
            recomputePractised()
            loadState = .loaded
        } catch {
            loadState = subjects.isEmpty
                ? .failed("Check your connection and try again.")
                : .loaded
        }
    }

    private func recomputePractised() {
        let practised = Set(attempts.filter { $0.kind == "qbank" }.map(\.sourceId))
        practisedModuleIds = practised

        var tally: [Int: Int] = [:]
        for subject in subjects {
            var count = 0
            for chapter in subject.chapters ?? [] {
                for module in chapter.modules ?? [] where practised.contains(module.id) {
                    count += 1
                }
            }
            tally[subject.subjectId] = count
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
