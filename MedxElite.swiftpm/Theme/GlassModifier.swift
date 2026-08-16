import SwiftUI

// MARK: - Modern iOS Card & Container Modifiers
// Uses real iOS materials (.ultraThinMaterial, .regularMaterial) and proper shadow hierarchy.

/// Material-based glass card with optional tint
public struct MaterialCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var material: Material
    public var shadowLevel: Int // 0 = none, 1 = subtle, 2 = medium, 3 = prominent

    public init(cornerRadius: CGFloat = 16, material: Material = .ultraThinMaterial, shadowLevel: Int = 1) {
        self.cornerRadius = cornerRadius
        self.material = material
        self.shadowLevel = shadowLevel
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(material)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
            )
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
    }

    private var shadowColor: Color {
        switch shadowLevel {
        case 0: return .clear
        case 1: return MedxTheme.Shadow.subtle.color
        case 2: return MedxTheme.Shadow.medium.color
        default: return MedxTheme.Shadow.prominent.color
        }
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

/// Native iOS card background using system grouped colors
public struct NativeCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var accentColor: Color?

    public init(cornerRadius: CGFloat = 16, accentColor: Color? = nil) {
        self.cornerRadius = cornerRadius
        self.accentColor = accentColor
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .shadow(
                color: MedxTheme.Shadow.subtle.color,
                radius: MedxTheme.Shadow.subtle.radius,
                x: 0,
                y: MedxTheme.Shadow.subtle.y
            )
    }
}

/// Interactive card with press state
public struct InteractiveCardStyle: ButtonStyle {
    var cornerRadius: CGFloat = 16

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
            .shadow(
                color: configuration.isPressed ? .clear : MedxTheme.Shadow.subtle.color,
                radius: configuration.isPressed ? 0 : MedxTheme.Shadow.subtle.radius,
                x: 0,
                y: configuration.isPressed ? 0 : MedxTheme.Shadow.subtle.y
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - View Extensions

public extension View {
    /// Glass card with material background
    func glassCard(cornerRadius: CGFloat = 16, shadowLevel: Int = 1) -> some View {
        self.modifier(MaterialCardModifier(cornerRadius: cornerRadius, material: .ultraThinMaterial, shadowLevel: shadowLevel))
    }

    /// Prominent card with thicker material
    func prominentCard(cornerRadius: CGFloat = 16) -> some View {
        self.modifier(MaterialCardModifier(cornerRadius: cornerRadius, material: .regularMaterial, shadowLevel: 2))
    }

    /// Native iOS card background — system grouped cell style
    /// Backward-compatible API name
    func liquidGlassCard(cornerRadius: CGFloat = 16, borderWidth: CGFloat = 1, glowColor: Color? = nil) -> some View {
        self.modifier(NativeCardModifier(cornerRadius: cornerRadius, accentColor: glowColor))
    }

    /// Floating bar with material background
    func liquidGlassFloating(cornerRadius: CGFloat = 28) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
            .shadow(
                color: MedxTheme.Shadow.medium.color,
                radius: MedxTheme.Shadow.medium.radius,
                x: 0,
                y: MedxTheme.Shadow.medium.y
            )
    }

    /// Capsule with material
    func liquidGlassCapsule(tintColor: Color? = nil) -> some View {
        self
            .background(Capsule().fill(.regularMaterial))
            .shadow(
                color: MedxTheme.Shadow.subtle.color,
                radius: MedxTheme.Shadow.subtle.radius,
                x: 0,
                y: MedxTheme.Shadow.subtle.y
            )
    }

    /// Elevated material card for overlays
    func elevatedCard(cornerRadius: CGFloat = 20) -> some View {
        self.modifier(MaterialCardModifier(cornerRadius: cornerRadius, material: .thickMaterial, shadowLevel: 3))
    }
}
