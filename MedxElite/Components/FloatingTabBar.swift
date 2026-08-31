import SwiftUI

/// The app's five top-level destinations.
///
/// `Videos` is a tab because watching a class is a daily habit and it is the one thing here that
/// gets opened without a reason. `Cards` is not, for the opposite reason — flashcards are a thing
/// you go *to*, so they live in `Library` alongside the raw VOD feed, the ARISE batch papers,
/// Faceoff, the custom modules and the saved things. Five tabs is what iOS lays out comfortably on
/// the smallest target device, and everything above would have made nine.
///
/// (File name is historical: this used to also hold a custom floating glass tab bar.
/// `MainTabView` now uses the system `TabView`, which brings the platform's own
/// appearance, accessibility, and iPad/Mac behaviour for free.)
public enum TabItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case qbank = "QBank"
    case tests = "Tests"
    case videos = "Videos"
    case library = "Library"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .home: return "house"
        case .qbank: return "books.vertical"
        case .tests: return "list.clipboard"
        case .videos: return "play.rectangle"
        case .library: return "square.grid.2x2"
        }
    }

    public var selectedIcon: String {
        switch self {
        case .home: return "house.fill"
        case .qbank: return "books.vertical.fill"
        case .tests: return "list.clipboard.fill"
        case .videos: return "play.rectangle.fill"
        case .library: return "square.grid.2x2.fill"
        }
    }

    /// The hue this destination owns, so a tab and the screen behind it agree.
    public var section: MedxSection {
        switch self {
        case .home: return .home
        case .qbank: return .qbank
        case .tests: return .tests
        case .videos: return .videos
        case .library: return .library
        }
    }
}
