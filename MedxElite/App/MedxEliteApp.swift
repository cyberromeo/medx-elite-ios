import SwiftUI

@main
struct MedxEliteApp: App {
    @StateObject private var authService = AuthService.shared
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isAuthenticated {
                    MainTabView()
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    ProfileSelectView()
                        .transition(.opacity)
                }
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: authService.isAuthenticated)
            .environmentObject(authService)
            .environmentObject(appState)
        }
    }
}
