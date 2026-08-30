import SwiftUI

/// The app's five top-level destinations.
///
/// `Videos` used to be the fifth and is now a row inside `Library`, which is the tab that
/// holds everything that is not a study surface in its own right: the class library and the
/// raw VOD feed, the ARISE batch papers, Faceoff, the custom modules, and the saved things.
/// Five tabs is what iOS lays out comfortably on the smallest target device, and the new
/// destinations would have made six.
///
/// (File name is historical: this used to also hold a custom floating glass tab bar.
/// `MainTabView` now uses the system `TabView`, which brings the platform's own
/// appearance, accessibility, and iPad/Mac behaviour for free.)
public enum TabItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case qbank = "QBank"
    case tests = "Tests"
    case flashcards = "Cards"
    case library = "Library"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .home: return "house"
        case .qbank: return "books.vertical"
        case .tests: return "checkmark.seal"
        case .flashcards: return "rectangle.stack"
        case .library: return "square.grid.2x2"
        }
    }

    public var selectedIcon: String {
        switch self {
        case .home: return "house.fill"
        case .qbank: return "books.vertical.fill"
        case .tests: return "checkmark.seal.fill"
        case .flashcards: return "rectangle.stack.fill"
        case .library: return "square.grid.2x2.fill"
        }
    }

    /// The hue this destination owns, so a tab and the screen behind it agree.
    public var section: MedxSection {
        switch self {
        case .home: return .home
        case .qbank: return .qbank
        case .tests: return .tests
        case .flashcards: return .cards
        case .library: return .library
        }
    }
}
