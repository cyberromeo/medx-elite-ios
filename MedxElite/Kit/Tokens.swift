import SwiftUI

// MARK: - The kit's tokens
//
// One accent, chosen in Settings: `MedxTheme.accent` (Theme/ColorSystem.swift). Everything
// interactive — buttons, selection, progress — wears it. Colour that means something else is
// either an outcome (`MedxOutcome`) or the icon tile that tells one feature from another
// (`MedxFeature`), and nothing else is coloured. Pages are the system's grouped background,
// surfaces are the system's grouped cells, and the bars are glass because iOS 26 makes them so.

public enum MedxSpace {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
}

public enum MedxRadius {
    public static let control: CGFloat = 14
    public static let card: CGFloat = 22
}

/// Colour that means outcome — correct, wrong, flagged — and nothing else. System colours, so
/// Increase Contrast and both appearances keep working.
public enum MedxOutcome {
    public static var correct: Color { Color(uiColor: .systemGreen) }
    public static var wrong: Color { Color(uiColor: .systemRed) }
    public static var flagged: Color { Color(uiColor: .systemOrange) }
    public static var pending: Color { Color(uiColor: .systemGray) }
}

/// Every feature in the app, with the one name, symbol and colour it wears everywhere: the tab,
/// the title, the Library row and the sidebar all read from here, so none of them can call the
/// same place two things. The colour is for the icon tile only (Sri, 9 Oct 2026: icons keep
/// their colours; buttons, selection and progress are the accent).
public enum MedxFeature: String, CaseIterable, Identifiable, Sendable {
    case home, qbank, tests, classes, library
    case flashcards, customModules, quickSitting, search
    case vod, importClasses
    case faceoff
    case bookmarks, downloads, watchHistory, activityLog
    case batchPapers, syllabus, settings
    case streak, goal

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: return "Home"
        case .qbank: return "QBank"
        case .tests: return "Tests"
        case .classes: return "Classes"
        case .library: return "Library"
        case .flashcards: return "Flashcards"
        case .customModules: return "Custom modules"
        case .quickSitting: return "Quick sitting"
        case .search: return "Search questions"
        case .vod: return "VOD feed"
        case .importClasses: return "Import to Classes"
        case .faceoff: return "Faceoff"
        case .bookmarks: return "Bookmarks"
        case .downloads: return "Downloads"
        case .watchHistory: return "Watch history"
        case .activityLog: return "Activity log"
        case .batchPapers: return "Batch papers"
        case .syllabus: return "Syllabus"
        case .settings: return "Settings"
        case .streak: return "Streak"
        case .goal: return "Daily goal"
        }
    }

    public var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .qbank: return "books.vertical.fill"
        case .tests: return "list.clipboard.fill"
        case .classes: return "play.rectangle.fill"
        case .library: return "square.grid.2x2.fill"
        case .flashcards: return "rectangle.stack.fill"
        case .customModules: return "slider.horizontal.3"
        case .quickSitting: return "dice.fill"
        case .search: return "magnifyingglass"
        case .vod: return "antenna.radiowaves.left.and.right"
        case .importClasses: return "tray.and.arrow.down.fill"
        case .faceoff: return "bolt.fill"
        case .bookmarks: return "bookmark.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .watchHistory: return "clock.arrow.circlepath"
        case .activityLog: return "list.bullet.rectangle.portrait.fill"
        case .batchPapers: return "flag.pattern.checkered"
        case .syllabus: return "checklist"
        case .settings: return "gearshape.fill"
        case .streak: return "flame.fill"
        case .goal: return "target"
        }
    }

    /// The tile colour. Light and dark values so a tile reads the same on both pages; the
    /// values are the ones the app shipped with before the one-accent pass.
    public var color: Color {
        switch self {
        case .home, .goal: return MedxTheme.accent
        case .qbank: return Self.tone(light: 0x8BC34A, dark: 0xC2F53F)
        case .tests, .batchPapers: return Self.tone(light: 0xFF8A3D, dark: 0xFF9440)
        case .classes: return Self.tone(light: 0x8B5CF6, dark: 0x9B6CFF)
        case .library, .quickSitting, .activityLog: return Self.tone(light: 0x14B8A6, dark: 0x17E0BB)
        case .flashcards, .bookmarks: return Self.tone(light: 0xF5B800, dark: 0xFFDF55)
        case .vod, .watchHistory, .syllabus: return Self.tone(light: 0x3D7DFF, dark: 0x4B86FF)
        case .customModules, .importClasses: return Self.tone(light: 0xA855F7, dark: 0xB57BFF)
        case .faceoff: return Self.tone(light: 0xFF4D8D, dark: 0xFF3D85)
        case .search: return Self.tone(light: 0x1EA7E1, dark: 0x3AD3FF)
        case .downloads: return Color(uiColor: .systemGreen)
        case .settings: return Color(uiColor: .systemGray)
        case .streak: return Color(uiColor: .systemOrange)
        }
    }

    private static func tone(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

// MARK: - Ink on a colour

public extension Color {
    /// The label colour for text set on a solid fill of this colour: near-black on a light
    /// accent (teal, green, orange, graphite), white on a dark one (blue, indigo, purple, pink).
    func medxInkOnFill(in scheme: ColorScheme) -> Color {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let resolved = UIColor(self).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else { return .white }
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.62 ? Color(red: 0.08, green: 0.07, blue: 0.06) : .white
    }
}

// MARK: - Home's glow

/// Home's page background, and Home's only (Sri, 10 Oct 2026): the grouped background with one
/// soft glow of the accent behind the top, fading out by the time the first cards scroll in.
/// Drawn once, never animates, never sits on a card. Every other page is flat.
public struct MedxTopGlow: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    public init() {}

    public var body: some View {
        let strength = (scheme == .dark ? 0.28 : 0.14) * (contrast == .increased ? 0.5 : 1)
        ZStack(alignment: .top) {
            Color(uiColor: .systemGroupedBackground)
            RadialGradient(
                colors: [MedxTheme.accent.opacity(strength), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 420
            )
            .frame(height: 440)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
