import SwiftUI

// MARK: - Pure iOS Native Liquid Glass Design System
// Multi-layer materials (.ultraThinMaterial, .regularMaterial), specular refractive borders,
// dynamic dark/light vibrancy, and ambient chromatic glow shadows.

/// Multi-layered Liquid Glass Card with specular refraction and ambient glow
public struct LiquidGlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var material: Material
    public var glowColor: Color?
    public var shadowLevel: Int

    public init(
        cornerRadius: CGFloat = 20,
        material: Material = .ultraThinMaterial,
        glowColor: Color? = nil,
        shadowLevel: Int = 1
    ) {
        self.cornerRadius = cornerRadius
        self.material = material
        self.glowColor = glowColor
        self.shadowLevel = shadowLevel
    }

    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // 1. Dynamic material foundation
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(material)

                    // 2. Adaptive grouped background tint
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.65))

                    // 3. Subtle ambient chromatic tint
                    if let glow = glowColor {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [glow.opacity(0.06), glow.opacity(0.01), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
            )
            // 4. Specular inner highlight border (Apple Liquid Glass refraction)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.10),
                                Color.white.opacity(0.02),
                                (glowColor ?? Color.white).opacity(0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            // 5. Chromatic ambient glow + elevation drop shadow
            .shadow(
                color: glowColor.map { $0.opacity(0.16) } ?? MedxTheme.Shadow.subtle.color,
                radius: glowColor != nil ? 14 : shadowRadius,
                x: 0,
                y: glowColor != nil ? 6 : shadowY
            )
    }

    private var shadowRadius: CGFloat {
        switch shadowLevel {
        case 0: return 0
        case 1: return MedxTheme.Shadow.subtle.radius
        case 2: return MedxTheme.Shadow.medium.radius
        default: return MedxTheme.Shadow.prominent.radius
        }
    }

    private var shadowY: CGFloat {
        switch shadowLevel {
        case 0: return 0
        case 1: return MedxTheme.Shadow.subtle.y
        case 2: return MedxTheme.Shadow.medium.y
        default: return MedxTheme.Shadow.prominent.y
        }
    }
}

/// Compact Liquid Glass Tile for row items, option buttons, and pills
public struct LiquidGlassTileModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var accentColor: Color?
    public var isSelected: Bool

    public init(cornerRadius: CGFloat = 16, accentColor: Color? = nil, isSelected: Bool = false) {
        self.cornerRadius = cornerRadius
        self.accentColor = accentColor
        self.isSelected = isSelected
    }

    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    if let color = accentColor, isSelected {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(color.opacity(0.12))
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected && accentColor != nil
                            ? (accentColor!.opacity(0.5))
                            : Color.white.opacity(0.15),
                        lineWidth: isSelected ? 1.5 : 0.8
                    )
            )
            .shadow(
                color: isSelected && accentColor != nil ? accentColor!.opacity(0.2) : Color.black.opacity(0.04),
                radius: isSelected ? 8 : 4,
                x: 0,
                y: isSelected ? 4 : 2
            )
    }
}

// MARK: - View Modifiers Extension

public extension View {
    /// Pure iOS Native Liquid Glass Card
    func liquidGlassCard(
        cornerRadius: CGFloat = 20,
        glowColor: Color? = nil,
        shadowLevel: Int = 1
    ) -> some View {
        self.modifier(LiquidGlassCardModifier(
            cornerRadius: cornerRadius,
            material: .ultraThinMaterial,
            glowColor: glowColor,
            shadowLevel: shadowLevel
        ))
    }

    /// Glass card with material background (alias)
    func glassCard(cornerRadius: CGFloat = 20, shadowLevel: Int = 1) -> some View {
        self.modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, material: .ultraThinMaterial, shadowLevel: shadowLevel))
    }

    /// Prominent card with thicker material and stronger specular highlight
    func prominentCard(cornerRadius: CGFloat = 20, glowColor: Color? = nil) -> some View {
        self.modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, material: .regularMaterial, glowColor: glowColor, shadowLevel: 2))
    }

    /// Compact Liquid Glass Tile for row items, option buttons, and pills
    func liquidGlassTile(cornerRadius: CGFloat = 16, accentColor: Color? = nil, isSelected: Bool = false) -> some View {
        self.modifier(LiquidGlassTileModifier(cornerRadius: cornerRadius, accentColor: accentColor, isSelected: isSelected))
    }

    /// Floating bar with ultra-thin glass and refractive borders
    func liquidGlassFloating(cornerRadius: CGFloat = 28) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: Color.black.opacity(0.16), radius: 20, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.4), Color.white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
    }

    /// Capsule pill with frosted glass
    func liquidGlassCapsule(tintColor: Color? = nil) -> some View {
        self
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        tintColor?.opacity(0.3) ?? Color.white.opacity(0.18),
                        lineWidth: 0.8
                    )
            )
            .shadow(
                color: tintColor?.opacity(0.15) ?? Color.black.opacity(0.04),
                radius: 6,
                y: 2
            )
    }

    /// Elevated material card for overlays & sheets
    func elevatedCard(cornerRadius: CGFloat = 24) -> some View {
        self.modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, material: .thickMaterial, shadowLevel: 3))
    }
}
