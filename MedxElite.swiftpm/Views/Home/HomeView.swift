import SwiftUI

/// Home is a dashboard, and it answers one question: **what do I do next, and how far am I from the
/// exam.**
///
/// Two things it used to be, and is not:
///
/// * **A launcher.** A "Jump back in" grid whose six tiles opened Question Bank, Test series and
///   Classes — all three of which are *tabs*, one thumb away at the bottom of the same screen — plus
///   Faceoff, Quick sitting and Custom modules, all three of which are Library tiles. Every
///   destination in the app had two front doors. Navigation now lives in exactly one place each.
/// * **A stack of cards.** Nine of them, each with its own heading, each fading and lifting into place
///   on a spring as the page arrived. What is left is a `List`: one hero and five rows.
///
/// The hero is the app's signature — today's answer sheet, one cell per question, green for right and
/// red for wrong, against the day's goal. It replaced a card with a progress ring in it that reported
/// the same number twice: once as an arc and once as a figure inside the arc.
///
/// "3 modules are due" is gone. It counted something the student had no way to check and made a
/// recommendation out of an interval table; the spaced schedule still drives Today's revision from
/// Library and from the Siri shortcut, which is where a suggestion belongs.
public struct HomeView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var stats = MedxStudyStatsStore.shared
    @ObservedObject private var lobbyWatcher = MedxLobbyWatcher.shared

    @State private var attempts: [SittingAttempt] = []
    @State private var summary = HomeSummary.empty
    @State private var trackerDoc: UserTrackerDoc?
    @State private var isLoading = true
    @State private var showTrackerSheet = false
    @State private var resumeVideo: RecordedVideo?

    public init() {}

    private var uid: String? { authService.currentSession?.uid }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case ..<5: return "Still up"
        case ..<12: return "Good morning"
        case ..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    /// The greeting *is* the page title. It used to be a `Text` at the top of the scroll view under a
    /// large title reading "Home", which is two headings for one page — and "Home" was the less useful.
    private var profileGreeting: String {
        guard let name = authService.currentProfile?.displayName else { return greeting }
        return "\(greeting), \(name)"
    }

    private var resumeEntry: WatchHistoryEntry? {
        activityStore.watchHistory(for: uid).first { !$0.isCompleted && $0.resumePosition > 0 }
    }

    /// Lobbies the other one has dealt and nobody has joined.
    private var openLobby: MedxDuelGame? { lobbyWatcher.theirs.first }

    // MARK: - Body

    public var body: some View {
        List {
            todaySection
            nextSection
            weekSection
            progressSection
            syllabusSection
        }
        .medxList()
        .navigationTitle(profileGreeting)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                MedxSettingsMonogram()
            }
        }
        .refreshable {
            await loadHomeData()
        }
        .sheet(isPresented: $showTrackerSheet) {
            if let uid {
                SyllabusTrackerSheet(uid: uid, trackerDoc: $trackerDoc)
            }
        }
        .fullScreenCover(item: $resumeVideo) { video in
            VideoPlayerView(video: video) { resumeVideo = nil }
        }
        .task {
            await loadHomeData()
            lobbyWatcher.start()
        }
        .onChange(of: attempts) { _, updated in
            summary = HomeSummary(attempts: updated)
        }
    }

    // MARK: - Today

    /// The hero. One figure, one sheet, one streak.
    ///
    /// The cells are built from what the store actually knows — `correctToday` and `answeredToday` —
    /// padded out to the day's goal. So the sheet is literally "how today went, against the target",
    /// which is the one thing a dashboard on this app has to say. No ring, because an arc and a figure
    /// inside the arc are the same number drawn twice.
    private var todaySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(stats.answeredToday)")
                        .font(MedxType.hero)
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Spacer(minLength: 8)

                    if stats.streakDays > 0 {
                        Label("\(stats.streakDays)", systemImage: "flame.fill")
                            .font(MedxType.value)
                            .foregroundStyle(MedxDS.warn)
                            .contentTransition(.numericText())
                            .symbolEffect(.bounce, value: stats.streakDays)
                            .accessibilityLabel(streakSummary)
                    }
                }

                Text(goalCaption)
                    .medxTag()

                MedxAnswerSheet(cells: todayCells, scale: .sheet, label: sheetSummary)
            }
            .padding(.vertical, 2)
            .medxPlainRow()
            .contextMenu {
                Button {
                    appState.open(route: .quickSitting)
                } label: {
                    Label("Build a quick sitting", systemImage: "dice")
                }
                Button {
                    appState.open(route: .settings)
                } label: {
                    Label("Change daily goal", systemImage: "target")
                }
            }
        }
    }

    /// Right, then wrong, then the rest of the goal unfilled. Capped at 240 cells: past that the grid
    /// stops being readable and starts being a texture, and a day over 240 questions is a day the
    /// figure above already tells you about.
    private var todayCells: [MedxSheetCell] {
        let answered = min(stats.answeredToday, 240)
        let correct = min(stats.correctToday, answered)
        let target = min(max(stats.dailyGoal, answered), 240)

        var cells = [MedxSheetCell](repeating: .correct, count: correct)
        cells.append(contentsOf: [MedxSheetCell](repeating: .wrong, count: answered - correct))
        cells.append(contentsOf: [MedxSheetCell](repeating: .pending, count: max(target - answered, 0)))
        // A day with no goal set and nothing answered would draw nothing at all, which reads as a
        // broken view rather than as an empty one.
        return cells.isEmpty ? [MedxSheetCell](repeating: .pending, count: 24) : cells
    }

    private var goalCaption: String {
        if stats.isGoalMet {
            return "answered today · goal of \(stats.dailyGoal) met"
        }
        if stats.answeredToday == 0 {
            return "answered today · \(stats.dailyGoal) is the target"
        }
        return "answered today · \(stats.remainingToGoal) to go"
    }

    /// What the grid says, in one sentence, because VoiceOver cannot read a grid of cells.
    private var sheetSummary: String {
        let wrong = max(stats.answeredToday - stats.correctToday, 0)
        return "\(stats.correctToday) correct, \(wrong) wrong, out of a goal of \(stats.dailyGoal)"
    }

    private var streakSummary: String {
        stats.streakDays == 1 ? "1 day in a row" : "\(stats.streakDays) days in a row"
    }

    // MARK: - Next

    /// The three things with somebody or something waiting: a dealt game, the exam, the class you
    /// stopped halfway through. All rows, in that order — a dealt game has a person at the other end of
    /// it, which outranks a date.
    @ViewBuilder
    private var nextSection: some View {
        Section {
            if let openLobby {
                inviteRow(openLobby)
            }

            examRow

            if let resumeEntry {
                resumeRow(resumeEntry)
            }
        }
    }

    /// "Sri wants a game", live. Tapping it opens the room rather than the lobby: there is exactly one
    /// thing to do with a dealt game, and a screen in between is a screen nobody wants.
    private func inviteRow(_ game: MedxDuelGame) -> some View {
        let host = Profile.byId(game.hostProfile) ?? Profile.byUid(game.hostUid)

        return Button {
            HapticManager.medium()
            appState.open(route: .faceoffRoom(game.id))
        } label: {
            MedxRow(
                lead: "VS",
                title: "\(host?.displayName ?? "Someone") wants a game",
                tag: game.source?.name ?? "a paper",
                detail: "\(game.total) questions"
            ) {
                MedxBadge("Join", tint: MedxDS.correct)
            }
        }
        .buttonStyle(.plain)
        .medxListRow()
        .accessibilityHint("Opens the faceoff")
    }

    private var examRow: some View {
        MedxRow(
            lead: "\(stats.daysToExam)",
            title: stats.examName,
            tag: stats.daysToExam == 1 ? "1 day away" : "\(stats.daysToExam) days away",
            detail: stats.examDate.formatted(.dateTime.day().month(.abbreviated).year())
        ) {
            MedxChevron()
        }
        .medxListRow()
        .onTapGesture {
            HapticManager.light()
            appState.open(route: .settings)
        }
        .accessibilityHint("Change the exam date in Settings")
    }

    private func resumeRow(_ entry: WatchHistoryEntry) -> some View {
        Button {
            HapticManager.medium()
            resumeVideo = entry.video
        } label: {
            MedxRow(
                lead: "▶",
                title: entry.video.title,
                tag: entry.video.subject,
                detail: "from \(entry.formattedResumeTime)"
            ) {
                MedxAnswerSheet(
                    fraction: entry.progress,
                    label: "\(Int(entry.progress * 100)) percent watched"
                )
            }
        }
        .buttonStyle(.plain)
        .medxListRow()
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

    // MARK: - Last 7 days

    private var weekSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                weekBars

                HStack(alignment: .top, spacing: 10) {
                    MedxStat("\(summary.weekSittings)", label: "sittings")
                    MedxStat("\(summary.weekAnswered)", label: "questions")
                    MedxStat(
                        summary.weekAnswered > 0 ? "\(summary.weekAccuracy)%" : "—",
                        label: "accuracy",
                        tint: summary.weekAnswered > 0 ? MedxDS.correct : nil
                    )
                }

                if summary.weekSittings == 0, !isLoading {
                    Text("Nothing logged this week yet. One module is enough to start the streak.")
                        .font(MedxType.body)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .medxListRow()
        } header: {
            MedxHeader("Last 7 days", count: summary.weekAnswered > 0 ? summary.weekAnswered : nil)
        }
    }

    /// Seven capsules, oldest on the left. Seven views is not worth a `Canvas`; the answer sheet is
    /// because it draws two hundred.
    private var weekBars: some View {
        let week = stats.weeklyAnswered
        let peak = max(week.max() ?? 0, stats.dailyGoal, 1)

        return HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(week.enumerated()), id: \.offset) { index, count in
                Capsule(style: .continuous)
                    .fill(count >= stats.dailyGoal ? MedxDS.correct : MedxDS.pending)
                    .frame(height: max(CGFloat(count) / CGFloat(peak) * 40, 3))
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(index >= 0)
            }
        }
        .frame(height: 40)
        .accessibilityElement()
        .accessibilityLabel("Questions answered each of the last seven days")
        .accessibilityValue(week.map(String.init).joined(separator: ", "))
    }

    // MARK: - Progress

    private var progressSection: some View {
        Section {
            QBankProgressCard(attempts: attempts) {
                appState.open(tab: .qbank)
            }
            .medxPlainRow()

            AnalyticsCard(attempts: attempts)
                .medxPlainRow()
        } header: {
            MedxHeader("Progress")
        }
    }

    // MARK: - Syllabus

    private var syllabusSection: some View {
        Section {
            Button {
                HapticManager.light()
                showTrackerSheet = true
            } label: {
                MedxRow(
                    lead: "☑",
                    title: "Syllabus checklist",
                    detail: trackerSubtitle
                )
            }
            .buttonStyle(.plain)
            .medxListRow()
        }
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

    private func loadHomeData() async {
        guard let uid else {
            isLoading = false
            return
        }
        do {
            let token = try await authService.getValidIdToken()
            async let attemptsTask = FirestoreService.shared.fetchUserAttempts(uid: uid, idToken: token)
            async let trackerTask = FirestoreService.shared.fetchUserTracker(uid: uid, idToken: token)
            async let syncTask: Void = ActivityStore.shared.syncWithCloud(uid: uid)

            let (loadedAttempts, tracker, _) = try await (attemptsTask, trackerTask, syncTask)
            attempts = loadedAttempts
            trackerDoc = tracker
            summary = HomeSummary(attempts: loadedAttempts)
            // Feeds the answer sheet, the streak, the spaced-revision list, the widgets and the
            // reminders — all from this one fetch.
            stats.ingest(attempts: loadedAttempts)
        } catch {
            // Whatever is already on screen stays; the pull-to-refresh control reports the retry.
        }
        isLoading = false
    }
}

// MARK: - Derived stats

/// The last seven days, rolled up once when the attempt list changes rather than on every `body`
/// evaluation — this loop walks every response of every sitting.
struct HomeSummary: Equatable {
    var weekSittings = 0
    var weekAnswered = 0
    var weekCorrect = 0

    var weekAccuracy: Int {
        guard weekAnswered > 0 else { return 0 }
        return Int((Double(weekCorrect) / Double(weekAnswered) * 100).rounded())
    }

    static let empty = HomeSummary()

    init() {}

    init(attempts: [SittingAttempt]) {
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)

        for attempt in attempts {
            guard let finished = attempt.finishedDate, finished >= weekAgo else { continue }
            weekSittings += 1
            weekAnswered += attempt.attempted
            weekCorrect += attempt.score
        }
    }
}
