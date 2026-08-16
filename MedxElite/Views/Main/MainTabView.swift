import SwiftUI

public struct MainTabView: View {
    @State private var selectedTab: TabItem = .home

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            Tab(TabItem.home.rawValue, systemImage: "house.fill", value: .home) {
                NavigationStack {
                    HomeView()
                }
            }

            Tab(TabItem.qbank.rawValue, systemImage: "books.vertical.fill", value: .qbank) {
                NavigationStack {
                    QBankSubjectListView()
                }
            }

            Tab(TabItem.tests.rawValue, systemImage: "checkmark.seal.fill", value: .tests) {
                NavigationStack {
                    TestsListView()
                }
            }

            Tab(TabItem.flashcards.rawValue, systemImage: "sparkles.rectangle.stack.fill", value: .flashcards) {
                NavigationStack {
                    FlashcardsSubjectListView()
                }
            }

            Tab(TabItem.videos.rawValue, systemImage: "play.tv.fill", value: .videos) {
                NavigationStack {
                    VideosBatchListView()
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}
