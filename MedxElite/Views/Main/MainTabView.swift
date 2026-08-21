import SwiftUI

public struct MainTabView: View {
    @State private var selectedTab: TabItem = .home

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label(TabItem.home.rawValue, systemImage: selectedTab == .home ? TabItem.home.selectedIcon : TabItem.home.icon)
            }
            .tag(TabItem.home)

            NavigationStack {
                QBankSubjectListView()
            }
            .tabItem {
                Label(TabItem.qbank.rawValue, systemImage: selectedTab == .qbank ? TabItem.qbank.selectedIcon : TabItem.qbank.icon)
            }
            .tag(TabItem.qbank)

            NavigationStack {
                TestsListView()
            }
            .tabItem {
                Label(TabItem.tests.rawValue, systemImage: selectedTab == .tests ? TabItem.tests.selectedIcon : TabItem.tests.icon)
            }
            .tag(TabItem.tests)

            NavigationStack {
                FlashcardsSubjectListView()
            }
            .tabItem {
                Label(TabItem.flashcards.rawValue, systemImage: selectedTab == .flashcards ? TabItem.flashcards.selectedIcon : TabItem.flashcards.icon)
            }
            .tag(TabItem.flashcards)

            NavigationStack {
                VideosBatchListView()
            }
            .tabItem {
                Label(TabItem.videos.rawValue, systemImage: selectedTab == .videos ? TabItem.videos.selectedIcon : TabItem.videos.icon)
            }
            .tag(TabItem.videos)
        }
        .tint(.accentColor)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarBackground(.bar, for: .tabBar)
        .onChange(of: selectedTab) { _, _ in
            HapticManager.selection()
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
                Text(String(profile.displayName.prefix(1)).uppercased())
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(profile.accentColor)
                    .frame(width: 44, height: 44)
                    .liquidGlassCircle(tintColor: profile.accentColor)
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
