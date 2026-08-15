import SwiftUI

// MARK: - Apple Liquid Glass Design System

/// Core Apple Liquid Glass modifier providing multi-layer optical depth, specular rim lighting, and frosted material refraction.
public struct AppleLiquidGlassCard: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    public var cornerRadius: CGFloat
    public var tintColor: Color?
    public var isInteractive: Bool

    public init(cornerRadius: CGFloat = 24, tintColor: Color? = nil, isInteractive: Bool = false) {
        self.cornerRadius = cornerRadius
        self.tintColor = tintColor
        self.isInteractive = isInteractive
    }

    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Layer 1: Frosted Ultra-Thin Glass Material
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    // Layer 2: Subtle Ambient Color Wash
                    if let tint = tintColor {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(colorScheme == .dark ? 0.12 : 0.08),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }

                    // Layer 3: Inner Glass Highlight / Specular Sheen (Top Reflection)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(colorScheme == .dark ? 0.12 : 0.4), location: 0),
                                    .init(color: Color.white.opacity(0.02), location: 0.25),
                                    .init(color: Color.clear, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            )
            // Specular Rim Light Border (Apple Optical Refraction Line)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(colorScheme == .dark ? 0.45 : 0.75), location: 0.0),
                                .init(color: (tintColor ?? Color.white).opacity(colorScheme == .dark ? 0.25 : 0.4), location: 0.3),
                                .init(color: Color.white.opacity(colorScheme == .dark ? 0.06 : 0.15), location: 0.7),
                                .init(color: Color.white.opacity(colorScheme == .dark ? 0.2 : 0.35), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08),
                radius: 20,
                x: 0,
                y: 10
            )
            .shadow(
                color: (tintColor ?? Color.clear).opacity(colorScheme == .dark ? 0.18 : 0.08),
                radius: 24,
                x: 0,
                y: 12
            )
    }
}

/// Floating Liquid Glass Capsule for Tab Bars, Search Bars, Chips & Controls
public struct AppleLiquidGlassCapsule: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    public var tintColor: Color?

    public init(tintColor: Color? = nil) {
        self.tintColor = tintColor
    }

    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Capsule()
                        .fill(.regularMaterial)

                    if let tint = tintColor {
                        Capsule()
                            .fill(tint.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    }

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.16 : 0.5),
                                    Color.white.opacity(0.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(colorScheme == .dark ? 0.5 : 0.8), location: 0.0),
                                .init(color: Color.white.opacity(colorScheme == .dark ? 0.1 : 0.2), location: 0.5),
                                .init(color: Color.white.opacity(colorScheme == .dark ? 0.25 : 0.4), location: 1.0)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.12),
                radius: 24,
                x: 0,
                y: 12
            )
    }
}

/// Living Ambient Background Aura that refracts through Liquid Glass panels
public struct AmbientGlassAuraBackground: View {
    @State private var animate = false

    public init() {}

    public var body: some View {
        ZStack {
            Color(hex: "#0A0B10").ignoresSafeArea()

            // Dynamic blurred lighting caustics
            ZStack {
                // Top-Left Deep Indigo Blob
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "#3A5AFF").opacity(0.4), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 220
                        )
                    )
                    .frame(width: 440, height: 440)
                    .blur(radius: 80)
                    .offset(x: animate ? -80 : 40, y: animate ? -180 : -80)

                // Top-Right Vibrant Magenta Blob
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "#FF2D55").opacity(0.35), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 200
                        )
                    )
                    .frame(width: 400, height: 400)
                    .blur(radius: 75)
                    .offset(x: animate ? 100 : -20, y: animate ? -100 : -220)

                // Center-Bottom Cyan / Emerald Caustic Blob
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "#00F2FE").opacity(0.28), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 240
                        )
                    )
                    .frame(width: 460, height: 460)
                    .blur(radius: 90)
                    .offset(x: animate ? -60 : 80, y: animate ? 200 : 120)

                // Deep Purple Center Aura
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "#7F00FF").opacity(0.22), Color.clear],
                            center: .center,
                            startRadius: 30,
                            endRadius: 260
                        )
                    )
                    .frame(width: 500, height: 500)
                    .blur(radius: 100)
                    .offset(x: animate ? 40 : -60, y: animate ? 40 : -40)
            }
            .animation(.easeInOut(duration: 10).repeatForever(autoreverses: true), value: animate)
            .onAppear {
                animate = true
            }
        }
    }
}

// MARK: - View Extensions

public extension View {
    /// Applies Apple Liquid Glass material card styling with specular rim lighting and ambient refraction
    func liquidGlassCard(cornerRadius: CGFloat = 24, borderWidth: CGFloat = 1, glowColor: Color? = nil) -> some View {
        self.modifier(AppleLiquidGlassCard(cornerRadius: cornerRadius, tintColor: glowColor))
    }

    /// Applies Apple Liquid Glass capsule styling for floating bars and pills
    func liquidGlassFloating(cornerRadius: CGFloat = 28) -> some View {
        self.modifier(AppleLiquidGlassCapsule())
    }

    /// Applies Apple Liquid Glass capsule styling with tint
    func liquidGlassCapsule(tintColor: Color? = nil) -> some View {
        self.modifier(AppleLiquidGlassCapsule(tintColor: tintColor))
    }
}
