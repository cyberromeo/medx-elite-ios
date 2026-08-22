import SwiftUI

public struct MainTabView: View {
    @ObservedObject private var appState = AppState.shared

    public init() {}

    public var body: some View {
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
        .tint(.accentColor)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.bar, for: .tabBar)
        .onChange(of: appState.selectedTab) { _, _ in
            HapticManager.selection()
        }
    }

    @ViewBuilder
    private func destination(for tab: TabItem) -> some View {
        switch tab {
        case .home: HomeView()
        case .qbank: QBankSubjectListView()
        case .tests: TestsListView()
        case .flashcards: FlashcardsSubjectListView()
        case .videos: VideosBatchListView()
        }
    }
}

public struct ProfileSettingsButton: View {
    @ObservedObject private var authService = AuthService.shared
    @State private var showSettings = false

    public init() {}

    public var body: some View {
        Button {
            HapticManager.light()
            showSettings = true
        } label: {
            if let profile = authService.currentProfile {
                ProfileAvatarView(profile: profile, size: 34)
                    .frame(width: 44, height: 44)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .fixedSize()
        .clipShape(Circle())
        .contentShape(Circle())
        .accessibilityLabel("Profile settings")
        .accessibilityHint("Opens account, bookmarks, history, and app settings")
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

// MARK: - Profile Avatar

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
