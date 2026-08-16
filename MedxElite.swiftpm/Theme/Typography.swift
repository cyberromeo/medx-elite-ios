import SwiftUI

// MARK: - SF Pro Exclusive Type Scale
// Uses only system fonts (SF Pro, SF Pro Rounded, SF Mono) — iOS exclusives.

public enum MedxFont {
    // MARK: - Display & Hero
    /// Large hero text — SF Pro Rounded, heavy weight
    public static func hero(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }

    // MARK: - Title
    /// Primary title — SF Pro, bold
    public static func title(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }

    /// Rounded title variant — SF Pro Rounded
    public static func titleRounded(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    // MARK: - Headline
    /// Section headline — SF Pro Rounded, semibold
    public static func headline(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    // MARK: - Body
    /// Body text — SF Pro, regular
    public static func body(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .regular, design: .default)
    }

    /// Body text emphasis — SF Pro, medium
    public static func bodyMedium(_ size: CGFloat = 17) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }

    // MARK: - Subheadline / Caption
    /// Caption text — SF Pro, medium
    public static func caption(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }

    /// Small label — SF Pro, semibold
    public static func label(_ size: CGFloat = 13) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    // MARK: - Monospaced (SF Mono)
    /// Monospaced digits for timers, counts — SF Mono
    public static func mono(_ size: CGFloat = 14, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .monospaced).monospacedDigit()
    }

    // MARK: - Width Variants
    /// Condensed for compact UI — SF Pro Condensed
    public static func condensed(_ size: CGFloat = 14, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    /// Expanded for emphasis — SF Pro Expanded
    public static func expanded(_ size: CGFloat = 14, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.expanded)
    }

    // MARK: - Legacy Compatibility
    /// Backward compatible — maps to rounded system font
    public static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Backward compatible — monospaced digits
    public static func monospacedDigits(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced).monospacedDigit()
    }
}
