import SwiftUI

// MARK: - Dynamic Type Scale

public enum MedxFont {
    public static func hero(_ size: CGFloat = 34) -> Font {
        .system(.largeTitle, design: .rounded, weight: .heavy)
    }

    public static func title(_ size: CGFloat = 28) -> Font {
        .system(titleStyle(for: size), design: .default, weight: .bold)
    }

    public static func titleRounded(_ size: CGFloat = 28) -> Font {
        .system(titleStyle(for: size), design: .rounded, weight: .bold)
    }

    public static func headline(_ size: CGFloat = 17) -> Font {
        .system(size >= 19 ? .title3 : .headline, design: .rounded, weight: .semibold)
    }

    public static func body(_ size: CGFloat = 17) -> Font {
        .system(size <= 15 ? .subheadline : .body, design: .default, weight: .regular)
    }

    public static func bodyMedium(_ size: CGFloat = 17) -> Font {
        .system(size <= 15 ? .subheadline : .body, design: .default, weight: .medium)
    }

    public static func caption(_ size: CGFloat = 12) -> Font {
        .system(size >= 14 ? .subheadline : (size <= 11 ? .caption2 : .caption), design: .default, weight: .medium)
    }

    public static func label(_ size: CGFloat = 13) -> Font {
        .system(size >= 15 ? .subheadline : .caption, design: .rounded, weight: .semibold)
    }

    public static func mono(_ size: CGFloat = 14, weight: Font.Weight = .bold) -> Font {
        .system(metricStyle(for: size), design: .monospaced, weight: weight).monospacedDigit()
    }

    public static func condensed(_ size: CGFloat = 14, weight: Font.Weight = .medium) -> Font {
        .system(metricStyle(for: size), design: .default, weight: weight).width(.condensed)
    }

    public static func expanded(_ size: CGFloat = 14, weight: Font.Weight = .semibold) -> Font {
        .system(metricStyle(for: size), design: .default, weight: weight).width(.expanded)
    }

    public static func rounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(metricStyle(for: size), design: .rounded, weight: weight)
    }

    public static func monospacedDigits(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(metricStyle(for: size), design: .monospaced, weight: weight).monospacedDigit()
    }

    private static func titleStyle(for size: CGFloat) -> Font.TextStyle {
        if size >= 32 { return .largeTitle }
        if size >= 26 { return .title }
        return .title2
    }

    private static func metricStyle(for size: CGFloat) -> Font.TextStyle {
        if size >= 17 { return .body }
        if size >= 14 { return .subheadline }
        if size >= 12 { return .caption }
        return .caption2
    }
}
