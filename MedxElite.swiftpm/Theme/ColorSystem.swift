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
}

public enum MedxTheme {
    // Dynamic brand accents
    public static let primaryBlue = Color(hex: "#0A84FF")
    public static let primaryPurple = Color(hex: "#BF5AF2")
    public static let primaryPink = Color(hex: "#FF375F")
    public static let successGreen = Color(hex: "#30D158")
    public static let warningOrange = Color(hex: "#FF9F0A")
    public static let destructiveRed = Color(hex: "#FF453A")
    public static let cyanAccent = Color(hex: "#64D2FF")
    public static let indigoAccent = Color(hex: "#5E5CE6")

    // Dynamic backgrounds
    public static let background = Color(uiColor: .systemBackground)
    public static let secondaryBackground = Color(uiColor: .secondarySystemBackground)
    public static let tertiaryBackground = Color(uiColor: .tertiarySystemBackground)
    public static let groupedBackground = Color(uiColor: .systemGroupedBackground)

    // Glass gradients
    public static let auroraGradient = LinearGradient(
        colors: [Color(hex: "#0A84FF").opacity(0.8), Color(hex: "#BF5AF2").opacity(0.8), Color(hex: "#FF375F").opacity(0.8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

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
}
