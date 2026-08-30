import SwiftUI

/// The Marrow FMGE test series — 352 keyed papers in three groups, each bucketed by the month
/// it ran with the newest month at the top, so scrolling down is scrolling back through seven
/// years of papers.
///
/// The whole catalogue is one Firestore document (`medx_meta/series_fmge`), so this screen costs
/// a single read and can then filter and group in memory. Questions are only fetched when a
/// paper is actually opened.
///
/// Tapping a paper does not start it. A grand paper runs as timed 50-question sections with no
/// way back, which is not something to walk into by mistake, so the mode picker says what is
/// about to happen first.
public struct TestsListView: View {
    @ObservedObject private var authService = AuthService.shared

    @State private var index: MedxSeriesIndex?
    @State private var attempts: [SittingAttempt] = []
    @State private var loadState: MedxLoadState = .loading
    @State private var group: MedxSeriesGroup = .grand
    @State private var searchText = ""
    @State private var picked: MedxSeriesPaper?
    @State private var activeRunnerPayload: RunnerPayload?

    public init() {}

    private static let groupKey = "medx.series.group"

    private var uid: String? { authService.currentSession?.uid }

    /// Best score and sitting count per paper, folded once per load rather than inside `body`:
    /// this walks every response of every attempt, and the list can be 119 rows.
    @State private var bestByPaper: [String: MedxPaperRecord] = [:]

