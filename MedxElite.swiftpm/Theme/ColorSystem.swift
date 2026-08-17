import SwiftUI

public extension Color {
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

    // Native iOS system label colors
    static let secondaryLabel = Color(uiColor: .secondaryLabel)
    static let tertiaryLabel = Color(uiColor: .tertiaryLabel)
    static let quaternaryLabel = Color(uiColor: .quaternaryLabel)
}

public enum MedxTheme {
    // MARK: - Brand Accents (iOS Dynamic Colors)
    public static let primaryBlue = Color(uiColor: .systemBlue)
    public static let primaryPurple = Color(uiColor: .systemPurple)
    public static let primaryPink = Color(uiColor: .systemPink)
    public static let successGreen = Color(uiColor: .systemGreen)
    public static let warningOrange = Color(uiColor: .systemOrange)
    public static let destructiveRed = Color(uiColor: .systemRed)
    public static let cyanAccent = Color(uiColor: .systemCyan)
    public static let indigoAccent = Color(uiColor: .systemIndigo)
    public static let mintAccent = Color(uiColor: .systemMint)
    public static let tealAccent = Color(uiColor: .systemTeal)

    // MARK: - Semantic Backgrounds (System Dynamic)
    public static let background = Color(uiColor: .systemBackground)
    public static let secondaryBackground = Color(uiColor: .secondarySystemBackground)
    public static let tertiaryBackground = Color(uiColor: .tertiarySystemBackground)
    public static let groupedBackground = Color(uiColor: .systemGroupedBackground)

    // MARK: - Semantic Card Fills
    /// Adaptive card fill for grouped content
    public static let cardFill = Color(uiColor: .secondarySystemGroupedBackground)
    /// Elevated card fill for floating elements
    public static let elevatedFill = Color(uiColor: .tertiarySystemBackground)
    /// Subtle separator
    public static let separator = Color(uiColor: .separator)

    // MARK: - Vibrant Label Colors
    public static let vibrancyPrimary = Color(uiColor: .label)
    public static let vibrancySecondary = Color(uiColor: .secondaryLabel)
    public static let vibrancyTertiary = Color(uiColor: .tertiaryLabel)
    public static let vibrancyQuaternary = Color(uiColor: .quaternaryLabel)

    // MARK: - Premium Gradients
    public static let auroraGradient = LinearGradient(
        colors: [
            Color(hex: "#0A84FF").opacity(0.85),
            Color(hex: "#BF5AF2").opacity(0.85),
            Color(hex: "#FF375F").opacity(0.85)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let oceanGradient = LinearGradient(
        colors: [Color(hex: "#0A84FF"), Color(hex: "#5AC8FA"), Color(hex: "#64D2FF")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let sunsetGradient = LinearGradient(
        colors: [Color(hex: "#FF9F0A"), Color(hex: "#FF375F"), Color(hex: "#BF5AF2")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let emeraldGradient = LinearGradient(
        colors: [Color(hex: "#30D158"), Color(hex: "#63E6BE"), Color(hex: "#5AC8FA")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Card Glass Gradients
    public static let cardGlassGradient = LinearGradient(
        colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    public static let darkCardGlassGradient = LinearGradient(
        colors: [Color(hex: "#1C1C1E").opacity(0.8), Color(hex: "#0E0E10").opacity(0.9)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Shadow Presets
    public enum Shadow {
        /// Subtle shadow — elevation 1
        public static let subtle = (color: Color.black.opacity(0.06), radius: CGFloat(4), y: CGFloat(2))
        /// Medium shadow — elevation 2
        public static let medium = (color: Color.black.opacity(0.10), radius: CGFloat(10), y: CGFloat(4))
        /// Prominent shadow — elevation 3
        public static let prominent = (color: Color.black.opacity(0.16), radius: CGFloat(20), y: CGFloat(8))
        /// Colored shadow for accented elements
        public static func colored(_ color: Color) -> (color: Color, radius: CGFloat, y: CGFloat) {
            (color: color.opacity(0.35), radius: 16, y: 6)
        }
    }
}
