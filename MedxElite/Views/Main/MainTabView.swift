import SwiftUI

public struct MainTabView: View {
    @State private var selectedTab: TabItem = .home

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .home:
                    HomeView { tab in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            selectedTab = tab
                        }
                    }
                case .qbank:
                    QBankSubjectListView()
                case .tests:
                    TestsListView()
                case .flashcards:
                    FlashcardsSubjectListView()
                case .videos:
                    VideosBatchListView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom Floating Tab Bar
            FloatingTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(.keyboard)
    }
}