    private var papers: [MedxSeriesPaper] {
        let all = (index?.papers ?? []).filter { $0.group == group }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var months: [MedxSeriesMonth] {
        MedxSeriesRules.byMonth(papers)
    }

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
        .background(MedxSurface.groupedBackground.ignoresSafeArea())
        .navigationTitle("Tests")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ProfileSettingsButton()
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                header

                batchRow

                MedxSegmented(
                    section: .tests,
                    segments: MedxSeriesGroup.allCases.map {
                        MedxSegment(value: $0, label: $0.label, count: index?.count(of: $0))
                    },
                    selection: $group
                )
                .onChange(of: group) { _, next in
                    UserDefaults.standard.set(next.rawValue, forKey: Self.groupKey)
                }

                if months.isEmpty {
                    emptyGroupState
                } else {
                    ForEach(months) { month in
                        monthSection(month)
                    }
                }
            }
            .padding(.horizontal, MedxSurface.gutter)
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
        .refreshable {
            await load()
        }
    }

    private var header: some View {
        MedxPageHeader(
            section: .tests,
            title: "Tests",
            lead: index.map {
                "\($0.totalPapers.formatted()) papers, \($0.totalQuestions.formatted()) questions. "
                    + "Every one of them is keyed, so every one can be scored."
            } ?? "The Marrow FMGE test series — grand, mini and subject papers.",
            sticker: "trophy"
        )
    }

    /// The batch's own four papers. One row rather than a segment: they are a different library
    /// with a different shape, and folding them into a month-bucketed series list would put four
    /// undated rows above seven years of papers.
    private var batchRow: some View {
        NavigationLink {
            BatchPapersView()
        } label: {
            HStack(spacing: 14) {
                MedxSticker("flag", size: 30, tilt: -7)
                    .frame(width: 38, height: 38)
                    .background(MedxCandy.tangerineSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("ARISE batch papers")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("The batch's own four, keyed and unkeyed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                MedxDisclosure()
            }
            .padding(14)
            .medxCard()
            .contentShape(RoundedRectangle(cornerRadius: MedxSurface.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("ARISE batch papers")
    }

    private func monthSection(_ month: MedxSeriesMonth) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MedxRuleHeader(month.label, count: month.papers.count)

            ForEach(Array(month.papers.enumerated()), id: \.element.id) { offset, paper in
                paperRow(paper, tilt: offset.isMultiple(of: 2) ? -6 : 6)
            }
        }
        .medxScrollReveal()
    }

    private func paperRow(_ paper: MedxSeriesPaper, tilt: Double) -> some View {
        let record = bestByPaper[paper.id]
        let sections = MedxSeriesRules.sections(for: paper)

        return Button {
            HapticManager.light()
            picked = paper
        } label: {
            HStack(spacing: 12) {
                MedxSticker(MedxSeriesRules.sticker(for: paper), size: 28, tilt: tilt)
                    .frame(width: 38, height: 38)
                    .background(MedxCandy.tangerineSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(paper.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(paper.line)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if let record {
                        ProgressView(value: record.fraction)
                            .tint(MedxCandy.tangerine)
                            .frame(maxWidth: 120)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    if let record {
                        MedxPill(
                            "\(record.bestScore)/\(record.total)",
                            hue: MedxCandy.tangerine,
                            weight: .solid
                        )
                    } else if let sections, let first = sections.first {
                        // A grand paper's shape is the one thing worth knowing before opening
                        // it: three timed blocks is a very different afternoon from one clock.
                        MedxPill("\(sections.count) × \(first.count)", hue: MedxCandy.tangerine)
                    }

                    MedxDisclosure()
                }
            }
            .padding(14)
            .frame(minHeight: 64)
            .medxCard()
            .contentShape(RoundedRectangle(cornerRadius: MedxSurface.cardRadius, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
        .accessibilityLabel(paper.title)
        .accessibilityValue(accessibilityValue(paper: paper, record: record, sections: sections))
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
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 15)
                            .frame(maxWidth: 240)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                            .frame(height: 11)
                            .frame(maxWidth: 120)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .medxCard()
                }
            }
            .padding(.horizontal, MedxSurface.gutter)
            .padding(.top, 8)
            .redacted(reason: .placeholder)
        }
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
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)

                NavigationLink("Open batch papers instead") {
                    BatchPapersView()
                }
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var emptyGroupState: some View {
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
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }

    // MARK: - Data

    private func load() async {
        do {
            let token = try await authService.getValidIdToken()
            async let indexTask = FirestoreService.shared.fetchSeriesIndex(idToken: token)
            // A signed-out state should not fail the catalogue — the papers are readable, only
            // the best-score badges need a uid.
            let loadedIndex = try await indexTask
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
            attempts = loadedAttempts
            bestByPaper = MedxPaperRecord.fold(attempts: loadedAttempts, papers: loadedIndex.papers)
            loadState = .loaded
        } catch {
            loadState = index == nil
                ? .failed("The Marrow series could not be read. Check your connection and try again.")
                : .loaded
        }
    }

    private func start(paper: MedxSeriesPaper, mode: SittingMode) {
        HapticManager.medium()
        activeRunnerPayload = RunnerPayload(
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

// MARK: - Mode picker

/// What is about to happen, before it happens.
///
/// A grand paper runs as three timed 50-question blocks with no way back once a block is
/// submitted. Starting that from a tap on a list row would be the app's most unpleasant
/// surprise, so the sheet spells the shape out and both modes are an explicit choice.
struct MedxPaperModeSheet: View {
    let paper: MedxSeriesPaper
    let record: MedxPaperRecord?
    let onPick: (SittingMode) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    MedxPageHeader(
                        section: .tests,
                        eyebrow: [paper.year, "\(paper.group.rawValue) test"]
                            .compactMap { $0 }
                            .joined(separator: " · "),
                        title: paper.title,
                        lead: paper.line,
                        sticker: MedxSeriesRules.sticker(for: paper)
                    )

                    modeButton(
                        mode: .exam,
                        icon: "timer",
                        title: "Exam mode",
                        blurb: MedxSeriesRules.examBlurb(for: paper),
                        hue: MedxCandy.tangerine
                    )

                    modeButton(
                        mode: .revision,
                        icon: "bolt.fill",
                        title: "Revision mode",
                        blurb: "60 seconds each. Answer and explanation the moment you pick.",
                        hue: MedxCandy.lime
                    )

                    if let record {
                        priorSittings(record)
                    }
                }
                .padding(.horizontal, MedxSurface.gutter)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(MedxSurface.groupedBackground.ignoresSafeArea())
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

    private func modeButton(
        mode: SittingMode,
        icon: String,
        title: String,
        blurb: String,
        hue: Color
    ) -> some View {
        Button {
            HapticManager.medium()
            onPick(mode)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MedxCandy.onSoft(hue))
                    .frame(width: 42, height: 42)
                    .background(hue.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(blurb)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .medxCard()
            .contentShape(RoundedRectangle(cornerRadius: MedxSurface.cardRadius, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
        .accessibilityLabel(title)
        .accessibilityHint(blurb)
    }

    private func priorSittings(_ record: MedxPaperRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MedxSectionHeader("Your sittings")
            HStack(spacing: 8) {
                MedxPill(
                    "best \(record.bestScore)/\(record.total)",
                    hue: MedxCandy.tangerine,
                    weight: .solid
                )
                MedxPill(
                    record.sittings == 1 ? "1 attempt" : "\(record.sittings) attempts",
                    weight: .outline
                )
            }
        }
    }
}
