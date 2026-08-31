import SwiftUI

/// The Marrow FMGE test series — 352 keyed papers in three groups, bucketed by the month each one ran
/// with the newest at the top, so scrolling down is scrolling back through seven years of papers.
///
/// The whole catalogue is one Firestore document (`medx_meta/series_fmge`), so this screen costs a
/// single read and then filters and groups in memory. Questions are only fetched when a paper is opened.
///
/// Two things this screen used to get wrong, both of them about where work happens:
///
/// * **The grouping ran inside `body`.** `months` sorted all 352 papers and bucketed them into a
///   dictionary every time the view was evaluated — so on every search keystroke, and again on every
///   unrelated publish from `AuthService`. It is `@State` now, recomputed when the inputs actually
///   change.
/// * **The rows were a `LazyVStack` of `Button`s**, which builds a live subtree per row and never
///   releases one. 119 grand tests is 119 of them. It is a `List` now: reused cells, and the system's
///   own scrolling.
///
/// Tapping a paper still does not start it. A grand paper runs as timed 50-question sections with no
/// way back, which is not something to walk into by mistake, so the mode picker says what is about to
/// happen first.
public struct TestsListView: View {
    @ObservedObject private var authService = AuthService.shared

    @State private var index: MedxSeriesIndex?
    @State private var loadState: MedxLoadState = .loading
    @State private var group: MedxSeriesGroup = .grand
    @State private var searchText = ""
    @State private var picked: MedxSeriesPaper?
    @State private var activeRunnerPayload: RunnerPayload?

    /// The grouped, filtered catalogue. Folded in `regroup()` rather than in `body` — see the note
    /// above. `MedxSeriesRules.byMonth` sorts every paper it is given.
    @State private var months: [MedxSeriesMonth] = []

    /// Best score and sitting count per paper, folded once per load: this walks every response of every
    /// attempt, and the list can be 119 rows.
    @State private var bestByPaper: [String: MedxPaperRecord] = [:]

    public init() {}

    private static let groupKey = "medx.series.group"

    private var uid: String? { authService.currentSession?.uid }

    // MARK: - Body

