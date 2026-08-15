import SwiftUI

public enum TabItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case qbank = "QBank"
    case tests = "Tests"
    case flashcards = "Cards"
    case videos = "Videos"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .home: return "house.fill"
        case .qbank: return "books.vertical.fill"
        case .tests: return "checkmark.seal.fill"
        case .flashcards: return "sparkles.rectangle.stack.fill"
        case .videos: return "play.tv.fill"
        }
    }
}

public struct FloatingTabBar: View {
    @Binding public var selectedTab: TabItem
    @Namespace private var animationNamespace

    public init(selectedTab: Binding<TabItem>) {
        self._selectedTab = selectedTab
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(TabItem.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    HapticManager.selection()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if isSelected {
                                Capsule()
                                    .fill(MedxTheme.primaryBlue.opacity(0.18))
                                    .matchedGeometryEffect(id: "TabPill", in: animationNamespace)
                                    .frame(height: 36)
                            }
                            Image(systemName: tab.icon)
                                .font(.system(size: 18, weight: isSelected ? .bold : .medium))
                                .foregroundColor(isSelected ? MedxTheme.primaryBlue : .secondary)
                        }
                        .frame(maxWidth: .infinity)

                        Text(tab.rawValue)
                            .font(MedxFont.rounded(10, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? MedxTheme.primaryBlue : .secondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .liquidGlassFloating(cornerRadius: 32)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
}
