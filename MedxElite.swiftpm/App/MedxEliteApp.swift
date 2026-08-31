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

    /// A `BGTaskScheduler` registration has to happen before the app finishes launching, and it
    /// traps if it happens later — so it goes in `init`, not in the `.task` that runs after the
    /// first frame. It also traps if the identifier is missing from
    /// `Info.plist ▸ BGTaskSchedulerPermittedIdentifiers`, which is why both live together.
    init() {
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
        MedxFirebaseBridge.shared.configure()
        Task { await authService.restoreSDKSession() }

        // Long enough for the mark to read as an entrance rather than a flicker, short
        // enough that it never becomes a wait.
        try? await Task.sleep(nanoseconds: 1_100_000_000)
        withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
    }

    // MARK: - Scene phase

    @MainActor
    private func handle(scenePhase phase: ScenePhase) {
        switch phase {
        case .background, .inactive:
            ActivityStore.shared.flushPendingWrites()
            // Leaving the app is exactly when the widgets need the latest numbers.
            stats.publishSnapshot()
            // Re-armed on the way out, so the next opportunistic wake has something to run.
            MedxVodWatcher.shared.scheduleBackgroundCheck()

        case .active:
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
