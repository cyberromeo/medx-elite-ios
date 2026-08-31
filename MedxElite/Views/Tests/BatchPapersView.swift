import SwiftUI

/// The four ARISE batch papers.
///
/// This screen *is* the old Tests tab — the scored/practice split, the scope filter and the
/// prior-attempt stats, moved wholesale when the tab itself became the Marrow FMGE series.
/// They are only four papers and most of them exported without an answer key, so a tab of
/// their own was more room than they earn; they live in the Library now and are linked from
/// the top of Tests.
public struct BatchPapersView: View {
    @ObservedObject private var authService = AuthService.shared

    @State private var tests: [BatchTest] = []
    @State private var attempts: [SittingAttempt] = []
    @State private var loadState: MedxLoadState = .loading
    @State private var activeRunnerPayload: RunnerPayload?
    @State private var searchText = ""
    @State private var scope: TestScope = .all

    public init() {}

    private var uid: String? { authService.currentSession?.uid }

    private var matchingTests: [BatchTest] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return tests.filter { test in
            let matchesScope: Bool
            switch scope {
            case .all: matchesScope = true
            case .scored: matchesScope = test.gradable
            case .practice: matchesScope = !test.gradable
            }
            guard matchesScope else { return false }
            guard !query.isEmpty else { return true }
            return test.name.localizedCaseInsensitiveContains(query)
                || test.subject.localizedCaseInsensitiveContains(query)
                || (test.batch ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private var scoredTests: [BatchTest] { matchingTests.filter(\.gradable) }
    private var practiceTests: [BatchTest] { matchingTests.filter { !$0.gradable } }

    public var body: some View {
        Group {
            switch loadState {
            case .loading:
                loadingState
            case .failed(let message):
                failedState(message: message)
            case .loaded:
                if tests.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
        }
        .medxPage(.tests)
        .navigationTitle("Batch papers")
        // Large, and the only place the words appear — there used to be an inline title and a
        // `MedxPageHeader` repeating them.
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search batch papers"
        )
        .task {
            guard case .loading = loadState else { return }
            await load()
        }
        .fullScreenCover(item: $activeRunnerPayload) { (payload: RunnerPayload) in
            QuizRunnerView(payload: payload) {
                Task { await load() }
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                MedxPageCaption("ARISE · the batch's own four · most exported without a key")

                summaryRow

                MedxSegmented(
                    section: .tests,
                    segments: TestScope.allCases.map {
                        MedxSegment(value: $0, label: $0.title)
                    },
                    selection: $scope
                )

                if matchingTests.isEmpty {
                    noMatchesState
                } else {
                    if !scoredTests.isEmpty {
                        section(
                            title: "Scored papers",
                            subtitle: "Official answer key available",
                            tests: scoredTests
                        )
                    }

                    if !practiceTests.isEmpty {
                        section(
                            title: "Practice papers",
                            subtitle: "Answerable, but the source withheld the key",
                            tests: practiceTests
                        )
                    }
                }
            }
            .padding(.horizontal, MedxDS.gutter)
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
        .refreshable {
            await load()
        }
    }

    private var summaryRow: some View {
        MedxMetricsRow {
            MedxMetric(
                icon: "checkmark.seal.fill",
                value: "\(tests.filter(\.gradable).count)",
                label: "scored",
                color: MedxDS.correct
            )
            MedxMetric(
                icon: "doc.text.fill",
                value: "\(tests.filter { !$0.gradable }.count)",
                label: "practice",
                color: MedxDS.warn
            )
            MedxMetric(
                icon: "flag.pattern.checkered",
                value: "\(Set(attempts.map(\.sourceId)).count)",
                label: "attempted",
                color: MedxCandy.tangerine
            )
        }
    }

    private func section(title: String, subtitle: String, tests: [BatchTest]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MedxSectionHeader(title, subtitle: subtitle)

            ForEach(tests) { test in
                TestDetailCard(test: test, attempts: attempts) { mode in
                    start(test: test, mode: mode)
                }
            }
        }
    }

    // MARK: - States

    private var loadingState: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    skeletonCard
                }
            }
            .padding(.horizontal, MedxDS.gutter)
            .padding(.top, 8)
        }
        .allowsHitTesting(false)
        .accessibilityLabel("Loading batch papers")
    }

    private var skeletonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(height: 16)
                .frame(maxWidth: 220)
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .frame(height: 11)
                .frame(maxWidth: 150)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .medxCard()
        .redacted(reason: .placeholder)
    }

    /// Reached when the fetch succeeded but the collection came back with nothing. This screen
    /// used to render an empty `ScrollView` in that case, which read as a bug.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No batch papers", systemImage: "doc.text.magnifyingglass")
        } description: {
            Text("None have been published to your account. Pull to refresh once they are.")
        } actions: {
            Button("Refresh") {
                HapticManager.light()
                Task { await load() }
            }
            .medxFilledButton()
            .buttonBorderShape(.capsule)
        }
    }

    private func failedState(message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load the papers", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                HapticManager.light()
                loadState = .loading
                Task { await load() }
            }
            .medxFilledButton()
            .buttonBorderShape(.capsule)
        }
    }

    private var noMatchesState: some View {
        ContentUnavailableView {
            Label("No Matches", systemImage: "magnifyingglass")
        } description: {
            Text(searchText.isEmpty
                 ? "No paper matches this filter."
                 : "No paper matches “\(searchText)”.")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }

    // MARK: - Data

    private func load() async {
        guard let uid else {
            loadState = .loaded
            return
        }
        do {
            let token = try await authService.getValidIdToken()
            async let testsTask = FirestoreService.shared.fetchTests(idToken: token)
            async let attemptsTask = FirestoreService.shared.fetchUserAttempts(uid: uid, idToken: token)

            let (loadedTests, loadedAttempts) = try await (testsTask, attemptsTask)
            tests = loadedTests
            attempts = loadedAttempts.filter { $0.kind == "test" }
            loadState = .loaded
        } catch {
            loadState = tests.isEmpty
                ? .failed("Check your connection and try again.")
                : .loaded
        }
    }

    private func start(test: BatchTest, mode: SittingMode) {
        HapticManager.medium()
        activeRunnerPayload = RunnerPayload(
            kind: "test",
            id: test.testId,
            name: test.name,
            subject: test.subject,
            mode: mode,
            gradable: test.gradable,
            // The batch papers carry their own official duration; only fall back to one minute
            // a question when the export did not include one.
            examSeconds: test.officialTimeMins > 0 ? test.officialTimeMins * 60 : nil
        )
    }
}

// MARK: - Supporting types

enum TestScope: String, CaseIterable, Identifiable {
    case all, scored, practice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .scored: return "Scored"
        case .practice: return "Practice"
        }
    }
}
