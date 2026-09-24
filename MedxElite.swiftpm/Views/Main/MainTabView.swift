import SwiftUI

/// The app's shell, and the single place every *external* entry point is presented from.
///
/// Notification taps, Spotlight results, Siri shortcuts, widget deep links and the search
/// screen's "practise these" all set a flag on `AppState`; the sheets and covers live here so
/// there is exactly one presentation host no matter which tab happens to be on screen.
public struct MainTabView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var medxTheme = MedxAccentThemeStore.shared

    // `MedxStudyStatsStore` is deliberately **not** observed here.
    //
    // It was, and it is the app's busiest publisher — `answeredToday`, `correctToday`, `streakDays`,
    // `due`, `weeklyAnswered` all change as a sitting is answered. Observing it from the shell meant
    // every answered question re-evaluated this `body`: the `TabView`, all five destinations and nine
    // `.sheet` modifiers, while the runner was on screen. Nothing in `body` reads it — only
    // `startTodaysRevision()` does, and that reaches `.shared` directly, which needs no observation.

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var columnVisibility: NavigationSplitViewVisibility = .doubleColumn
    @State private var isBuildingRevision = false
    /// Which library destination the iPad sidebar has open, if any. `nil` means a main tab is
    /// showing. Unused on iPhone and on the iOS 17 iPad fallback.
    @State private var padLibrarySelection: MedxPadLibraryTab?

    public init() {}

    private var uid: String? { authService.currentSession?.uid }

    public var body: some View {
        layout
            // Re-identified when the accent changes so every screen inside repaints at once.
            // `MedxTheme.accent` is a static read — SwiftUI cannot track it as a dependency,
            // and hand-adding an observer to all thirty views that draw an accent would be
            // both noisier and easier to forget. The `.sheet`s below sit *outside* this id,
            // so changing the accent from Settings does not dismiss Settings.
            .id(medxTheme.accent)
            .tint(MedxTheme.accent)
            .onChange(of: appState.selectedTab) { _, _ in
                HapticManager.selection()
            }
            .sheet(isPresented: $appState.showSearch) {
                MedxQuestionSearchView(seed: appState.searchSeed)
            }
            .sheet(isPresented: $appState.showQuickSitting) {
                MedxCustomModuleSheet()
            }
            .sheet(isPresented: $appState.showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $appState.showCustomModules) {
                NavigationStack {
                    CustomModulesView()
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Done") { appState.showCustomModules = false }
                            }
                        }
                }
            }
            .fullScreenCover(isPresented: $appState.showFaceoff) {
                FaceoffLobbyView()
            }
            .sheet(isPresented: $appState.showBookmarks) {
                NavigationStack {
                    BookmarkedQuestionsView(uid: uid)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Done") { appState.showBookmarks = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $appState.showDownloads) {
                NavigationStack {
                    DownloadsView()
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Done") { appState.showDownloads = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $appState.showActivityLog) {
                NavigationStack {
                    MedxActivityLogHost(uid: uid)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Done") { appState.showActivityLog = false }
                            }
                        }
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
            .fullScreenCover(item: $appState.pendingRunnerPayload) { payload in
                QuizRunnerView(payload: payload) {
                    appState.pendingRunnerPayload = nil
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
                NavigationStack {
                    destination(for: tab)
                }
                .tabItem {
                    Label(tab.rawValue, systemImage: appState.selectedTab == tab ? tab.selectedIcon : tab.icon)
                }
                .tag(tab)
            }
        }
        // On iOS 26 the bar shrinks to a pill as you scroll down and comes back the moment you
        // scroll up, which is the platform's own answer to a five-tab app on a phone.
        .medxTabBarMinimize()
        // The tab bar's background is deliberately *not* specified. Forcing
        // `.toolbarBackground(.bar, for: .tabBar)` overrode whatever the running OS wanted to
        // do with it, which on iOS 26+ meant opting out of the system's own treatment — the app
        // should not be hand-picking chrome the platform owns.
    }

    // MARK: - iPad

    /// iPad follows Apple's own adaptive layout on iOS 18+: a floating Liquid Glass tab bar
    /// across the top that toggles into a sidebar — the Files / Photos arrangement — and falls
    /// back to the older two-column split on iOS 17.
    ///
    /// The five destinations are the primary tabs (the floating top bar); every library action
    /// rides a `TabSection`, so expanding the sidebar lists the whole library the way iPadOS
    /// lists a sidebar's secondary destinations. Selection is a `MedxPadSelection` so the two
    /// kinds of tab share one binding; the main half stays wired to `appState.selectedTab`.
    ///
    /// The `TabView` is inline rather than in an `@available` helper: `.agents/availability_audit.py`
    /// only recognises an `if #available` block as a guard for the iOS 18 `Tab` / `.sidebarAdaptable`
    /// APIs.
    @ViewBuilder
    private var iPadLayout: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: padSelection) {
                // Library is *not* a top tab on iPad: its grid is redundant with the "Library"
                // sidebar section below, and having both was the duplicate "Library" the user saw.
                // The four remaining destinations are the primary tabs; everything the Library tab
                // launched lives in the section.
                ForEach(iPadMainTabs) { tab in
                    Tab(
                        tab.rawValue,
                        systemImage: appState.selectedTab == tab ? tab.selectedIcon : tab.icon,
                        value: MedxPadSelection.main(tab)
                    ) {
                        NavigationStack {
                            destination(for: tab)
                        }
                    }
                }

                TabSection("Library") {
                    ForEach(MedxPadLibraryTab.allCases) { lib in
                        Tab(lib.title, systemImage: lib.icon, value: MedxPadSelection.library(lib)) {
                            NavigationStack {
                                libraryDestination(lib)
                            }
                        }
                    }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            // A deep link that flips the main tab must pull the sidebar back out of a library
            // destination; selecting a library item leaves `selectedTab` untouched, so this only
            // fires for genuine main-tab changes.
            .onChange(of: appState.selectedTab) { _, _ in padLibrarySelection = nil }
        } else {
            splitLayout
        }
    }

    /// The iPad's primary tabs: every destination except Library, whose contents ride the sidebar
    /// section instead.
    private var iPadMainTabs: [TabItem] { TabItem.allCases.filter { $0 != .library } }

    /// Bridges the unified `MedxPadSelection` to the app's `selectedTab` plus a local record of
    /// which library destination (if any) is open. A library tab leaves `selectedTab` alone so
    /// returning to a main tab restores exactly where it was.
    private var padSelection: Binding<MedxPadSelection> {
        Binding(
            get: {
                if let lib = padLibrarySelection { return .library(lib) }
                // Library is not a top tab here, so a stray `.library` (carried from the phone or a
                // deep link) shows Home rather than selecting a tab that does not exist.
                let tab: TabItem = appState.selectedTab == .library ? .home : appState.selectedTab
                return .main(tab)
            },
            set: { newValue in
                switch newValue {
                case .main(let tab):
                    padLibrarySelection = nil
                    appState.selectedTab = tab
                case .library(let lib):
                    padLibrarySelection = lib
                }
            }
        )
    }

    /// The detail view behind each library sidebar tab.
    @ViewBuilder
    private func libraryDestination(_ tab: MedxPadLibraryTab) -> some View {
        switch tab {
        case .flashcards: FlashcardsSubjectListView()
        case .vodFeed: VodFeedView()
        case .importVod: VodImportView()
        case .faceoff: FaceoffLobbyView()
        case .batchPapers: BatchPapersView()
        case .customModules: CustomModulesView()
        case .search: MedxQuestionSearchView()
        case .bookmarks: BookmarkedQuestionsView(uid: uid)
        case .downloads: DownloadsView()
        case .activityLog: MedxActivityLogHost(uid: uid)
        }
    }

    // MARK: - iPad (iOS 17 fallback)

    /// Two columns on a regular width: the five destinations plus the library actions in a
    /// sidebar, the destination itself in the detail column. The detail stack is keyed on the
    /// selection so switching sections starts at that section's root rather than restoring a
    /// stale push from the previous one.
    ///
    /// Only reached on iOS 17 now — iOS 18+ iPads get the adaptive tab bar above.
    private var splitLayout: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            NavigationStack {
                destination(for: appState.selectedTab)
                    // With the sidebar collapsed there is no way left to change section — the
                    // sidebar was the only tab switcher. A segmented bar rides the top of the
                    // detail column so the five destinations stay one tap apart. It hides itself
                    // the moment the sidebar is back, so the switcher is never shown twice.
                    .toolbar {
                        if columnVisibility == .detailOnly {
                            ToolbarItem(placement: .principal) {
                                iPadTabSwitcher
                            }
                        }
                    }
            }
            .id(appState.selectedTab)
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// The top tab bar for a collapsed sidebar: the five destinations as a segmented control,
    /// bound to the same selection the sidebar drives.
    private var iPadTabSwitcher: some View {
        Picker("Section", selection: $appState.selectedTab) {
            ForEach(TabItem.allCases) { tab in
                Label(
                    tab.rawValue,
                    systemImage: appState.selectedTab == tab ? tab.selectedIcon : tab.icon
                )
                .labelStyle(.iconOnly)
                .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 320)
    }

    private var sidebar: some View {
        List(selection: sidebarSelection) {
            Section {
                ForEach(TabItem.allCases) { tab in
                    Label(
                        tab.rawValue,
                        systemImage: appState.selectedTab == tab ? tab.selectedIcon : tab.icon
                    )
                    .symbolEffect(.bounce, value: appState.selectedTab == tab)
                    .tag(tab)
                }
            } header: {
                Text("Study")
            }

            Section("Play") {
                sidebarAction("Faceoff", icon: "bolt.horizontal") {
                    appState.open(route: .faceoff)
                }
            }

            Section("Library") {
                sidebarAction("Flashcards", icon: "rectangle.stack") {
                    appState.open(route: .flashcards)
                }
                sidebarAction("VOD feed", icon: "antenna.radiowaves.left.and.right") {
                    appState.open(route: .vodFeed)
                }
                sidebarAction("Import to Classes", icon: "tray.and.arrow.down") {
                    appState.open(route: .importVod)
                }
                sidebarAction("Batch papers", icon: "flag.pattern.checkered") {
                    appState.open(route: .batchPapers)
                }
                sidebarAction("Custom modules", icon: "slider.horizontal.3") {
                    appState.open(route: .customModules)
                }
                sidebarAction("Search questions", icon: "magnifyingglass") {
                    appState.open(route: .search(nil))
                }
                sidebarAction("Bookmarks", icon: "bookmark") {
                    appState.showBookmarks = true
                }
                sidebarAction("Downloads", icon: "arrow.down.circle") {
                    appState.showDownloads = true
                }
            }

            Section {
                sidebarAction("Settings", icon: "gearshape") {
                    appState.showSettings = true
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("MedX Elite")
    }

    private func sidebarAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.light()
            action()
        } label: {
            Label(title, systemImage: icon)
                .foregroundStyle(.primary)
                .frame(minHeight: 34)
        }
    }

    /// `List` wants an optional selection; a nil arriving from a deselect is ignored so the
    /// detail column never goes blank.
    private var sidebarSelection: Binding<TabItem?> {
        Binding(
            get: { appState.selectedTab },
            set: { newValue in
                guard let newValue else { return }
                appState.selectedTab = newValue
            }
        )
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
    /// Cold-launched from Siri there may be no attempt history in memory yet, so it is
    /// fetched here rather than assuming Home has already run.
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
                id: "revision-" + String(UUID().uuidString.prefix(8)),
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

/// One selection type for the iPad `.sidebarAdaptable` `TabView`: a primary destination (the
/// floating top bar) or a library destination (the sidebar's own section).
enum MedxPadSelection: Hashable {
    case main(TabItem)
    case library(MedxPadLibraryTab)
}

/// The library destinations listed in the iPad sidebar. These are the browsable ones — the
/// transient builders (Quick sitting) and the profile-owned Settings stay off the list, reachable
/// from the Library tab and the profile button respectively.
enum MedxPadLibraryTab: String, CaseIterable, Identifiable, Hashable {
    case flashcards, vodFeed, importVod, faceoff, batchPapers, customModules, search, bookmarks, downloads, activityLog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flashcards: return "Flashcards"
        case .vodFeed: return "VOD feed"
        case .importVod: return "Import to Classes"
        case .faceoff: return "Faceoff"
        case .batchPapers: return "Batch papers"
        case .customModules: return "Custom modules"
        case .search: return "Search"
        case .bookmarks: return "Bookmarks"
        case .downloads: return "Downloads"
        case .activityLog: return "Activity log"
        }
    }

    var icon: String {
        switch self {
        case .flashcards: return "rectangle.stack"
        case .vodFeed: return "antenna.radiowaves.left.and.right"
        case .importVod: return "tray.and.arrow.down"
        case .faceoff: return "bolt.horizontal"
        case .batchPapers: return "flag.pattern.checkered"
        case .customModules: return "slider.horizontal.3"
        case .search: return "magnifyingglass"
        case .bookmarks: return "bookmark"
        case .downloads: return "arrow.down.circle"
        case .activityLog: return "list.bullet.rectangle.portrait"
        }
    }
}


// MARK: - Profile Avatar
//
// `ProfileSettingsButton` used to live here: a toolbar button drawing a `ProfileAvatarView` at 34pt —
// a photo if one had been picked, otherwise two letters over a two-stop `LinearGradient` inside a
// `strokeBorder` ring, with `AvatarStore` observed from all six toolbars that used it. It is
// `MedxSettingsMonogram` now: one circle, one letter, in the face every number in the app is set in.
//
// `ProfileAvatarView` itself stays, for the two places the picture *is* the content — choosing between
// two people on `ProfileSelectView`, and knowing whose turn it is in a duel.

/// Circular profile picture with an initials-over-gradient fallback when the
/// user has not chosen a photo yet.
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
                profile.gradient

                Text(profile.initials)
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            if showsRing {
                Circle()
                    .strokeBorder(profile.accentColor.opacity(0.45), lineWidth: max(1, size * 0.04))
            }
        }
        .accessibilityHidden(true)
    }
}
