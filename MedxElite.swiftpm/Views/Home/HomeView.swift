import SwiftUI

/// Home is the app's dashboard, laid out the way iOS lays out its own: a large title, a
/// hero widget, then flat grouped cards under plain section headers. It answers three
/// questions in order — how long is left, what should I open now, how am I doing.
public struct HomeView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var appState = AppState.shared

    @State private var attempts: [SittingAttempt] = []
    @State private var summary = HomeSummary.empty
    @State private var trackerDoc: UserTrackerDoc?
    @State private var isLoading = true
    @State private var showSettings = false
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

    private var resumeEntry: WatchHistoryEntry? {
        activityStore.watchHistory(for: uid).first { !$0.isCompleted && $0.resumePosition > 0 }
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                greetingLine

                CountdownWidgetView()

                quickActionsSection

                if let resumeEntry {
                    continueSection(entry: resumeEntry)
                }

                thisWeekSection

                progressSection

                syllabusRow
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
        }
        .onChange(of: attempts) { _, updated in
            summary = HomeSummary(attempts: updated, history: activityStore.watchHistory(for: uid))
        }
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
                        appState.open(tab: shortcut.tab)
                    } label: {
                        shortcutTile(shortcut)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(shortcut.title)
                    .accessibilityValue(detail(for: shortcut))
                    .accessibilityHint("Opens the \(shortcut.title) tab")
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
            return summary.qbankSittings == 0 ? "Start a module" : "\(summary.qbankSittings) sittings"
        case .tests:
            return summary.testSittings == 0 ? "Take a paper" : "\(summary.testSittings) attempted"
        case .flashcards:
            return "High-yield visuals"
        case .videos:
            return summary.watchedClasses == 0 ? "Classroom" : "\(summary.watchedClasses) started"
        }
    }

    // MARK: - Continue watching

    private func continueSection(entry: WatchHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MedxSectionHeader("Continue") {
                Button("All videos") {
                    HapticManager.light()
                    appState.open(tab: .videos)
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
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
                        .background(Color.accentColor, in: Circle())

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
                            .tint(Color.accentColor)
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
        } catch {
            // Whatever is already on screen stays; the pull-to-refresh control reports the retry.
        }
        isLoading = false
    }
}

// MARK: - Shortcuts

private enum HomeShortcut: String, CaseIterable, Identifiable {
    case qbank, tests, flashcards, videos

    var id: String { rawValue }

    var tab: TabItem {
        switch self {
        case .qbank: return .qbank
        case .tests: return .tests
        case .flashcards: return .flashcards
        case .videos: return .videos
        }
    }

    var title: String {
        switch self {
        case .qbank: return "Question Bank"
        case .tests: return "Batch Tests"
        case .flashcards: return "Flashcards"
        case .videos: return "Classes"
        }
    }

    var icon: String {
        switch self {
        case .qbank: return "books.vertical.fill"
        case .tests: return "checkmark.seal.fill"
        case .flashcards: return "rectangle.stack.fill"
        case .videos: return "play.rectangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .qbank: return MedxTheme.primaryBlue
        case .tests: return MedxTheme.successGreen
        case .flashcards: return MedxTheme.indigoAccent
        case .videos: return MedxTheme.primaryPurple
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

    var weekAccuracy: Int {
        guard weekAnswered > 0 else { return 0 }
        return Int((Double(weekCorrect) / Double(weekAnswered) * 100).rounded())
    }

    static let empty = HomeSummary()

    init() {}

    init(attempts: [SittingAttempt], history: [WatchHistoryEntry]) {
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)

        for attempt in attempts {
            if attempt.kind == "test" { testSittings += 1 } else { qbankSittings += 1 }

            guard let finished = attempt.finishedDate, finished >= weekAgo else { continue }
            weekSittings += 1
            weekAnswered += attempt.attempted
            weekCorrect += attempt.score
        }

        watchedClasses = history.count
    }
}
