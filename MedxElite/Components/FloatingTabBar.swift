import SwiftUI

/// The app's five top-level destinations.
///
/// (File name is historical: this used to also hold a custom floating glass tab bar.
/// `MainTabView` now uses the system `TabView`, which brings the platform's own
/// appearance, accessibility, and iPad/Mac behaviour for free.)
public enum TabItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case qbank = "QBank"
    case tests = "Tests"
    case flashcards = "Cards"
    case videos = "Videos"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .home: return "house"
        case .qbank: return "books.vertical"
        case .tests: return "checkmark.seal"
        case .flashcards: return "rectangle.stack"
        case .videos: return "play.rectangle"
        }
    }

    public var selectedIcon: String {
        switch self {
        case .home: return "house.fill"
        case .qbank: return "books.vertical.fill"
        case .tests: return "checkmark.seal.fill"
        case .flashcards: return "rectangle.stack.fill"
        case .videos: return "play.rectangle.fill"
        }
    }
}
