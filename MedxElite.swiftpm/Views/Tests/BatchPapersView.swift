import SwiftUI

/// The four ARISE batch papers, one level under Tests.
///
/// This screen *was* the old Tests tab — the scored/practice split, the scope filter and the
/// prior-attempt stats, moved wholesale when the tab itself became the Marrow FMGE series.
/// They are only four papers and most of them exported without an answer key, so a tab of
/// their own was more room than they earn.
public struct BatchPapersView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var appState = AppState.shared

    @State private var tests: [BatchTest] = []
    @State private var attempts: [SittingAttempt] = []
    @State private var loadState: MedxLoadState = .loading
    @State private var searchText = ""
    @State private var scope: TestScope = .all

    public init() {}

    private var uid: String? { authService.currentSession?.uid }

    private var isLoading: Bool { loadState == .loading && tests.isEmpty }

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

    private var subtitle: String {
        guard !tests.isEmpty else { return "The batch's own papers" }
        let scored = tests.filter(\.gradable).count
        return "\(scored) scored · \(tests.count - scored) practice"
    }

    public var body: some View {
        Group {
            if case .failed(let message) = loadState, tests.isEmpty {
                MedxEmptyState(
                    "Couldn't load the papers",
                    symbol: "wifi.exclamationmark",
                    message: message,
                    actionTitle: "Try again"
                ) {
                    HapticManager.light()
                    loadState = .loading
                    Task { await load() }
                }
            } else if loadState == .loaded, tests.isEmpty {
                // The fetch succeeded and the collection came back with nothing. This screen used
                // to render an empty page in that case, which read as a bug.
                MedxEmptyState(
                    "No batch papers",
                    symbol: "doc.text.magnifyingglass",
                    message: "None have been published to your account yet.",
                    actionTitle: "Refresh"
                ) {
                    HapticManager.light()
                    Task { await load() }
                }
            } else {
                list
            }
        }
        .navigationTitle(MedxFeature.batchPapers.title)
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search batch papers")
        .task {
            guard case .loading = loadState else { return }
            await medxLoadRevalidating { await load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .medxContentShouldRefresh)) { _ in
            Task { await load() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .medxSittingDidFinish)) { _ in
            Task { await load() }
        }
    }

    // MARK: - List

    private var list: some View {
        List {
            Section {
                Picker("Scope", selection: $scope) {
                    ForEach(TestScope.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                MedxStatRow {
                    MedxStatTile(
                        "\(tests.filter(\.gradable).count)",
                        label: "scored",
                        symbol: "checkmark.seal.fill",
                        hue: MedxOutcome.correct
                    )
                    MedxStatTile(
                        "\(tests.filter { !$0.gradable }.count)",
                        label: "practice",
                        symbol: "doc.text.fill",
                        hue: MedxOutcome.pending
                    )
                    MedxStatTile(
                        "\(Set(attempts.map(\.sourceId)).count)",
                        label: "attempted",
                        symbol: MedxFeature.batchPapers.symbol,
                        hue: MedxFeature.batchPapers.color
                    )
                }
                .padding(.vertical, MedxSpace.xs)
                .redacted(reason: isLoading ? .placeholder : [])
            }

            if isLoading {
                Section {
                    MedxPlaceholderRows(count: 4)
                }
            } else if matchingTests.isEmpty {
                Section {
                    MedxEmptyState(
                        "No matches",
                        symbol: "magnifyingglass",
                        message: searchText.isEmpty
                            ? "No paper matches this filter."
                            : "No paper matches “\(searchText)”."
                    )
                }
            } else {
                if !scoredTests.isEmpty {
                    Section {
                        ForEach(scoredTests) { test in
                            row(test)
                        }
                    } header: {
                        Text("Scored papers")
                    } footer: {
                        Text("Marked against the official answer key.")
                    }
                }

                if !practiceTests.isEmpty {
                    Section {
                        ForEach(practiceTests) { test in
                            row(test)
                        }
                    } header: {
                        Text("Practice papers")
                    } footer: {
                        Text("The source withheld these papers' answer keys, so they can be answered but not scored.")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            // A pull always reaches the backend: cached copies are kept for offline, never
            // served in place of a fresh read the student asked for.
            await CacheManager.shared.markAllStale()
            await load()
        }
    }

    private func row(_ test: BatchTest) -> some View {
        TestDetailCard(test: test, attempts: attempts) { mode in
            start(test: test, mode: mode)
        }
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
            // Best scores are decoration; the papers must load even when the attempts read fails.
            async let attemptsTask = FirestoreService.shared.fetchUserAttemptsOrEmpty(uid: uid, idToken: token)

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
        appState.startSitting(
            RunnerPayload(
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
