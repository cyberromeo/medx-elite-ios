import SwiftUI
import CoreSpotlight

@main
struct MedxEliteApp: App {
    @StateObject private var authService = AuthService.shared
    @StateObject private var appState = AppState.shared
    @StateObject private var theme = MedxAccentThemeStore.shared
    @StateObject private var stats = MedxStudyStatsStore.shared
    @Environment(\.scenePhase) private var scenePhase

    /// The splash is an overlay, not a gate: the real root is already mounted and fetching
    /// underneath it, so this only controls how long the mark is visible.
    @State private var showSplash = true

    /// When the app last went to the background, so a return after a real absence refreshes what
    /// is on screen (a flick to Control Centre does not).
    @State private var backgroundedAt: Date?

    /// A `BGTaskScheduler` registration has to happen before the app finishes launching, and it
    /// traps if it happens later — so it goes in `init`, not in the `.task` that runs after the
    /// first frame. It also traps if the identifier is missing from
    /// `Info.plist ▸ BGTaskSchedulerPermittedIdentifiers`, which is why both live together.
    init() {
        // DEBUG builds launched with `-medxDemo YES` (the simulator screenshot job) answer every
        // backend call from fixtures; in Release this is an empty stub.
        MedxDemoMode.install()
        MedxVodWatcher.registerBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                root
                    // A cross-fade only. The old spring scale made every cold launch feel
                    // like the app had bounced onto screen.
                    .animation(.easeInOut(duration: 0.28), value: authService.isAuthenticated)

                if showSplash {
                    MedxSplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .environmentObject(authService)
            .environmentObject(appState)
            .environmentObject(theme)
            .environmentObject(stats)
            // `.tint` drives the system's own controls; deliberate accents in the app read
            // `MedxTheme.accent`, because `Color.accentColor` does not follow this.
            .tint(theme.accent.color)
            .preferredColorScheme(theme.appearance.colorScheme)
            .task { await bootstrap() }
            .onOpenURL { url in
                handle(url: url)
            }
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard let route = MedxSpotlightIndexer.route(for: activity) else { return }
                appState.open(route: route)
            }
            .onChange(of: scenePhase) { _, phase in
                handle(scenePhase: phase)
            }
        }
    }

    @ViewBuilder
    private var root: some View {
        if authService.isAuthenticated {
            MainTabView()
        } else {
            ProfileSelectView()
        }
    }

    // MARK: - Launch

    @MainActor
    private func bootstrap() async {
        // Drop cache files written by an older decoding schema before any screen reads
        // them, so a poisoned payload cannot render an empty tab.
        await CacheManager.shared.pruneStaleVersions()

        // Still needed: the proxy is the only thing that can attach the CDN's expected
        // headers to a *live* stream. Downloads no longer go through it.
        HLSProxyServer.shared.start()

        // Touching `.shared` installs the notification-centre delegate.
        await MedxNotificationManager.shared.refreshAuthorization()
        stats.publishSnapshot()

        // The Firebase SDK is configured for one feature — Faceoff's snapshot listeners — and its
        // sign-in is separate from the REST one, so a restored session has to re-do it. Both are
        // fire-and-forget: the rest of the app is on the REST path either way.
        if !MedxDemoMode.isOn {
            MedxFirebaseBridge.shared.configure()
            Task { await authService.restoreSDKSession() }
        }

        // Long enough for the mark to read as an entrance rather than a flicker, short
        // enough that it never becomes a wait.
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        withAnimation(.easeOut(duration: 0.35)) { showSplash = false }

        #if DEBUG
        await runScreenshotDirector()
        #endif
    }

    #if DEBUG
    /// Screenshot runs only: `-medxScreen <name>` opens one screen after launch, so the simulator
    /// job can capture each of them without a tap. Every route is one the app already has.
    @MainActor
    private func runScreenshotDirector() async {
        guard MedxDemoMode.isOn,
              let screen = UserDefaults.standard.string(forKey: "medxScreen")
        else { return }

        // `-medxLandscape YES`: the iPad job's landscape pass asks the scene to turn itself.
        if UserDefaults.standard.bool(forKey: "medxLandscape"),
           let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
            try? await Task.sleep(nanoseconds: 600_000_000)
        }

        let demoModule = MedxModulePick(
            id: "qb_375",
            name: "Gram-Positive Cocci: Staphylococcus & Streptococcus",
            subject: "Microbiology",
            questionCount: 12
        )

        switch screen {
        case "home", "syllabus": appState.open(route: .home)
        case "qbank", "subject":
            UserDefaults.standard.set(MedxBank.arise.rawValue, forKey: "medx.qbank.bank")
            appState.open(route: .qbank)
        case "qbank-marrow":
            UserDefaults.standard.set(MedxBank.marrow.rawValue, forKey: "medx.qbank.bank")
            appState.open(route: .qbank)
        case "tests": appState.open(route: .tests)
        case "classes", "videosubject": appState.open(route: .classes)
        case "import": appState.open(route: .importVod)
        case "library": appState.open(route: .library)
        case "flashcards", "deck": appState.open(route: .flashcards)
        case "vod": appState.open(route: .vodFeed)
        case "batch": appState.open(route: .batchPapers)
        case "search": appState.open(route: .search(nil))
        case "custom": appState.open(route: .customModules)
        case "faceoff": appState.open(route: .faceoff)
        case "bookmarks": appState.open(route: .bookmarks)
        case "downloads", "player-offline": appState.open(route: .downloads)
        case "settings": appState.open(route: .settings)
        case "module": appState.open(route: .module(demoModule))
        case "runner-batch":
            appState.startSitting(
                RunnerPayload(
                    kind: "test",
                    id: "test_5",
                    name: "ARISE Mock 7 (new upload)",
                    subject: "All subjects",
                    mode: .exam,
                    gradable: true
                )
            )
        case "runner-custom", "review-custom":
            // A mixed paper: every question says which paper it came from.
            let papers = ["FMGE June 2023", "FMGE Dec 2022", "FMGE June 2022", "FMGE Jan 2023"]
            appState.startSitting(
                RunnerPayload(
                    kind: "qbank",
                    id: demoModule.id,
                    name: "Weak spots mix",
                    subject: "Custom",
                    mode: .exam,
                    questionTags: (0..<200).map { papers[$0 % papers.count] }
                )
            )
        case "runner-custom-next":
            // The real custom-module route: the Custom modules sheet is open, the paper is built
            // from fetched questions, and the sitting starts from inside that sheet.
            appState.open(route: .customModules)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let token = (try? await AuthService.shared.getValidIdToken()) ?? ""
            let module = try? await FirestoreService.shared.fetchQBankModule(moduleId: demoModule.id, idToken: token)
            let supplied = module?.questions ?? []
            print("[CustomNext] built \(supplied.count) questions from the sheet")
            appState.startSitting(
                RunnerPayload(
                    kind: "custom",
                    id: "demo-custom-next",
                    name: "Weak spots mix",
                    subject: "Custom",
                    mode: .exam,
                    gradable: true,
                    questions: supplied.isEmpty ? nil : supplied,
                    questionTags: supplied.isEmpty ? nil : supplied.indices.map { $0 % 2 == 0 ? "FMGE June 2023" : "FMGE Dec 2022" }
                )
            )
        case "runner-zoom":
            appState.startSitting(
                RunnerPayload(
                    kind: "qbank",
                    id: demoModule.id,
                    name: demoModule.name,
                    subject: demoModule.subject,
                    mode: .revision
                )
            )
        case "runner", "runner-revision", "review", "runner-navigator", "runner-answered", "runner-lowtime",
             "runner-submit", "runner-resume", "runner-leave", "review-question", "runner-revision-pick":
            appState.startSitting(
                RunnerPayload(
                    kind: "qbank",
                    id: demoModule.id,
                    name: demoModule.name,
                    subject: demoModule.subject,
                    mode: screen.hasPrefix("runner-revision") ? .revision : .exam
                )
            )
        default: break
        }
    }
    #endif

    // MARK: - Scene phase

    @MainActor
    private func handle(scenePhase phase: ScenePhase) {
        switch phase {
        case .background, .inactive:
            if phase == .background { backgroundedAt = Date() }
            ActivityStore.shared.flushPendingWrites()
            // Leaving the app is exactly when the widgets need the latest numbers.
            stats.publishSnapshot()
            // Re-armed on the way out, so the next opportunistic wake has something to run.
            MedxVodWatcher.shared.scheduleBackgroundCheck()

        case .active:
            // Coming back after a minute or more: everything cached is marked stale (kept for
            // offline, no longer served as current) and the screens on show refetch, so a module,
            // paper or class added on the backend appears without clearing the cache by hand.
            if let away = backgroundedAt, Date().timeIntervalSince(away) > 60 {
                backgroundedAt = nil
                Task {
                    await CacheManager.shared.markAllStale()
                    NotificationCenter.default.post(name: .medxContentShouldRefresh, object: nil)
                }
            }

            // The local HLS proxy has to be re-armed here, and this is the fix for "minimise the app,
            // come back, no video plays". iOS closes listening sockets when it suspends a process, and
            // `NWListener`'s state handler does not get to run while suspended — so nothing in the app
            // ever learned the socket had gone.
            //
            // `revalidate()` and not `restart()`: audio is a declared background mode, so a class can
            // still be playing through the proxy when this fires — coming back from Control Centre is an
            // `.active` too. An unconditional rebind would cut a stream that was working. This probes
            // first and only rebinds if nothing answers.
            Task { await HLSProxyServer.shared.revalidate() }

            Task { await MedxNotificationManager.shared.refreshAuthorization() }
            // The foreground check is the *guarantee* behind the new-drop notification: iOS may
            // not run the background task for days, so returning to the app is what actually
            // keeps the badge and the watermark honest. One document read.
            Task { await MedxVodWatcher.shared.refreshFromForeground() }

            guard let uid = authService.currentSession?.uid else { return }
            Task {
                await ActivityStore.shared.syncWithCloud(uid: uid)
                await MedxSpotlightIndexer.shared.indexBookmarks(
                    ActivityStore.shared.bookmarks(for: uid)
                )
            }

        @unknown default:
            break
        }
    }

    // MARK: - Deep links

    /// Widget taps and notification taps arrive as `medxelite://<route>`.
    @MainActor
    private func handle(url: URL) {
        guard url.scheme == "medxelite" else { return }

        switch url.host {
        case "revision":
            appState.open(route: .todaysRevision)
        case "search":
            appState.open(route: .search(nil))
        case "downloads":
            appState.open(route: .downloads)
        case "qbank":
            appState.open(route: .qbank)
        case "tests":
            appState.open(route: .tests)
        case "library":
            appState.open(route: .library)
        case "classes", "videos":
            appState.open(route: .classes)
        case "cards", "flashcards":
            appState.open(route: .flashcards)
        case "vod":
            appState.open(route: .vodFeed)
        case "custom":
            appState.open(route: .customModules)
        case "faceoff":
            // `medxelite://faceoff/<gameId>` opens that room; the bare host opens the lobby.
            let gameId = url.pathComponents.first { $0 != "/" && !$0.isEmpty }
            if let gameId {
                appState.open(route: .faceoffRoom(gameId))
            } else {
                appState.open(route: .faceoff)
            }
        default:
            appState.open(route: .home)
        }
    }
}
