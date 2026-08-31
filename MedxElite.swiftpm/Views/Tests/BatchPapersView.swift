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
                .navigationTitle("Batch papers")
        // Large, and the only place the words appear — there used to be an inline title and a
        // an in-content header repeating them.
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
        List {
            heroSection

            if matchingTests.isEmpty {
                Section { noMatchesState.medxPlainRow() }
            } else {
                if !scoredTests.isEmpty {
                    paperSection(
                        title: "Scored papers",
                        footer: "Official answer key available.",
                        tests: scoredTests
                    )
                }

                if !practiceTests.isEmpty {
                    paperSection(
                        title: "Practice papers",
                        footer: "Answerable, but the source withheld the key.",
                        tests: practiceTests
                    )
                }
            }
        }
        .medxList()
        .refreshable {
            await load()
        }
    }

    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(tests.count)")
                    .font(MedxType.display)
                    .contentTransition(.numericText())

                Text("ARISE papers · \(tests.filter(\.gradable).count) keyed · \(Set(attempts.map(\.sourceId)).count) attempted")
                    .medxTag()

                Picker("Scope", selection: $scope) {
                    ForEach(TestScope.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .medxPlainRow()
        }
    }

    private func paperSection(title: String, footer: String, tests: [BatchTest]) -> some View {
        Section {
            ForEach(tests) { test in
                TestDetailCard(test: test, attempts: attempts) { mode in
                    start(test: test, mode: mode)
                }
                .medxListRow()
            }
        } header: {
            MedxHeader(title, count: tests.count)
        } footer: {
            Text(footer)
        }
    }

    // MARK: - States

    private var loadingState: some View {
        List {
            ForEach(0..<4, id: \.self) { _ in
                MedxRow(lead: "100", title: "Batch paper", detail: "100 q · 100 min")
                    .medxListRow()
            }
        }
        .medxList()
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityLabel("Loading batch papers")
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