    public var body: some View {
        Group {
            switch loadState {
            case .loading:
                loadingState
            case .failed(let message):
                failedState(message: message)
            case .loaded:
                content
            }
        }
        .navigationTitle("Tests")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                MedxSettingsMonogram()
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search 352 papers"
        )
        .task {
            guard case .loading = loadState else { return }
            group = MedxSeriesGroup(rawValue: UserDefaults.standard.string(forKey: Self.groupKey) ?? "") ?? .grand
            await load()
        }
        .onChange(of: group) { _, next in
            UserDefaults.standard.set(next.rawValue, forKey: Self.groupKey)
            regroup()
        }
        .onChange(of: searchText) { _, _ in
            regroup()
        }
        .sheet(item: $picked) { paper in
            MedxPaperModeSheet(paper: paper, record: bestByPaper[paper.id]) { mode in
                picked = nil
                start(paper: paper, mode: mode)
            }
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
            batchSection

            if months.isEmpty {
                emptyGroupSection
            } else {
                ForEach(months) { month in
                    Section {
                        ForEach(month.papers) { paper in
                            paperRow(paper)
                        }
                    } header: {
                        MedxHeader(month.label, count: month.papers.count)
                    }
                }
            }
        }
        .medxList()
        .refreshable {
            await load()
        }
    }

    /// The count, then the group picker. `Picker(.segmented)` rather than the hand-built control this
    /// screen used: that one existed to fit a tally beside each label and to tint the selection, and the
    /// tally now lives in each month's header where a tally belongs.
    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                if let index {
                    Text(index.totalPapers.formatted())
                        .font(MedxType.display)
                        .contentTransition(.numericText())
                    Text("keyed papers · \(index.totalQuestions.formatted()) questions")
                        .medxTag()
                }

                Picker("Group", selection: $group) {
                    ForEach(MedxSeriesGroup.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .medxPlainRow()
        }
    }

    /// The batch's own four papers. A row rather than a group in the picker: they are a different
    /// library with a different shape, and folding four undated papers into a month-bucketed list would
    /// put them above seven years of dated ones.
    private var batchSection: some View {
        Section {
            NavigationLink {
                BatchPapersView()
            } label: {
                MedxRow(
                    lead: "4",
                    title: "ARISE batch papers",
                    detail: "The batch's own, keyed and unkeyed"
                ) {
                    EmptyView()
                }
            }
            .medxListRow()
        }
    }

    private func paperRow(_ paper: MedxSeriesPaper) -> some View {
        let record = bestByPaper[paper.id]
        let sections = MedxSeriesRules.sections(for: paper)

        return Button {
            HapticManager.light()
            picked = paper
        } label: {
            MedxRow(
                lead: paper.questions.formatted(),
                title: paper.title,
                tag: shapeTag(sections: sections),
                detail: paper.line
            ) {
                if let record {
                    // The strip, not a bar: eight cells of which your best score fills a proportion.
                    // `MedxPaperRecord` carries a score and a total and no per-question breakdown, and
                    // this says exactly that much without pretending to more.
                    MedxAnswerSheet(
                        fraction: record.fraction,
                        label: "best \(record.bestScore) of \(record.total)"
                    )
                } else {
                    MedxChevron()
                }
            }
        }
        .buttonStyle(.plain)
        .medxListRow()
        .accessibilityValue(accessibilityValue(paper: paper, record: record, sections: sections))
    }

    /// A grand paper's shape is the one thing worth knowing before opening it: three timed blocks is a
    /// very different afternoon from one clock.
    private func shapeTag(sections: [MedxRunnerSection]?) -> String? {
        guard let sections, let first = sections.first else { return nil }
        return "\(sections.count) × \(first.count)"
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

    // MARK: - States

    private var loadingState: some View {
        List {
            ForEach(0..<7, id: \.self) { _ in
                MedxRow(lead: "150", title: "Grand Test 00", tag: "3 × 50", detail: "150 q · 150 min")
                    .medxListRow()
            }
        }
        .medxList()
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityLabel("Loading the test series")
    }

    private func failedState(message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load the series", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            VStack(spacing: 10) {
                Button("Try Again") {
                    HapticManager.light()
                    loadState = .loading
                    Task { await load() }
                }
                .medxFilledButton()
                .buttonBorderShape(.capsule)

                NavigationLink("Open batch papers instead") {
                    BatchPapersView()
                }
                .font(MedxType.title)
            }
        }
        .medxPage()
    }

    private var emptyGroupSection: some View {
        Section {
            ContentUnavailableView {
                Label(
                    searchText.isEmpty ? "Nothing in this group" : "No Matches",
                    systemImage: "magnifyingglass"
                )
            } description: {
                Text(searchText.isEmpty
                     ? "No paper of that kind came through in the export."
                     : "No paper matches “\(searchText)”.")
            }
            .medxPlainRow()
        }
    }

    // MARK: - Data

    private func load() async {
        do {
            let token = try await authService.getValidIdToken()
            // A signed-out state should not fail the catalogue — the papers are readable, only the
            // best-score strips need a uid.
            let loadedIndex = try await FirestoreService.shared.fetchSeriesIndex(idToken: token)
            let loadedAttempts: [SittingAttempt]
            if let uid {
                loadedAttempts = (try? await FirestoreService.shared.fetchUserAttempts(
                    uid: uid,
                    idToken: token
                )) ?? []
            } else {
                loadedAttempts = []
            }

            index = loadedIndex
            bestByPaper = MedxPaperRecord.fold(attempts: loadedAttempts, papers: loadedIndex.papers)
            loadState = .loaded
            regroup()
        } catch {
            loadState = index == nil
                ? .failed("The Marrow series could not be read. Check your connection and try again.")
                : .loaded
        }
    }

    /// Filter, then bucket by month. The one place either happens.
    ///
    /// Called from `load()`, and from `onChange` of the group and the search text — which is every input
    /// that can change the answer, and nothing else. It used to be a computed property read from `body`,
    /// so it ran on every evaluation whether or not anything it depends on had moved.
    private func regroup() {
        let all = (index?.papers ?? []).filter { $0.group == group }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty
            ? all
            : all.filter { $0.title.localizedCaseInsensitiveContains(query) }
        months = MedxSeriesRules.byMonth(filtered)
    }

    private func start(paper: MedxSeriesPaper, mode: SittingMode) {
        HapticManager.medium()
        activeRunnerPayload = RunnerPayload(
            // `series` rather than `test`: the runner's else-branch fetches from `medx_test_questions`
            // either way, and the attempt row then matches what the PWA files so the two clients agree
            // about what a series sitting is.
            kind: "series",
            id: paper.id,
            name: paper.title,
            subject: paper.title,
            mode: mode,
            gradable: true,
            sections: mode == .exam ? MedxSeriesRules.sections(for: paper) : nil,
            examSeconds: paper.durationMin > 0 ? paper.durationMin * 60 : nil
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
    /// catalogue's, because a paper whose export lost a chunk was genuinely shorter when it was sat, and
    /// a best score of 40/40 should not read as 40/150.
    static func fold(
        attempts: [SittingAttempt],
        papers: [MedxSeriesPaper]
    ) -> [String: MedxPaperRecord] {
        let known = Set(papers.map(\.id))
        var out: [String: MedxPaperRecord] = [:]

        for attempt in attempts where known.contains(attempt.sourceId) {
            // A duel dealt from a series paper carries the same `sourceId` but is a different thing —
            // 20 shuffled questions out of 150 is not a score on that paper.
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

// MARK: - Mode picker

/// What is about to happen, before it happens.
///
/// A grand paper runs as three timed 50-question blocks with no way back once a block is submitted.
/// Starting that from a tap on a list row would be the app's most unpleasant surprise, so the sheet
/// spells the shape out and both modes are an explicit choice.
///
/// **This is one of the three places glass survives**, and it is the one the user named. A sheet floats
/// over the screen it was raised from, so the two mode cards have real content behind them to refract —
/// which is the only condition under which glass reads as glass rather than as haze.
struct MedxPaperModeSheet: View {
    let paper: MedxSeriesPaper
    let record: MedxPaperRecord?
    let onPick: (SittingMode) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // The nav bar is already showing `paper.title`; this is only the shape of the paper.
                    MedxCaption(paperShape)

                    modeButton(
                        mode: .exam,
                        icon: "timer",
                        title: "Exam mode",
                        blurb: MedxSeriesRules.examBlurb(for: paper)
                    )

                    modeButton(
                        mode: .revision,
                        icon: "bolt.fill",
                        title: "Revision mode",
                        blurb: "60 seconds each. Answer and explanation the moment you pick."
                    )

                    if let record {
                        priorSittings(record)
                    }
                }
                .padding(.horizontal, MedxDS.gutter)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .medxPage()
            .navigationTitle(paper.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// Year · group · shape, in that order. Built stepwise rather than as one expression because
    /// `paper.year` is the only optional in it, and mixing that into an array literal alongside
    /// non-optionals is how you get an inference error for no gain in clarity.
    private var paperShape: String {
        var parts = [paper.year].compactMap { $0 }
        parts.append("\(paper.group.rawValue) test")
        parts.append(paper.line)
        return parts.joined(separator: " · ")
    }

    private func modeButton(
        mode: SittingMode,
        icon: String,
        title: String,
        blurb: String
    ) -> some View {
        Button {
            HapticManager.medium()
            onPick(mode)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(MedxType.heading)
                        .foregroundStyle(.primary)
                    Text(blurb)
                        .font(MedxType.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .medxSheetCard()
            .contentShape(MedxDS.shape(MedxDS.card))
        }
        .buttonStyle(MedxPressStyle())
        .accessibilityLabel(title)
        .accessibilityHint(blurb)
    }

    private func priorSittings(_ record: MedxPaperRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MedxHeader("Your sittings")
            HStack(spacing: 8) {
                MedxBadge("best \(record.bestScore)/\(record.total)", tint: MedxDS.correct)
                MedxBadge(record.sittings == 1 ? "1 attempt" : "\(record.sittings) attempts")
                MedxAnswerSheet(fraction: record.fraction)
            }
        }
    }
}
