import SwiftUI

/// The Marrow FMGE test series — 352 keyed papers in three groups, each bucketed by the month
/// it ran with the newest month at the top, so scrolling down is scrolling back through seven
/// years of papers. The batch's own four papers sit in one row above them: a different library
/// with a different shape, and folding them into a month-bucketed list would put four undated
/// rows above seven years of papers.
///
/// The whole catalogue is one Firestore document (`medx_meta/series_fmge`), so this screen costs
/// a single read and can then filter and group in memory. Questions are only fetched when a
/// paper is actually opened — and tapping a paper does not start it. A grand paper runs as
/// timed 50-question sections with no way back, which is not something to walk into by mistake,
/// so the mode picker says what is about to happen first.
public struct TestsListView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var appState = AppState.shared

    @State private var index: MedxSeriesIndex?
    /// Best score and sitting count per paper, folded once per load rather than inside `body`:
    /// this walks every response of every attempt, and the list can be 119 rows.
    @State private var bestByPaper: [String: MedxPaperRecord] = [:]
    @State private var loadState: MedxLoadState = .loading
    @State private var group: MedxSeriesGroup = .grand
    @State private var searchText = ""
    @State private var picked: MedxSeriesPaper?
    /// The pick made inside the mode sheet, started once the sheet has gone — see
    /// `StartSessionSheet` for why not sooner.
    @State private var pendingStart: (paper: MedxSeriesPaper, mode: SittingMode)?

    public init() {}

    private static let groupKey = "medx.series.group"

    private var uid: String? { authService.currentSession?.uid }

    private var isLoading: Bool { loadState == .loading && index == nil }

    private var papers: [MedxSeriesPaper] {
        let all = (index?.papers ?? []).filter { $0.group == group }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    /// Says exactly what the search covers: the papers in the group on screen.
    private var searchPrompt: String {
        guard let count = index?.count(of: group) else { return "Search papers" }
        let noun: String
        switch group {
        case .grand: noun = count == 1 ? "grand test" : "grand tests"
        case .mini: noun = count == 1 ? "mini test" : "mini tests"
        case .subject: noun = count == 1 ? "subject test" : "subject tests"
        }
        return "Search \(MedxFormat.count(count)) \(noun)"
    }

    private var months: [MedxSeriesMonth] {
        MedxSeriesRules.byMonth(papers)
    }

    /// Counted from the papers that can actually be opened, the same set the segments and the
    /// search count, so the numbers on this screen always agree.
    private var subtitle: String {
        guard let index else { return "Marrow FMGE test series" }
        let questions = index.papers.reduce(0) { $0 + $1.questions }
        return "\(MedxFormat.count(index.papers.count)) papers · \(MedxFormat.count(questions)) questions"
    }

    public var body: some View {
        list
            .navigationTitle(MedxFeature.tests.title)
            .navigationSubtitle(subtitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    MedxProfileButton()
                }
            }
            .searchable(text: $searchText, prompt: searchPrompt)
            .searchToolbarBehavior(.minimize)
            .task {
                guard case .loading = loadState else { return }
                group = MedxSeriesGroup(rawValue: UserDefaults.standard.string(forKey: Self.groupKey) ?? "") ?? .grand
                await medxLoadRevalidating { await load() }
            }
            .onChange(of: group) { _, next in
                UserDefaults.standard.set(next.rawValue, forKey: Self.groupKey)
            }
            .onReceive(NotificationCenter.default.publisher(for: .medxContentShouldRefresh)) { _ in
                Task { await load() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .medxSittingDidFinish)) { _ in
                Task { await load() }
            }
            .sheet(item: $picked, onDismiss: startPending) { paper in
                StartSessionSheet(
                    title: paper.title,
                    subtitle: [paper.year, paper.group.label].compactMap { $0 }.joined(separator: " · "),
                    questionCount: paper.questions,
                    examDetail: MedxSeriesRules.examBlurb(for: paper),
                    record: bestByPaper[paper.id]
                ) { mode in
                    pendingStart = (paper: paper, mode: mode)
                }
            }
    }

    private func startPending() {
        guard let pending = pendingStart else { return }
        pendingStart = nil
        start(paper: pending.paper, mode: pending.mode)
    }

    // MARK: - List

    private var list: some View {
        List {
            Section {
                NavigationLink {
                    BatchPapersView()
                } label: {
                    MedxTileLabel(
                        "ARISE batch papers",
                        detail: "The batch's own four papers",
                        symbol: MedxFeature.batchPapers.symbol,
                        hue: MedxFeature.batchPapers.color
                    )
                }
                .accessibilityLabel("ARISE batch papers")
            }

            if case .failed(let message) = loadState, index == nil {
                Section {
                    MedxEmptyState(
                        "Couldn't load the series",
                        symbol: "wifi.exclamationmark",
                        message: message,
                        actionTitle: "Try again"
                    ) {
                        HapticManager.light()
                        loadState = .loading
                        Task { await load() }
                    }
                }
            } else {
                Section {
                    Picker("Group", selection: $group) {
                        ForEach(MedxSeriesGroup.allCases) { item in
                            Text(item.label).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if isLoading {
                    Section {
                        MedxPlaceholderRows(count: 8)
                    }
                } else if months.isEmpty {
                    Section {
                        emptyGroupState
                    }
                } else {
                    ForEach(months) { month in
                        Section {
                            ForEach(month.papers) { paper in
                                paperRow(paper)
                            }
                        } header: {
                            Text(month.label)
                        }
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

    private func paperRow(_ paper: MedxSeriesPaper) -> some View {
        let record = bestByPaper[paper.id]
        let sections = MedxSeriesRules.sections(for: paper)

        return Button {
            HapticManager.light()
            picked = paper
        } label: {
            HStack(spacing: MedxSpace.m) {
                MedxSymbolTile(MedxSeriesRules.symbol(for: paper), hue: MedxFeature.tests.color, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(paper.title)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(paper.line)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let record {
                        ProgressView(value: record.fraction)
                            .tint(MedxOutcome.correct)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: MedxSpace.s)

                if let record {
                    Text("\(record.bestScore)/\(record.total)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(MedxOutcome.correct)
                } else if let sections, let first = sections.first {
                    // A grand paper's shape is the one thing worth knowing before opening it:
                    // three timed blocks is a very different afternoon from one clock.
                    Text("\(sections.count) × \(first.count)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                MedxRowChevron()
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(paper.title)
        .accessibilityValue(accessibilityValue(paper: paper, record: record, sections: sections))
        .accessibilityHint("Opens the mode picker")
    }

    private func accessibilityValue(
        paper: MedxSeriesPaper,
        record: MedxPaperRecord?,
        sections: [MedxRunnerSection]?
    ) -> String {
        var parts = [paper.line]
        if let sections, let first = sections.first {
            parts.append("\(sections.count) sections of \(first.count)")
        }
        if let record {
            parts.append("best \(record.bestScore) of \(record.total)")
        }
        return parts.joined(separator: ", ")
    }

    private var emptyGroupState: some View {
        MedxEmptyState(
            searchText.isEmpty ? "Nothing in this group" : "No matches",
            symbol: "magnifyingglass",
            message: searchText.isEmpty
                ? "No paper of that kind came through in the export."
                : "No paper matches “\(searchText)”."
        )
    }

    // MARK: - Data

    private func load() async {
        do {
            let token = try await authService.getValidIdToken()
            let loadedIndex = try await FirestoreService.shared.fetchSeriesIndex(idToken: token)
            // A signed-out state should not fail the catalogue — the papers are readable, only
            // the best-score badges need a uid.
            let loadedAttempts: [SittingAttempt]
            if let uid {
                loadedAttempts = await FirestoreService.shared.fetchUserAttemptsOrEmpty(uid: uid, idToken: token)
            } else {
                loadedAttempts = []
            }

            index = loadedIndex
            bestByPaper = MedxPaperRecord.fold(attempts: loadedAttempts, papers: loadedIndex.papers)
            loadState = .loaded
        } catch {
            loadState = index == nil
                ? .failed("The Marrow series could not be read. Check your connection and try again.")
                : .loaded
        }
    }

    private func start(paper: MedxSeriesPaper, mode: SittingMode) {
        appState.startSitting(
            RunnerPayload(
                // `series` rather than `test`: the runner's else-branch fetches from
                // `medx_test_questions` either way, and the attempt row then matches what the PWA
                // files so the two clients agree about what a series sitting is.
                kind: "series",
                id: paper.id,
                name: paper.title,
                subject: paper.title,
                mode: mode,
                gradable: true,
                sections: mode == .exam ? MedxSeriesRules.sections(for: paper) : nil,
                examSeconds: paper.durationMin > 0 ? paper.durationMin * 60 : nil
            )
        )
    }
}

// MARK: - Prior sittings

/// What a paper's row and its mode picker say about previous attempts.
public struct MedxPaperRecord: Hashable, Sendable {
    public let bestScore: Int
    public let total: Int
    public let sittings: Int

    public var fraction: Double {
        total > 0 ? min(Double(bestScore) / Double(total), 1) : 0
    }

    /// Folded once per load. `total` prefers the largest count any sitting reported over the
    /// catalogue's, because a paper whose export lost a chunk was genuinely shorter when it
    /// was sat, and a best score of 40/40 should not read as 40/150.
    static func fold(
        attempts: [SittingAttempt],
        papers: [MedxSeriesPaper]
    ) -> [String: MedxPaperRecord] {
        let known = Set(papers.map(\.id))
        var out: [String: MedxPaperRecord] = [:]

        for attempt in attempts where known.contains(attempt.sourceId) {
            // A duel dealt from a series paper carries the same `sourceId` but is a different
            // thing — 20 shuffled questions out of 150 is not a score on that paper.
            guard attempt.kind == "series" || attempt.kind == "test" else { continue }
            let existing = out[attempt.sourceId]
            out[attempt.sourceId] = MedxPaperRecord(
                bestScore: max(existing?.bestScore ?? 0, attempt.score),
                total: max(existing?.total ?? 0, attempt.total),
                sittings: (existing?.sittings ?? 0) + 1
            )
        }
        return out
    }
}
