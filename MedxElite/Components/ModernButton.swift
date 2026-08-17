import SwiftUI

public struct ModernButton: View {
    public let title: String
    public var icon: String?
    public var gradient: LinearGradient
    public var height: CGFloat
    public var cornerRadius: CGFloat
    public var isBusy: Bool
    public var action: () -> Void

    public init(
        title: String,
        icon: String? = nil,
        gradient: LinearGradient = LinearGradient(
            colors: [MedxTheme.primaryBlue, MedxTheme.cyanAccent],
            startPoint: .leading,
            endPoint: .trailing
        ),
        height: CGFloat = 52,
        cornerRadius: CGFloat = 14,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.gradient = gradient
        self.height = height
        self.cornerRadius = cornerRadius
        self.isBusy = isBusy
        self.action = action
    }

    public var body: some View {
        Button {
            HapticManager.medium()
            action()
        } label: {
            Group {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading…")
                } else if let icon {
                    Label(title, systemImage: icon)
                } else {
                    Text(title)
                }
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: max(height, 44))
        }
        .buttonStyle(.borderedProminent)
        .tint(MedxTheme.primaryBlue)
        .controlSize(.large)
        .disabled(isBusy)
        .accessibilityHint(isBusy ? "Please wait" : "Activates this action")
    }
}

/// Compatibility style for existing call sites. It now uses a restrained
/// native press response rather than a springy game-like animation.
public struct BouncyButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
