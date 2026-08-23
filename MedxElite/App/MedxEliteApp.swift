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

        case .active:
            Task { await MedxNotificationManager.shared.refreshAuthorization() }

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

    /// Widget taps arrive as `medxelite://<route>`.
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
        default:
            appState.open(route: .home)
        }
    }
}
