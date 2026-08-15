import SwiftUI

public struct ModernButton: View {
    public let title: String
    public var icon: String?
    public var gradient: LinearGradient = LinearGradient(
        colors: [MedxTheme.primaryBlue, MedxTheme.cyanAccent],
        startPoint: .leading,
        endPoint: .trailing
    )
    public var height: CGFloat = 54
    public var cornerRadius: CGFloat = 18
    public var isBusy: Bool = false
    public var action: () -> Void

    public init(
        title: String,
        icon: String? = nil,
        gradient: LinearGradient = LinearGradient(
            colors: [MedxTheme.primaryBlue, MedxTheme.cyanAccent],
            startPoint: .leading,
            endPoint: .trailing
        ),
        height: CGFloat = 54,
        cornerRadius: CGFloat = 18,
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
        Button(action: {
            HapticManager.medium()
            action()
        }) {
            HStack(spacing: 10) {
                if isBusy {
                    ProgressView()
                        .tint(.white)
                } else {
                    if let ic = icon {
                        Image(systemName: ic)
                            .font(.headline)
                    }
                    Text(title)
                        .font(MedxFont.rounded(16, weight: .bold))
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(gradient)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.blue.opacity(0.35), radius: 12, x: 0, y: 6)
        }
        .disabled(isBusy)
        .buttonStyle(BouncyButtonStyle())
    }
}

public struct BouncyButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
