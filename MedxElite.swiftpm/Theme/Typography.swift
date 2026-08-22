import SwiftUI

/// Type helpers.
///
/// The app spells fonts as native text styles at the point of use — `.headline`,
/// `.subheadline.weight(.semibold)`, `.caption.monospacedDigit()` — rather than routing
/// them through a size-based indirection. That keeps Dynamic Type honest and makes the
/// intent readable in the view code, so what remains here are only the shapes that are
/// genuinely worth naming.
public enum MedxFont {
    /// A figure that must not reflow as its digits change — timers, scores, counters.
    public static func metric(_ style: Font.TextStyle = .body, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .default, weight: weight).monospacedDigit()
    }

    /// Rounded display numerals used as headlines (the exam countdown's day count).
    /// Fixed-size on purpose: it already scales itself down and must not wrap.
    public static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
