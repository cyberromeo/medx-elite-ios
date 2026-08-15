import SwiftUI

public struct LiquidGlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    public var cornerRadius: CGFloat
    public var borderWidth: CGFloat
    public var glowColor: Color?

    public init(cornerRadius: CGFloat = 20, borderWidth: CGFloat = 1, glowColor: Color? = nil) {
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.glowColor = glowColor
    }

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colorScheme == .dark ? Color(hex: "#1E1E24").opacity(0.7) : Color.white.opacity(0.85))
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                (glowColor ?? Color.white).opacity(colorScheme == .dark ? 0.35 : 0.6),
                                Color.white.opacity(colorScheme == .dark ? 0.05 : 0.2),
                                (glowColor ?? Color.clear).opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: borderWidth
                    )
            )
            .shadow(
                color: (glowColor ?? Color.black).opacity(colorScheme == .dark ? 0.25 : 0.08),
                radius: 14,
                x: 0,
                y: 8
            )
    }
}

public struct LiquidGlassFloatingModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    public var cornerRadius: CGFloat

    public init(cornerRadius: CGFloat = 28) {
        self.cornerRadius = cornerRadius
    }

    public func body(content: Content) -> some View {
        content
            .background(
                Capsule()
                    .fill(colorScheme == .dark ? Color(hex: "#16161A").opacity(0.85) : Color.white.opacity(0.92))
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.3 : 0.7),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.15),
                radius: 20,
                x: 0,
                y: 10
            )
    }
}

public extension View {
    func liquidGlassCard(cornerRadius: CGFloat = 20, borderWidth: CGFloat = 1, glowColor: Color? = nil) -> some View {
        self.modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, borderWidth: borderWidth, glowColor: glowColor))
    }

    func liquidGlassFloating(cornerRadius: CGFloat = 28) -> some View {
        self.modifier(LiquidGlassFloatingModifier(cornerRadius: cornerRadius))
    }
}
