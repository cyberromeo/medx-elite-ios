import SwiftUI

public extension Color {
    /// Hex initialiser. Used by `Profile`, whose accent and gradient come from the
    /// backend as hex strings.
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    // System label colours, spelled as SwiftUI colours.
    static let secondaryLabel = Color(uiColor: .secondaryLabel)
    static let tertiaryLabel = Color(uiColor: .tertiaryLabel)
    static let quaternaryLabel = Color(uiColor: .quaternaryLabel)
}

/// Semantic colour tokens.
///
/// Every one is a *system* colour, so the whole app inverts correctly in Dark Mode and
/// respects Increase Contrast without a second palette. The tokens exist to give meaning
/// a name — "correct" is green, "ungraded" is orange — not to invent brand colours. Plain
/// UI accents use `Color.accentColor` directly.
public enum MedxTheme {
    public static let primaryBlue = Color(uiColor: .systemBlue)
    public static let primaryPurple = Color(uiColor: .systemPurple)
    public static let primaryPink = Color(uiColor: .systemPink)
    public static let successGreen = Color(uiColor: .systemGreen)
    public static let warningOrange = Color(uiColor: .systemOrange)
    public static let destructiveRed = Color(uiColor: .systemRed)
    public static let cyanAccent = Color(uiColor: .systemCyan)
    public static let indigoAccent = Color(uiColor: .systemIndigo)
    public static let tealAccent = Color(uiColor: .systemTeal)

    // MARK: - Rich-text colours
    //
    // Arise's question HTML carries hard-coded inline colours from a light-mode web
    // editor: `color:#fff` on white, `background-color:#ffffff` highlights, black body
    // text. Rendered verbatim, those words vanish in Dark Mode. `MedxRichText` maps them
    // onto these dynamic tokens instead, so a highlight stays a highlight in both
    // appearances and coloured emphasis keeps its meaning without failing contrast.
    public enum RichText {
        /// Body copy. Always the system label so it inverts with the appearance.
        public static var label: UIColor { .label }
        public static var secondaryLabel: UIColor { .secondaryLabel }

        /// Replaces any authored highlight (`<mark>`, `background-color`, white-on-white
        /// spans): warm yellow in light, deep amber in dark, label-coloured text on top.
        public static var highlightBackground: UIColor {
            UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor(red: 0.62, green: 0.46, blue: 0.05, alpha: 0.45)
                    : UIColor(red: 1.00, green: 0.91, blue: 0.45, alpha: 0.75)
            }
        }

        public static var highlightForeground: UIColor { .label }

        public static var emphasisRed: UIColor { .systemRed }
        public static var emphasisGreen: UIColor { .systemGreen }
        public static var emphasisBlue: UIColor { .systemBlue }
        public static var emphasisOrange: UIColor { .systemOrange }
        public static var emphasisPurple: UIColor { .systemPurple }
    }
}
