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
                Label(TabItem.home.rawValue, systemImage: "house.fill")
            }
            .tag(TabItem.home)

            NavigationStack {
                QBankSubjectListView()
            }
            .tabItem {
                Label(TabItem.qbank.rawValue, systemImage: "books.vertical.fill")
            }
            .tag(TabItem.qbank)

            NavigationStack {
                TestsListView()
            }
            .tabItem {
                Label(TabItem.tests.rawValue, systemImage: "checkmark.seal.fill")
            }
            .tag(TabItem.tests)

            NavigationStack {
                FlashcardsSubjectListView()
            }
            .tabItem {
                Label(TabItem.flashcards.rawValue, systemImage: "sparkles.rectangle.stack.fill")
            }
            .tag(TabItem.flashcards)

            NavigationStack {
                VideosBatchListView()
            }
            .tabItem {
                Label(TabItem.videos.rawValue, systemImage: "play.tv.fill")
            }
            .tag(TabItem.videos)
        }
    }
}
