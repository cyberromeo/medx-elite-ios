import SwiftUI

/// The app's shell, and the single place every presentation is hosted from.
///
/// Five tabs on a phone, a sidebar and a detail column on an iPad. Notification taps, Spotlight
/// results, Siri shortcuts, widget links and the search screen's "practise these" all set a flag
/// on `AppState`; the sheets and covers live here so there is exactly one presentation host no
/// matter which screen happens to be on top — Settings, which six toolbars used to present on
/// their own, and the runner, which three screens used to cover themselves with.
public struct MainTabView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var medxTheme = MedxAccentThemeStore.shared

    // `MedxStudyStatsStore` is deliberately not observed here: it is the app's busiest publisher
    // and nothing in this body reads it. Observing it re-evaluated the whole shell on every
    // answered question while the runner was on screen.

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var isBuildingRevision = false

    public init() {}

    private var uid: String? { authService.currentSession?.uid }

    /// `openDuelId` as the item a cover wants: a `String` is not `Identifiable`, a request is.
    private var roomRequest: Binding<MedxRoomRequest?> {
        Binding(
            get: { appState.openDuelId.map { MedxRoomRequest(id: $0) } },
            set: { appState.openDuelId = $0?.id }
        )
    }

    public var body: some View {
        layout
            // Re-identified when the accent changes so every screen inside repaints at once;
            // the sheets below sit outside this id, so changing the accent from Settings does
            // not dismiss Settings.
            .id(medxTheme.accent)
            .tint(MedxTheme.accent)
            .onChange(of: appState.selectedTab) { _, _ in
                HapticManager.selection()
            }
            .sheet(isPresented: $appState.showSettings) {
                SettingsView()
                    .medxFullSheet()
            }
            .sheet(isPresented: $appState.showQuickSitting) {
                MedxCustomModuleSheet()
            }
            // The duel room, from wherever it was asked for: the lobby, a Home invite card, a
            // notification or a link. Hosted here so no lobby has to be on screen first.
            .fullScreenCover(item: roomRequest) { request in
                DuelRoomView(gameId: request.id) {
                    appState.openDuelId = nil
                    NotificationCenter.default.post(name: .medxSittingDidFinish, object: nil)
                }
            }
            .sheet(item: $appState.pendingModulePick) { pick in
                StartSessionSheet(
                    title: pick.name,
                    subtitle: pick.subject,
                    questionCount: pick.questionCount
                ) { mode in
                    appState.startSitting(
                        RunnerPayload(
                            kind: "qbank",
                            id: pick.id,
                            name: pick.name,
                            subject: pick.subject,
                            mode: mode
                        )
                    )
                }
            }
            // The one runner host. Every screen that starts a sitting goes through
            // `AppState.startSitting`, and the screens that paint "practised" badges and best
            // scores refetch when the cover comes down.
            .fullScreenCover(item: $appState.pendingRunnerPayload) { payload in
                QuizRunnerView(payload: payload) {
                    appState.pendingRunnerPayload = nil
                    NotificationCenter.default.post(name: .medxSittingDidFinish, object: nil)
                }
            }
            .task(id: appState.revisionRequestedAt) {
                await startTodaysRevision()
            }
    }

    @ViewBuilder
    private var layout: some View {
        if sizeClass == .regular {
            iPadLayout
        } else {
            tabLayout
        }
    }

    // MARK: - iPhone

    private var tabLayout: some View {
        TabView(selection: $appState.selectedTab) {
            ForEach(TabItem.allCases) { tab in
                Tab(tab.rawValue, systemImage: tab.icon, value: tab) {
                    NavigationStack {
                        destination(for: tab)
                    }
                }
            }
        }
        // The bar shrinks to a pill as you scroll down and comes back the moment you scroll up —
        // the platform's own answer to a five-tab app on a phone.
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    // MARK: - iPad

    /// A collapsible sidebar plus a detail column, the Mail / Notes / Files pattern. The sidebar
    /// lists the five destinations under "Study" and the Library doors under "Library"; picking
    /// any of them shows it in the detail column. There is deliberately no floating tab bar:
    /// `.sidebarAdaptable` kept dragging the sections into the collapsed top bar.
    private var iPadLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: sidebarSelection) {
                Section("Study") {
                    ForEach(TabItem.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(MedxPadSelection.main(tab))
                    }
                }

                Section("Library") {
                    ForEach(MedxPadLibraryTab.allCases) { lib in
                        Label(lib.title, systemImage: lib.icon)
                            .tag(MedxPadSelection.library(lib))
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("MedX Elite")
        } detail: {
            NavigationStack {
                iPadDetail
            }
            .id(padDetailID)
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// The sidebar's selection, bridged to `selectedTab` plus the Library pick. A `nil` from a
    /// deselect is ignored so the detail column never goes blank; a Library pick leaves
    /// `selectedTab` alone so returning to a main tab restores where it was.
    private var sidebarSelection: Binding<MedxPadSelection?> {
        Binding(
            get: { appState.padLibrarySelection.map(MedxPadSelection.library) ?? .main(appState.selectedTab) },
            set: { newValue in
                guard let newValue else { return }
                switch newValue {
                case .main(let tab):
                    appState.padLibrarySelection = nil
                    appState.selectedTab = tab
                case .library(let lib):
                    appState.padLibrarySelection = lib
                }
            }
        )
    }

    @ViewBuilder
    private var iPadDetail: some View {
        if let lib = appState.padLibrarySelection {
            libraryDestination(lib)
        } else {
            destination(for: appState.selectedTab)
        }
    }

    /// Resets the detail's navigation stack when the selection changes, so a new pick starts at
    /// that destination's root.
    private var padDetailID: String {
        appState.padLibrarySelection.map(\.rawValue) ?? appState.selectedTab.rawValue
    }

    @ViewBuilder
    private func libraryDestination(_ tab: MedxPadLibraryTab) -> some View {
        switch tab {
        case .flashcards: FlashcardsSubjectListView()
        case .vodFeed: VodFeedView()
        case .importVod: VodImportView()
        case .faceoff: FaceoffLobbyView()
        case .customModules: CustomModulesView()
        case .search: MedxQuestionSearchView()
        case .bookmarks: BookmarkedQuestionsView(uid: uid)
        case .downloads: DownloadsView()
        case .watchHistory: WatchHistoryView(uid: uid)
        case .activityLog: MedxActivityLogHost(uid: uid)
        }
    }

    @ViewBuilder
    private func destination(for tab: TabItem) -> some View {
        switch tab {
        case .home: HomeView()
        case .qbank: QBankSubjectListView()
        case .tests: TestsListView()
        case .videos: VideosBatchListView()
        case .library: LibraryView()
        }
    }

    // MARK: - Today's revision

    /// Assembles the sitting behind the "Start today's revision" shortcut and the revision
    /// reminder. Ten questions from each of up to five overdue modules, capped at forty.
    ///
    /// Cold-launched from Siri there may be no attempt history in memory yet, so it is fetched
    /// here rather than assuming Home has already run.
    private func startTodaysRevision() async {
        guard appState.revisionRequestedAt != nil, !isBuildingRevision else { return }
        isBuildingRevision = true
        defer {
            isBuildingRevision = false
            appState.revisionRequestedAt = nil
        }

        guard let uid, let token = try? await AuthService.shared.getValidIdToken() else { return }

        let stats = MedxStudyStatsStore.shared
        if !stats.hasIngested {
            let attempts = (try? await FirestoreService.shared.fetchUserAttempts(uid: uid, idToken: token)) ?? []
            stats.ingest(attempts: attempts)
        }

        let due = Array(stats.due.prefix(5))
        guard !due.isEmpty else {
            // Nothing overdue is good news, not an error — offer to build something instead.
            appState.open(route: .quickSitting)
            return
        }

        var questions: [Question] = []
        for item in due {
            if Task.isCancelled { break }
            guard let module = try? await FirestoreService.shared.fetchQBankModule(
                moduleId: item.moduleId,
                idToken: token
            ) else { continue }
            questions.append(contentsOf: (module.questions ?? []).shuffled().prefix(10))
            if questions.count >= 40 { break }
        }

        guard !questions.isEmpty else {
            HapticManager.error()
            return
        }

        appState.startSitting(
            RunnerPayload(
                kind: "qbank",
                // One id per day, so a revision left half-way is offered back the same day
                // instead of a fresh random id orphaning its saved sitting.
                id: "revision-" + Date().formatted(.iso8601.year().month().day()),
                name: "Today's revision",
                subject: due.first?.subject ?? "",
                mode: .revision,
                gradable: true,
                questions: Array(questions.prefix(40))
            )
        )
    }
}

// MARK: - iPad selection

/// One selection type for the iPad sidebar: a primary destination (the "Study" section) or a
/// Library door (the "Library" section). Both drive the same detail column.
enum MedxPadSelection: Hashable {
    case main(TabItem)
    case library(MedxPadLibraryTab)
}

/// The Library doors listed in the iPad sidebar — the same doors, in the same order, as the
/// Library tab's list. Quick sitting is a sheet and Settings is the profile button's, so neither
/// is here; the batch papers live under Tests.
public enum MedxPadLibraryTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case flashcards, customModules, search, vodFeed, importVod, faceoff, bookmarks, downloads, watchHistory, activityLog

    public var id: String { rawValue }

    var feature: MedxFeature {
        switch self {
        case .flashcards: return .flashcards
        case .customModules: return .customModules
        case .search: return .search
        case .vodFeed: return .vod
        case .importVod: return .importClasses
        case .faceoff: return .faceoff
        case .bookmarks: return .bookmarks
        case .downloads: return .downloads
        case .watchHistory: return .watchHistory
        case .activityLog: return .activityLog
        }
    }

    var title: String { feature.title }
    var icon: String { feature.symbol }
}

// MARK: - Profile avatar

/// Circular profile picture with an initial-over-fill fallback when no photo has been chosen.
/// Used where the picture *is* the content: choosing between two people, the Profile page's
/// hero, and knowing whose turn it is in a duel.
public struct ProfileAvatarView: View {
    public let profile: Profile
    public let size: CGFloat
    public let showsRing: Bool

    @ObservedObject private var avatars = AvatarStore.shared

    public init(profile: Profile, size: CGFloat = 44, showsRing: Bool = true) {
        self.profile = profile
        self.size = size
        self.showsRing = showsRing
    }

    public var body: some View {
        ZStack {
            if let image = avatars.images[profile.id] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(uiColor: .tertiarySystemFill)

                Text(profile.initials)
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(MedxTheme.accent)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if showsRing {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: max(1, size * 0.04))
            }
        }
        .accessibilityHidden(true)
    }
}
