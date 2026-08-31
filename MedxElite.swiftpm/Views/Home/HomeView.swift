import SwiftUI

/// Home is a dashboard, not a launcher.
///
/// It used to be both, and that was the app's worst duplication: a "Jump back in" grid whose six
/// tiles opened Question Bank, Test series and Classes — all three of which are *tabs*, one thumb
/// away at the bottom of the same screen — plus Faceoff, Quick sitting and Custom modules, all
/// three of which are also tiles in Library. Every destination in the app had two front doors and
/// three of them had the same heading printed twice.
///
/// So navigation left. The tab bar owns the five browsables and Library owns everything else, and
/// what is here now only answers questions about *today*: is somebody waiting for a game, how long
/// is left, is today being used, what is due, where did I stop, how am I doing.
public struct HomeView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var stats = MedxStudyStatsStore.shared
    @ObservedObject private var medxTheme = MedxAccentThemeStore.shared
    @ObservedObject private var lobbyWatcher = MedxLobbyWatcher.shared

    @State private var attempts: [SittingAttempt] = []
    @State private var summary = HomeSummary.empty
    @State private var trackerDoc: UserTrackerDoc?
    @State private var isLoading = true
    @State private var showTrackerSheet = false
    @State private var resumeVideo: RecordedVideo?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    private var resumeEntry: WatchHistoryEntry? {
        activityStore.watchHistory(for: uid).first { !$0.isCompleted && $0.resumePosition > 0 }
    }

    /// Lobbies the other one has dealt and nobody has joined.
    private var openLobbies: [MedxDuelGame] { lobbyWatcher.theirs }

    public var body: some View {
        ScrollView {
            // A plain `VStack`, not `LazyVStack`: there are nine children, all cheap, and lazy meant
            // each one ran its entrance animation as you scrolled down to it rather than the page
            // arriving as a page.
            VStack(alignment: .leading, spacing: 22) {
                MedxPageCaption(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .medxAppear(index: 0)

                // Above even the countdown: a dealt game is the one thing on this screen with
                // somebody waiting at the other end of it.
                if let invite = openLobbies.first {
                    faceoffInvite(invite)
                        .medxAppear(index: 1)
                }

                CountdownWidgetView()
                    .medxAppear(index: 2)

                goalSection
                    .medxAppear(index: 3)

                if !dueModules.isEmpty {
                    dueSection
                        .medxAppear(index: 4)
                }

                if let resumeEntry {
                    continueSection(entry: resumeEntry)
                        .medxAppear(index: 5)
                }

                thisWeekSection
                    .medxAppear(index: 6)

                progressSection
                    .medxAppear(index: 6)

                syllabusRow
                    .medxAppear(index: 6)
            }
            .padding(.horizontal, MedxSurface.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .medxPage(.home)
        .scrollIndicators(.automatic)
        // The greeting *is* the page title. It used to be a `Text` at the top of the scroll view
        // under a large title reading "Home", which is two headings for one page — and "Home" was
        // the less useful of the two.
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

    // MARK: - Faceoff invite

    /// "Sri wants a game", live.
    ///
    /// Tapping it opens the room straight away rather than the lobby: there is exactly one thing to
    /// do with a dealt game, and a screen in between it and joining is a screen nobody wants.
    private func faceoffInvite(_ game: MedxDuelGame) -> some View {
        let host = Profile.byId(game.hostProfile) ?? Profile.byUid(game.hostUid)
        let hue = host?.duelFill ?? MedxCandy.pink

        return Button {
            HapticManager.medium()
            appState.open(route: .faceoffRoom(game.id))
        } label: {
            HStack(spacing: 14) {
                MedxSticker(host?.sticker ?? "bolt", size: 34, tilt: -8)
                    .frame(width: 46, height: 46)
                    .background(
                        hue.opacity(0.2),
                        in: RoundedRectangle(cornerRadius: MedxRadius.tile, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(host?.displayName ?? "Someone") wants a game")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("\(game.source?.name ?? "a paper") · \(game.total) questions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text("Join")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(MedxCandy.onSolid)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(hue, in: Capsule(style: .continuous))
            }
            .padding(14)
            .medxCard(tint: hue, raised: true)
            .contentShape(RoundedRectangle(cornerRadius: MedxSurface.cardRadius, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
        .accessibilityLabel("\(host?.displayName ?? "Someone") wants a game")
        .accessibilityHint("Opens the faceoff")
    }

    // MARK: - Header

    private var profileGreeting: String {
        guard let name = authService.currentProfile?.displayName else { return greeting }
        return "\(greeting), \(name)"
    }

    // MARK: - Goal & streak

    /// Today's goal, the streak, and the exam distance in one card. Deliberately the second
    /// thing on the page: the countdown says how much time is left, this says whether today
    /// is being used.
    private var goalSection: some View {
        HStack(spacing: 18) {
            goalRing

            VStack(alignment: .leading, spacing: 10) {
                Text(goalHeadline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 14) {
                    Label("\(stats.streakDays)", systemImage: "flame.fill")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(MedxTheme.warningOrange)
                        .contentTransition(.numericText())
                        .symbolEffect(.bounce, value: stats.streakDays)

                    Label("\(summary.weekAnswered)", systemImage: "calendar")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                // There used to be a third line here — "6 days in a row · 340 this week" — which
                // is the two figures above it spelled out in words directly underneath them.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(streakSummary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medxCard()
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's goal")
        .accessibilityValue("\(stats.answeredToday) of \(stats.dailyGoal) questions, \(stats.streakDays) day streak")
    }

    private var goalHeadline: String {
        if stats.isGoalMet {
            return "Today's goal is done — \(stats.answeredToday) answered."
        }
        if stats.answeredToday == 0 {
            return "Nothing answered yet today. \(stats.dailyGoal) is the target."
        }
        return "\(stats.remainingToGoal) more to reach today's \(stats.dailyGoal)."
    }

    /// What the streak and week glyphs say, for VoiceOver — which cannot read a flame.
    private var streakSummary: String {
        let days = stats.streakDays == 1 ? "1 day" : "\(stats.streakDays) days"
        return "\(days) in a row, \(summary.weekAnswered) answered this week"
    }

    private var goalRing: some View {
        ZStack {
            Circle()
                .stroke(MedxTheme.accent.opacity(0.16), lineWidth: 9)

            Circle()
                .trim(from: 0, to: max(stats.goalFraction, 0.004))
                .stroke(
                    stats.isGoalMet ? MedxTheme.successGreen : MedxTheme.accent,
                    style: StrokeStyle(lineWidth: 9, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : MedxMotion.settle, value: stats.goalFraction)

            VStack(spacing: 0) {
                Text("\(stats.answeredToday)")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                // A tick the moment the target is passed, rather than a count that keeps going
                // up against a number it has already beaten.
                if stats.isGoalMet {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(MedxTheme.successGreen)
                        .symbolEffect(.bounce, value: stats.isGoalMet)
                } else {
                    Text("of \(stats.dailyGoal)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(6)
        }
        .frame(width: 82, height: 82)
        .accessibilityHidden(true)
    }

    // MARK: - Due today

    /// What the spaced-revision schedule says is overdue, and one button that sits it.
    ///
    /// This is what replaced the six-tile launcher grid, and it is the trade the whole declutter
    /// turns on: the grid offered six places to go and made no recommendation, while this makes
    /// the one recommendation the app is actually in a position to make. `stats.due` is already
    /// computed — `MainTabView.startTodaysRevision` assembles the sitting from the same list — so
    /// this is a read, not a second schedule.
    private var dueSection: some View {
        Button {
            HapticManager.medium()
            appState.open(route: .todaysRevision)
        } label: {
            HStack(spacing: 14) {
                MedxSymbolMark("arrow.triangle.2.circlepath", hue: MedxCandy.mint, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(dueHeadline)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())

                    Text(dueDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text("Start")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(MedxCandy.onSolid)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(MedxCandy.mint, in: Capsule(style: .continuous))
            }
            .padding(14)
            .medxCard()
            .contentShape(RoundedRectangle(cornerRadius: MedxSurface.cardRadius, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
        .accessibilityLabel(dueHeadline)
        .accessibilityValue(dueDetail)
        .accessibilityHint("Builds a revision sitting from what is overdue")
    }

    /// Capped at five, which is the same cap `startTodaysRevision` applies when it builds the
    /// sitting — so the number on the card is the number that will be sat.
    private var dueModules: [MedxRevisionDue] {
        Array(stats.due.prefix(5))
    }

    private var dueHeadline: String {
        dueModules.count == 1 ? "1 module is due" : "\(dueModules.count) modules are due"
    }

    private var dueDetail: String {
        let subjects = Set(dueModules.map(\.subject)).sorted()
        guard !subjects.isEmpty else { return "Spaced revision" }
        if subjects.count == 1 { return subjects[0] }
        return "\(subjects[0]) and \(subjects.count - 1) more"
    }

    // MARK: - Continue watching

    private func continueSection(entry: WatchHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MedxSectionHeader("Continue") {
                Button("All classes") {
                    HapticManager.light()
                    appState.open(route: .classes)
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(MedxTheme.accent)
            }

            Button {
                HapticManager.medium()
                resumeVideo = entry.video
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(MedxTheme.accent, in: Circle())

                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.video.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text("\(entry.video.subject) · resume at \(entry.formattedResumeTime)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        ProgressView(value: entry.progress)
                            .tint(MedxTheme.accent)
                    }

                    MedxDisclosure()
                }
                .padding(14)
                .medxCard()
                .contentShape(RoundedRectangle(cornerRadius: MedxSurface.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Resume \(entry.video.title)")
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

    // MARK: - This week

    private var thisWeekSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MedxSectionHeader("Last 7 days")

            MedxMetricsRow {
                MedxMetric(
                    icon: "square.stack.3d.up.fill",
                    value: "\(summary.weekSittings)",
                    label: "sittings",
                    color: MedxTheme.primaryBlue
                )
                MedxMetric(
                    icon: "questionmark.circle.fill",
                    value: "\(summary.weekAnswered)",
                    label: "questions",
                    color: MedxTheme.indigoAccent
                )
                MedxMetric(
                    icon: "target",
                    value: summary.weekAnswered > 0 ? "\(summary.weekAccuracy)%" : "—",
                    label: "accuracy",
                    color: MedxTheme.successGreen
                )
            }

            if summary.weekSittings == 0, !isLoading {
                Text("Nothing logged this week yet. One module is enough to start the streak.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MedxSectionHeader("Progress")

            QBankProgressCard(attempts: attempts) {
                appState.open(tab: .qbank)
            }

            AnalyticsCard(attempts: attempts)
        }
    }

    // MARK: - Syllabus

    private var syllabusRow: some View {
        Button {
            HapticManager.light()
            showTrackerSheet = true
        } label: {
            HStack(spacing: 14) {
                MedxSymbolMark("checklist", hue: MedxCandy.blue, size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Syllabus checklist")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(trackerSubtitle)
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
        .buttonStyle(BouncyButtonStyle())
        .accessibilityLabel("Open syllabus checklist")
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
        return "\(done) of \(total) items ticked across \(subjects.count) subjects"
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
            // Feeds the goal ring, the streak, the spaced-revision list, the widgets and
            // the reminders — all from this one fetch.
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
///
/// It used to also carry lifetime totals per kind (`qbankSittings`, `testSittings`,
/// `watchedClasses`). Those existed only to put a subtitle on the launcher tiles that are gone,
/// and a figure nothing reads is a figure that goes quietly wrong.
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
