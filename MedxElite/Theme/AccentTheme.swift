import SwiftUI

// MARK: - Accent
//
// The app ships one accent in the asset catalogue, but the student can override it in
// Settings. `Color.accentColor` reads the *catalogue* value and does not reliably follow a
// `.tint()` modifier, so every deliberate accent in this project goes through
// `MedxTheme.accent` instead. `.tint()` is still applied at the root, because the system's
// own controls (toggles, `ProgressView`, prominent buttons) only listen to that.

public enum MedxAccent: String, CaseIterable, Identifiable, Sendable {
    case blue, indigo, purple, pink, teal, green, orange, graphite

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .blue: return "Blue"
        case .indigo: return "Indigo"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .teal: return "Teal"
        case .green: return "Green"
        case .orange: return "Orange"
        case .graphite: return "Graphite"
        }
    }

    /// A system colour every time, so Dark Mode and Increase Contrast keep working.
    public var color: Color {
        switch self {
        case .blue: return Color(uiColor: .systemBlue)
        case .indigo: return Color(uiColor: .systemIndigo)
        case .purple: return Color(uiColor: .systemPurple)
        case .pink: return Color(uiColor: .systemPink)
        case .teal: return Color(uiColor: .systemTeal)
        case .green: return Color(uiColor: .systemGreen)
        case .orange: return Color(uiColor: .systemOrange)
        case .graphite: return Color(uiColor: .systemGray)
        }
    }

    /// Dark-appearance hex, handed to the widgets through `MedxStudySnapshot.accentHex`
    /// because the extension cannot resolve a dynamic `UIColor`.
    public var hex: String {
        switch self {
        case .blue: return "#0A84FF"
        case .indigo: return "#5E5CE6"
        case .purple: return "#BF5AF2"
        case .pink: return "#FF375F"
        case .teal: return "#40C8E0"
        case .green: return "#30D158"
        case .orange: return "#FF9F0A"
        case .graphite: return "#98989D"
        }
    }
}

public extension MedxAccent {
    static let storageKey = "medx.theme.accent"

    /// Non-isolated read of the persisted choice.
    ///
    /// Deliberately not routed through `MedxAccentThemeStore` (which is `@MainActor`): plain
    /// value types tint themselves too — `RunnerQuestionStatus.trackColor(isCurrent:)` is a
    /// method on an enum, not a view — and they must be able to ask from any context.
    /// `UserDefaults` keeps its values in process, so this is a dictionary lookup.
    static var current: MedxAccent {
        MedxAccent(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .blue
    }
}

// MARK: - Appearance

public enum MedxAppearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .system: return "Automatic"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    public var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// `nil` hands the decision back to the system.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Store

/// Owns the two appearance choices. Views that draw the accent themselves observe this so
/// SwiftUI knows to re-evaluate their bodies when it changes — reading
/// `MedxTheme.accent` alone creates no dependency, because a static property is not
/// something SwiftUI can track.
@MainActor
public final class MedxAccentThemeStore: ObservableObject {
    public static let shared = MedxAccentThemeStore()

    @Published public var accent: MedxAccent {
        didSet {
            guard accent != oldValue else { return }
            UserDefaults.standard.set(accent.rawValue, forKey: MedxAccent.storageKey)
        }
    }

    @Published public var appearance: MedxAppearance {
        didSet {
            guard appearance != oldValue else { return }
            UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey)
        }
    }

    private static let appearanceKey = "medx.theme.appearance"

    private init() {
        accent = MedxAccent.current
        appearance = MedxAppearance(
            rawValue: UserDefaults.standard.string(forKey: Self.appearanceKey) ?? ""
        ) ?? .dark
    }

    /// Set both in one transaction so a single animation covers the whole repaint.
    public func apply(accent newAccent: MedxAccent) {
        guard newAccent != accent else { return }
        accent = newAccent
    }
}

// MARK: - Token

public extension MedxTheme {
    /// The one accent every deliberate tint in the app should use.
    static var accent: Color { MedxAccent.current.color }
}
