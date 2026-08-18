import SwiftUI

// MARK: - Native Surface System
// Liquid Glass is reserved for functional surfaces and controls. Static content
// falls back to semantic system materials so the app remains legible on iOS 17–25.

public struct LiquidGlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var material: Material
    public var glowColor: Color?
    public var shadowLevel: Int

    public init(
        cornerRadius: CGFloat = 16,
        material: Material = .regularMaterial,
        glowColor: Color? = nil,
        shadowLevel: Int = 1
    ) {
        self.cornerRadius = cornerRadius
        self.material = material
        self.glowColor = glowColor
        self.shadowLevel = shadowLevel
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(material, in: shape)
            .background(shape.fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.72)))
            .overlay(shape.strokeBorder(Color(uiColor: .separator).opacity(0.52), lineWidth: 0.6))
            .shadow(
                color: glowColor?.opacity(0.08) ?? Color.black.opacity(shadowLevel > 1 ? 0.10 : 0.05),
                radius: shadowLevel > 1 ? 10 : 4,
                y: shadowLevel > 1 ? 4 : 2
            )
    }
}

public struct LiquidGlassTileModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var accentColor: Color?
    public var isSelected: Bool

    public init(cornerRadius: CGFloat = 14, accentColor: Color? = nil, isSelected: Bool = false) {
        self.cornerRadius = cornerRadius
        self.accentColor = accentColor
        self.isSelected = isSelected
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let accent = accentColor ?? Color.accentColor

        Group {
            if #available(iOS 26.0, *) {
                content
                    .glassEffect(
                        isSelected ? .regular.tint(accent) : .regular,
                        in: shape
                    )
            } else {
                content
                    .background(.thinMaterial, in: shape)
                    .background(shape.fill(isSelected ? accent.opacity(0.10) : Color(uiColor: .tertiarySystemGroupedBackground).opacity(0.88)))
                    .overlay(
                        shape.strokeBorder(
                            isSelected ? accent.opacity(0.55) : Color(uiColor: .separator).opacity(0.38),
                            lineWidth: isSelected ? 1 : 0.5
                        )
                    )
            }
        }
    }
}

public extension View {
    func liquidGlassCard(cornerRadius: CGFloat = 16, glowColor: Color? = nil, shadowLevel: Int = 1) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, glowColor: glowColor, shadowLevel: shadowLevel))
    }

    func glassCard(cornerRadius: CGFloat = 16, shadowLevel: Int = 1) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, shadowLevel: shadowLevel))
    }

    func prominentCard(cornerRadius: CGFloat = 16, glowColor: Color? = nil) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, material: .thickMaterial, glowColor: glowColor, shadowLevel: 2))
    }

    func liquidGlassTile(cornerRadius: CGFloat = 14, accentColor: Color? = nil, isSelected: Bool = false) -> some View {
        modifier(LiquidGlassTileModifier(cornerRadius: cornerRadius, accentColor: accentColor, isSelected: isSelected))
    }

    @ViewBuilder
    func liquidGlassFloating(cornerRadius: CGFloat = 20) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self
                .background(.bar, in: shape)
                .overlay(shape.strokeBorder(Color(uiColor: .separator).opacity(0.55), lineWidth: 0.6))
                .shadow(color: Color.black.opacity(0.10), radius: 8, y: 3)
        }
    }

    @ViewBuilder
    func medxNavigationGlass(cornerRadius: CGFloat = 16, tint: Color? = nil, interactive: Bool = true) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            if let tint {
                self.glassEffect(interactive ? .regular.tint(tint).interactive() : .regular.tint(tint), in: shape)
            } else {
                self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
            }
        } else {
            self
                .background(.thinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color(uiColor: .separator).opacity(0.52), lineWidth: 0.6))
                .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)
        }
    }

    @ViewBuilder
    func liquidGlassCapsule(tintColor: Color? = nil) -> some View {
        let tint = tintColor ?? Color.accentColor
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint), in: Capsule())
        } else {
            self
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                .overlay(Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 0.6))
        }
    }

    func elevatedCard(cornerRadius: CGFloat = 16) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, material: .thickMaterial, shadowLevel: 2))
    }
}

@available(iOS 26.0, *)
public struct MedxGlassControl<Label: View>: View {
    private let tint: Color?
    private let action: () -> Void
    private let label: () -> Label

    public init(tint: Color? = nil, action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.tint = tint
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button(action: action) {
            label()
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.glass(tint.map { .regular.tint($0) } ?? .regular))
    }
}
