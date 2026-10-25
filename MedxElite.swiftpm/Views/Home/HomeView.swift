import SwiftUI
import Charts

/// Home is today, and only today: how long is left, whether today is being used, and the one
/// thing worth picking up again. No launcher tiles — the tab bar owns the five destinations and
/// Library owns everything else, so nothing on this screen is a second door to somewhere.
///
/// Every figure here comes from `MedxStudyStatsStore`, which the Profile page, the widgets and
/// Siri also read, so no two screens can disagree about a number.
public struct HomeView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var stats = MedxStudyStatsStore.shared
    @ObservedObject private var medxTheme = MedxAccentThemeStore.shared
    @ObservedObject private var lobbyWatcher = MedxLobbyWatcher.shared

    @State private var trackerDoc: UserTrackerDoc?
    @State private var subjects: [MedxBankSubject] = []
    @State private var loadedAt: Date?
    @State private var isLoading = true
    @State private var showTracker = false
    @State private var showExamEditor = false
    @State private var resumeVideo: RecordedVideo?

    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .largeTitle) private var heroFigureSize: CGFloat = 64

    public init() {}

    private var uid: String? { authService.currentSession?.uid }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: MedxSpace.l) {
                    dateLine

                    // Above even the countdown: a dealt game is the one thing on this screen with
                    // somebody waiting at the other end of it.
                    if let invite = lobbyWatcher.theirs.first {
                        inviteCard(invite)
                    }

                    countdownHero

                    goalCard

                    if let entry = resumeEntry {
                        continueCard(entry)
                    }

                    weekSection
                        .id("home.week")

                    progressSection

                    syllabusRow
                        .id("home.end")
                }
                .padding(.horizontal, MedxSpace.l)
                .padding(.top, MedxSpace.xs)
                .padding(.bottom, MedxSpace.xl)
            }
            #if DEBUG
            .task { await screenshotHooks(proxy) }
            #endif
        }
        .background { MedxTopGlow() }
        // The greeting *is* the title: one heading on a screen that needs one.
        .navigationTitle(greetingTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                MedxProfileButton()
            }
        }
        .refreshable {
            // A pull always reaches the backend: cached copies are kept for offline, never
            // served in place of a fresh read the student asked for.
            await CacheManager.shared.markAllStale()
            await loadHomeData(force: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .medxContentShouldRefresh)) { _ in
            Task { await loadHomeData(force: true) }
        }
        .navigationDestination(isPresented: $showTracker) {
            if let uid {
                SyllabusTrackerSheet(uid: uid, trackerDoc: $trackerDoc)
            }
        }
        .sheet(isPresented: $showExamEditor) {
            MedxExamDateSheet()
        }
        .fullScreenCover(item: $resumeVideo) { video in
            VideoPlayerView(video: video) { resumeVideo = nil }
        }
        .task {
            await loadHomeData(force: false)
            lobbyWatcher.start()
        }
    }

    // MARK: - Header

    private var greetingTitle: String {
        let greeting: String
        switch Calendar.current.component(.hour, from: Date()) {
        case ..<5: greeting = "Still up"
        case ..<12: greeting = "Good morning"
        case ..<17: greeting = "Good afternoon"
        default: greeting = "Good evening"
        }
        guard let name = authService.currentProfile?.displayName else { return greeting }
        return "\(greeting), \(name)"
    }

    /// Today's date, and nothing else.
    private var dateLine: some View {
        Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    // MARK: - Faceoff invite

    /// "Sri wants a game", live. Tapping Join opens the room straight away rather than the
    /// lobby: there is exactly one thing to do with a dealt game.
    private func inviteCard(_ game: MedxDuelGame) -> some View {
        let host = Profile.byId(game.hostProfile) ?? Profile.byUid(game.hostUid)
        return MedxCard {
            HStack(spacing: MedxSpace.m) {
                MedxSymbolTile(MedxFeature.faceoff.symbol, hue: MedxFeature.faceoff.color, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(host?.displayName ?? "Someone") wants a game")
                        .font(.headline)
                    Text("\(game.source?.name ?? "A paper") · \(game.total) questions")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: MedxSpace.s)

                Button("Join") {
                    HapticManager.medium()
                    appState.open(route: .faceoffRoom(game.id))
                }
                .medxPrimary(size: .regular)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(host?.displayName ?? "Someone") wants a game")
        .accessibilityHint("Join opens the faceoff")
    }

    // MARK: - Countdown

    /// The one coloured surface on the screen. Whole calendar days, by the same formula the
    /// Profile page, the widgets and Siri use. Tapping it edits the exam.
    private var countdownHero: some View {
        let days = MedxDates.daysUntil(stats.examDate)
        let weeks = days / 7
        let runUp = 1 - min(Double(days), 365) / 365

        return Button {
            HapticManager.light()
            showExamEditor = true
        } label: {
            MedxCard(tint: MedxTheme.accent) {
                VStack(alignment: .leading, spacing: MedxSpace.m) {
                    HStack {
                        Label(stats.examName, systemImage: "graduationcap.fill")
                            .font(.subheadline.weight(.bold))
                            .textCase(.uppercase)
                            .lineLimit(1)

                        Spacer(minLength: MedxSpace.s)

                        Text(stats.examDate.formatted(.dateTime.day().month(.abbreviated).year()))
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.22), in: Capsule())
                    }

                    HStack(alignment: .lastTextBaseline, spacing: MedxSpace.s) {
                        Text("\(days)")
                            .font(.system(size: heroFigureSize, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(days == 1 ? "day to go" : "days to go")
                            .font(.title3.weight(.semibold))
                    }

                    ProgressView(value: runUp)
                        .tint(.white)

                    HStack {
                        Text(weeks == 1 ? "1 week left" : "\(weeks) weeks left")
                        Spacer(minLength: MedxSpace.s)
                        Text("Change")
                            .opacity(0.8)
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
            .contentShape(MedxCard<EmptyView>.shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stats.examName) countdown")
        .accessibilityValue(MedxFormat.days(days))
        .accessibilityHint("Changes the exam name and date")
    }

    // MARK: - Goal & streak

    private var goalCard: some View {
        MedxCard {
            VStack(alignment: .leading, spacing: MedxSpace.l) {
                HStack(spacing: MedxSpace.l) {
                    MedxRing(
                        fraction: stats.goalFraction,
                        tint: stats.isGoalMet ? MedxOutcome.correct : MedxTheme.accent
                    ) {
                        VStack(spacing: 0) {
                            MedxFigure("\(stats.answeredToday)")
                            Text("of \(stats.dailyGoal)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 88, height: 88)

                    VStack(alignment: .leading, spacing: MedxSpace.xs) {
                        Text(stats.isGoalMet ? "Goal met" : "Today's goal")
                            .font(.caption.weight(.bold))
                            .textCase(.uppercase)
                            .foregroundStyle(stats.isGoalMet ? MedxOutcome.correct : .secondary)
                        Text(goalHeadline)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }

                MedxStatRow {
                    MedxStatTile("\(stats.streakDays)", label: "day streak", symbol: MedxFeature.streak.symbol, hue: MedxFeature.streak.color)
                    MedxStatTile("\(stats.correctToday)", label: "correct today", symbol: "checkmark.circle.fill", hue: MedxOutcome.correct)
                    MedxStatTile(todayAccuracy, label: "accuracy today", symbol: MedxFeature.goal.symbol, hue: MedxTheme.accent)
                }
            }
        }
        .contextMenu {
            Button {
                appState.open(route: .quickSitting)
            } label: {
                Label("Build a quick sitting", systemImage: MedxFeature.quickSitting.symbol)
            }
            Button {
                appState.open(route: .settings)
            } label: {
                Label("Change daily goal", systemImage: MedxFeature.goal.symbol)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's goal")
        .accessibilityValue("\(stats.answeredToday) of \(stats.dailyGoal) questions, \(stats.streakDays) day streak")
    }

    private var goalHeadline: String {
        if stats.isGoalMet {
            return "Done for today, \(stats.answeredToday) answered."
        }
        if stats.answeredToday == 0 {
            return "Nothing answered yet. \(stats.dailyGoal) is today's target."
        }
        return "\(stats.remainingToGoal) more to reach today's \(stats.dailyGoal)."
    }

    private var todayAccuracy: String {
        guard stats.answeredToday > 0 else { return "–" }
        return "\(MedxFormat.percent(stats.correctToday, of: stats.answeredToday))%"
    }

    // MARK: - Continue watching

    private var resumeEntry: WatchHistoryEntry? {
        activityStore.watchHistory(for: uid).first { !$0.isCompleted && $0.resumePosition > 0 }
    }

    private func continueCard(_ entry: WatchHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: MedxSpace.s) {
            MedxHeading("Continue watching") {
                Button("All classes") {
                    HapticManager.light()
                    appState.open(route: .classes)
                }
                .font(.subheadline.weight(.semibold))
            }

            Button {
                HapticManager.medium()
                resumeVideo = entry.video
            } label: {
                MedxCard {
                    HStack(spacing: MedxSpace.m) {
                        MedxSymbolTile("play.fill", hue: MedxFeature.classes.color, size: 40)

                        VStack(alignment: .leading, spacing: MedxSpace.xs) {
                            Text(entry.video.title.medxDisplayTitle)
                                .font(.headline)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Text("\(entry.video.subject) · resume at \(entry.formattedResumeTime)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            ProgressView(value: entry.progress)
                        }

                        MedxRowChevron()
                    }
                }
                .contentShape(MedxCard<EmptyView>.shape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Resume \(entry.video.title.medxDisplayTitle)")
            .accessibilityValue("\(Int(entry.progress * 100)) percent watched")
            .contextMenu {
                Button {
                    resumeVideo = entry.video
                } label: {
                    Label("Resume", systemImage: "play.circle")
                }
                Button(role: .destructive) {
                    activityStore.removeWatchHistory(entry, uid: uid)
                } label: {
                    Label("Remove from history", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Last 7 days

    private var weekSection: some View {
        VStack(alignment: .leading, spacing: MedxSpace.s) {
            MedxHeading("Last 7 days")

            MedxCard {
                VStack(alignment: .leading, spacing: MedxSpace.m) {
                    MedxStatRow {
                        MedxStatTile("\(stats.weekSittings)", label: "sittings", symbol: "square.stack.3d.up.fill", hue: MedxFeature.vod.color)
                        MedxStatTile("\(stats.weekAnswered)", label: "questions", symbol: "questionmark.circle.fill", hue: MedxFeature.customModules.color)
                        MedxStatTile(stats.weekAccuracy.map { "\($0)%" } ?? "–", label: "accuracy", symbol: MedxFeature.goal.symbol, hue: MedxOutcome.correct)
                    }

                    if stats.weekSittings == 0, !isLoading {
                        Text("Nothing logged this week yet. One module is enough to start the streak.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Progress

    private struct Coverage {
        let bank: MedxBank
        let seen: Int
        let total: Int

        var fraction: Double {
            guard total > 0 else { return 0 }
            return min(Double(seen) / Double(total), 1)
        }
    }

    /// Coverage of the bank the QBank tab is showing, against that bank's own catalogue total —
    /// not a hard-coded ARISE figure with Marrow sittings counted on top of it.
    private var coverage: Coverage {
        let bank = MedxBank(rawValue: UserDefaults.standard.string(forKey: "medx.qbank.bank") ?? "") ?? .arise
        var seen = Set<Int>()
        for attempt in stats.attempts
        where attempt.kind == "qbank" && MedxBank.isModuleId(attempt.sourceId) && MedxBank.of(attempt.sourceId) == bank {
            for response in attempt.responses where response.chosenId != nil {
                seen.insert(response.questionId)
            }
        }
        let total = subjects.filter { $0.bank == bank }.reduce(0) { $0 + $1.questionCount }
        return Coverage(bank: bank, seen: seen.count, total: total)
    }

    private struct AccuracyPoint: Identifiable {
        let id: Int
        let accuracy: Double
    }

    /// Accuracy across the last ten sittings that had an answer, oldest first.
    private var accuracyPoints: [AccuracyPoint] {
        let recent = stats.attempts
            .filter { $0.attempted > 0 }
            .sorted { ($0.finishedDate ?? .distantPast) < ($1.finishedDate ?? .distantPast) }
            .suffix(10)
        return recent.enumerated().map { index, attempt in
            AccuracyPoint(id: index, accuracy: Double(attempt.score) / Double(max(attempt.attempted, 1)) * 100)
        }
    }

    private var progressSection: some View {
        let current = coverage
        let points = accuracyPoints

        return VStack(alignment: .leading, spacing: MedxSpace.s) {
            MedxHeading("Progress") {
                Button("Open QBank") {
                    HapticManager.light()
                    appState.open(tab: .qbank)
                }
                .font(.subheadline.weight(.semibold))
            }

            MedxCard {
                VStack(alignment: .leading, spacing: MedxSpace.l) {
                    HStack(spacing: MedxSpace.l) {
                        MedxRing(fraction: current.fraction, tint: MedxTheme.accent) {
                            VStack(spacing: 0) {
                                MedxFigure("\(MedxFormat.percent(current.seen, of: current.total))%", style: .title3)
                                Text("seen")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 76, height: 76)

                        VStack(alignment: .leading, spacing: MedxSpace.xs) {
                            Text("\(MedxFormat.ratio(current.seen, of: current.total)) questions")
                                .font(.headline)
                            Text(progressDetail(current))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }

                    if points.count >= 2 {
                        Divider()
                        accuracyChart(points)
                    }
                }
            }
        }
    }

    private func progressDetail(_ current: Coverage) -> String {
        var parts = ["\(current.bank.label) bank"]
        parts.append(stats.sittings == 1 ? "1 sitting" : "\(MedxFormat.count(stats.sittings)) sittings")
        if let accuracy = stats.overallAccuracy {
            parts.append("\(accuracy)% accuracy")
        }
        return parts.joined(separator: " · ")
    }

    private func accuracyChart(_ points: [AccuracyPoint]) -> some View {
        VStack(alignment: .leading, spacing: MedxSpace.s) {
            Text("Accuracy over the last \(points.count) sittings")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Chart(points) { point in
                AreaMark(x: .value("Sitting", point.id), y: .value("Accuracy", point.accuracy))
                    .foregroundStyle(MedxTheme.accent.opacity(0.14))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Sitting", point.id), y: .value("Accuracy", point.accuracy))
                    .foregroundStyle(MedxTheme.accent)
                    .interpolationMethod(.catmullRom)
                    .symbol(.circle)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Int.self) {
                            Text("\(number)%")
                        }
                    }
                }
            }
            .frame(height: 120)
            .accessibilityLabel("Accuracy over the last \(points.count) sittings")
        }
    }

    // MARK: - Syllabus

    private var syllabusRow: some View {
        Button {
            HapticManager.light()
            showTracker = true
        } label: {
            MedxCard {
                MedxFeatureRow(
                    "Syllabus checklist",
                    detail: trackerSubtitle,
                    symbol: MedxFeature.syllabus.symbol,
                    hue: MedxFeature.syllabus.color
                ) {
                    MedxRowChevron()
                }
            }
            .contentShape(MedxCard<EmptyView>.shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Syllabus checklist")
        .accessibilityValue(trackerSubtitle)
    }

    private var trackerSubtitle: String {
        guard let subjects = trackerDoc?.subjects, !subjects.isEmpty else {
            return "Videos, revision cycles and PYQs"
        }
        var done = 0
        var total = 0
        for fields in subjects.values {
            for field in TrackerField.allCases {
                guard let value = fields.value(for: field) else { continue }
                total += 1
                if value { done += 1 }
            }
        }
        guard total > 0 else { return "Videos, revision cycles and PYQs" }
        return "\(done) of \(total) ticked across \(subjects.count) subjects"
    }

    // MARK: - Data

    /// Fetches attempts, the syllabus document and the bank catalogue, and syncs bookmarks and
    /// history. Not on every appearance: a tab switch within a minute reuses what is here.
    private func loadHomeData(force: Bool) async {
        guard let uid else {
            isLoading = false
            return
        }
        if !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 60 {
            isLoading = false
            return
        }
        do {
            let token = try await authService.getValidIdToken()
            async let attemptsTask = FirestoreService.shared.fetchUserAttempts(uid: uid, idToken: token)
            async let trackerTask = FirestoreService.shared.fetchUserTracker(uid: uid, idToken: token)
            async let syncTask: Void = ActivityStore.shared.syncWithCloud(uid: uid)

            let (loadedAttempts, tracker, _) = try await (attemptsTask, trackerTask, syncTask)
            // Feeds the goal ring, the streak, the spaced-revision list, the widgets and the
            // reminders — all from this one fetch.
            stats.ingest(attempts: loadedAttempts)
            trackerDoc = tracker
            loadedAt = Date()

            // The catalogue is cached for ten minutes, so this is free on all but the first load.
            if let banks = try? await FirestoreService.shared.fetchQBankBanks(idToken: token) {
                subjects = banks
            }
        } catch {
            // Whatever is already on screen stays; the pull-to-refresh control reports the retry.
        }
        isLoading = false
    }

    #if DEBUG
    /// Screenshot runs only: `-medxScreen syllabus` opens the checklist, `-medxScroll 1|2`
    /// scrolls to the middle or the end of the page.
    private func screenshotHooks(_ proxy: ScrollViewProxy) async {
        if UserDefaults.standard.string(forKey: "medxScreen") == "syllabus" {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            showTracker = true
        }
        let target = UserDefaults.standard.integer(forKey: "medxScroll")
        guard target > 0 else { return }
        try? await Task.sleep(nanoseconds: 3_500_000_000)
        proxy.scrollTo(target == 1 ? "home.week" : "home.end", anchor: target == 1 ? .top : .bottom)
    }
    #endif
}
