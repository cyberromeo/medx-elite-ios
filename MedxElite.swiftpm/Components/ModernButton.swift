import SwiftUI

/// Full-width primary action button. Uses the system prominent style so it picks up the
/// platform's current material and press behaviour rather than a hand-rolled gradient.
public struct ModernButton: View {
    public let title: String
    public var icon: String?
    public var tint: Color
    public var isBusy: Bool
    public var action: () -> Void

    public init(
        title: String,
        icon: String? = nil,
        tint: Color = .accentColor,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.tint = tint
        self.isBusy = isBusy
        self.action = action
    }

    public var body: some View {
        Button {
            HapticManager.medium()
            action()
        } label: {
            HStack(spacing: 8) {
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
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(tint)
        .disabled(isBusy)
        .accessibilityHint(isBusy ? "Please wait" : "")
    }
}

/// Press feedback for custom card-shaped buttons. Restrained on purpose: a subtle dim and
/// a hair of scale, matching how system cells respond.
public struct BouncyButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
