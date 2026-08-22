import SwiftUI

@main
struct MedxEliteApp: App {
    @StateObject private var authService = AuthService.shared
    @StateObject private var appState = AppState.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isAuthenticated {
                    MainTabView()
                } else {
                    ProfileSelectView()
                }
            }
            // A cross-fade only. The old spring scale made every cold launch feel like the
            // app had bounced onto screen.
            .animation(.easeInOut(duration: 0.28), value: authService.isAuthenticated)
            .environmentObject(authService)
            .environmentObject(appState)
            .tint(MedxTheme.primaryBlue)
            .task {
                // Drop cache files written by an older decoding schema before any screen
                // reads them, so a poisoned payload cannot render an empty tab.
                await CacheManager.shared.pruneStaleVersions()
                HLSProxyServer.shared.start()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background, .inactive:
                    ActivityStore.shared.flushPendingWrites()
                case .active:
                    if let uid = authService.currentSession?.uid {
                        Task { await ActivityStore.shared.syncWithCloud(uid: uid) }
                    }
                @unknown default:
                    break
                }
            }
        }
    }
}
