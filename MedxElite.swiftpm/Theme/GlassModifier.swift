import SwiftUI

// MARK: - Native iOS Card & Container Modifiers
// These provide standard iOS grouped-style card backgrounds
// that look native and let the system handle all visual treatment.

/// Simple native iOS card background using system grouped colors
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
    }
}

// MARK: - View Extensions (backward-compatible API)

public extension View {
    /// Native iOS card background — system grouped cell style
    func liquidGlassCard(cornerRadius: CGFloat = 16, borderWidth: CGFloat = 1, glowColor: Color? = nil) -> some View {
        self.modifier(NativeCardModifier(cornerRadius: cornerRadius, accentColor: glowColor))
    }

    /// Native iOS capsule background for floating bars
    func liquidGlassFloating(cornerRadius: CGFloat = 28) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
            )
    }

    /// Native iOS capsule styling with optional tint
    func liquidGlassCapsule(tintColor: Color? = nil) -> some View {
        self
            .background(Capsule().fill(.regularMaterial))
    }
}
