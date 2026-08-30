import SwiftUI

/// Home is the app's dashboard, laid out the way iOS lays out its own: a large title, a
/// hero widget, then flat grouped cards under plain section headers. It answers three
/// questions in order — how long is left, what should I open now, how am I doing.
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
    @State private var showSettings = false
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
            LazyVStack(alignment: .leading, spacing: 22) {
                greetingLine

                // Above even the countdown: a dealt game is the one thing on this screen with
                // somebody waiting at the other end of it.
                if let invite = openLobbies.first {
                    faceoffInvite(invite)
                }

                CountdownWidgetView()

                goalSection
                    .medxScrollReveal()

                if stats.dueCount > 0 {
                    dueRevisionRow
                        .medxScrollReveal()
                }

                quickActionsSection
                    .medxScrollReveal()

                if let resumeEntry {
                    continueSection(entry: resumeEntry)
                        .medxScrollReveal()
                }

                thisWeekSection
                    .medxScrollReveal()

                progressSection
                    .medxScrollReveal()

                syllabusRow
                    .medxScrollReveal()
            }
            .padding(.horizontal, MedxSurface.gutter)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .background(MedxSurface.groupedBackground.ignoresSafeArea())
        .scrollIndicators(.automatic)
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                profileButton
            }
        }
        .refreshable {
            await loadHomeData()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
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
            summary = HomeSummary(attempts: updated, history: activityStore.watchHistory(for: uid))
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
                    .background(hue.opacity(0.2), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

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
                    .background(hue, in: Capsule())
            }
            .padding(14)
            .medxCard(raised: true)
            .contentShape(RoundedRectangle(cornerRadius: MedxSurface.cardRadius, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
        .accessibilityLabel("\(host?.displayName ?? "Someone") wants a game")
        .accessibilityHint("Opens the faceoff")
    }

    // MARK: - Header

    private var greetingLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(profileGreeting)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var profileGreeting: String {
        guard let name = authService.currentProfile?.displayName else { return greeting }
        return "\(greeting), \(name)"
    }

    private var profileButton: some View {
        Button {
            HapticManager.light()
            showSettings = true
        } label: {
            Group {
                if let profile = authService.currentProfile {
                    ProfileAvatarView(profile: profile, size: 32)
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile and settings")
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

                Text("\(stats.streakDays == 1 ? "1 day" : "\(stats.streakDays) days") in a row · \(summary.weekAnswered) this week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
                .animation(reduceMotion ? nil : .snappy(duration: 0.45), value: stats.goalFraction)

            VStack(spacing: 0) {
                Text("\(stats.answeredToday)")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Text("of \(stats.dailyGoal)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(6)
        }
        .frame(width: 82, height: 82)
        .accessibilityHidden(true)
    }

    // MARK: - Spaced revision

    private var dueRevisionRow: some View {
        Button {
            HapticManager.medium()
            appState.open(route: .todaysRevision)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MedxTheme.tealAccent)
                    .frame(width: 34, height: 34)
                    .background(MedxTheme.tealAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .symbolEffect(.pulse, isActive: true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(stats.dueCount == 1 ? "1 module due for revision" : "\(stats.dueCount) modules due for revision")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                    Text(dueSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                MedxDisclosure()
            }
            .padding(14)
            .medxCard()
            .contentShape(RoundedRectangle(cornerRadius: MedxSurface.cardRadius, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
        .accessibilityLabel("Start today's revision")
        .accessibilityValue(dueSubtitle)
    }

    private var dueSubtitle: String {
        guard let first = stats.due.first else { return "Tap to start a mixed revision sitting" }
        let extra = stats.dueCount - 1
        return extra > 0 ? "\(first.name) and \(extra) more" : first.name
    }

    // MARK: - Quick actions

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MedxSectionHeader("Jump back in")

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(HomeShortcut.allCases) { shortcut in
                    Button {
                        HapticManager.light()
                        appState.open(route: shortcut.route)
                    } label: {
                        shortcutTile(shortcut)
                    }
                    .buttonStyle(BouncyButtonStyle())
                    .accessibilityLabel(shortcut.title)
                    .accessibilityValue(detail(for: shortcut))
                    .accessibilityHint(shortcut.hint)
                }
            }
        }
    }

    private func shortcutTile(_ shortcut: HomeShortcut) -> some View {
        HStack(spacing: 12) {
            Image(systemName: shortcut.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(shortcut.tint)
                .frame(width: 34, height: 34)
                .background(shortcut.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(shortcut.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(detail(for: shortcut))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(minHeight: 62)
        .medxCard(cornerRadius: 14)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func detail(for shortcut: HomeShortcut) -> String {
        switch shortcut {
        case .qbank:
            return summary.qbankSittings == 0 ? "Both banks" : "\(summary.qbankSittings) sittings"
        case .tests:
            return summary.testSittings == 0 ? "352 papers" : "\(summary.testSittings) attempted"
        case .faceoff:
            return openLobbies.isEmpty ? "Head to head" : "\(openLobbies.count) waiting"
        case .quickSitting:
            return "Pick scope & length"
        case .customModules:
            return "Saved by either of you"
        case .classes:
            return summary.watchedClasses == 0 ? "Classroom" : "\(summary.watchedClasses) started"
        }
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
                Image(systemName: "checklist")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(MedxTheme.primaryBlue)
                    .frame(width: 34, height: 34)
                    .background(MedxTheme.primaryBlue.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

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
        .buttonStyle(.plain)
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
            summary = HomeSummary(attempts: loadedAttempts, history: activityStore.watchHistory(for: uid))
            // Feeds the goal ring, the streak, the spaced-revision list, the widgets and
            // the reminders — all from this one fetch.
            stats.ingest(attempts: loadedAttempts)
        } catch {
            // Whatever is already on screen stays; the pull-to-refresh control reports the retry.
        }
        isLoading = false
    }
}

// MARK: - Shortcuts

private enum HomeShortcut: String, CaseIterable, Identifiable {
    case qbank, tests, faceoff, quickSitting, customModules, classes

    var id: String { rawValue }

    var route: MedxRoute {
        switch self {
        case .qbank: return .qbank
        case .tests: return .tests
        case .faceoff: return .faceoff
        case .quickSitting: return .quickSitting
        case .customModules: return .customModules
        case .classes: return .classes
        }
    }

    var title: String {
        switch self {
        case .qbank: return "Question Bank"
        case .tests: return "Test series"
        case .faceoff: return "Faceoff"
        case .quickSitting: return "Quick sitting"
        case .customModules: return "Custom modules"
        case .classes: return "Classes"
        }
    }

    var hint: String {
        switch self {
        case .faceoff: return "Deal a head-to-head paper, or join one"
        case .quickSitting: return "Builds a one-off sitting from your own filters"
        case .customModules: return "Papers either of you has saved"
        default: return "Opens \(title)"
        }
    }

    var icon: String {
        switch self {
        case .qbank: return "books.vertical.fill"
        case .tests: return "trophy.fill"
        case .faceoff: return "bolt.horizontal.fill"
        case .quickSitting: return "dice.fill"
        case .customModules: return "slider.horizontal.3"
        case .classes: return "play.rectangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .qbank: return MedxCandy.lime
        case .tests: return MedxCandy.tangerine
        case .faceoff: return MedxCandy.pink
        case .quickSitting: return MedxCandy.mint
        case .customModules: return MedxCandy.butter
        case .classes: return MedxCandy.violet
        }
    }

    var sticker: String {
        switch self {
        case .qbank: return "brain"
        case .tests: return "trophy"
        case .faceoff: return "bolt"
        case .quickSitting: return "crystal"
        case .customModules: return "memo"
        case .classes: return "clapper"
        }
    }
}

// MARK: - Derived stats

/// Rolled up once when the attempt list changes rather than on every `body` evaluation —
/// these loops walk every response of every sitting.
struct HomeSummary: Equatable {
    var qbankSittings = 0
    var testSittings = 0
    var watchedClasses = 0
    var weekSittings = 0
    var weekAnswered = 0
    var weekCorrect = 0

    /// A paper rather than a module. `series` is here because the Tests tab is the Marrow
    /// catalogue now, and a grand paper filed under QBank would make both figures wrong.
    private static let paperKinds: Set<String> = ["test", "series"]

    var weekAccuracy: Int {
        guard weekAnswered > 0 else { return 0 }
        return Int((Double(weekCorrect) / Double(weekAnswered) * 100).rounded())
    }

    static let empty = HomeSummary()

    init() {}

    init(attempts: [SittingAttempt], history: [WatchHistoryEntry]) {
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)

        for attempt in attempts {
            if Self.paperKinds.contains(attempt.kind) {
                testSittings += 1
            } else {
                qbankSittings += 1
            }

            guard let finished = attempt.finishedDate, finished >= weekAgo else { continue }
            weekSittings += 1
            weekAnswered += attempt.attempted
            weekCorrect += attempt.score
        }

        watchedClasses = history.count
    }
}
