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
        .medxFilledButton()
        .buttonBorderShape(.capsule)
        .tint(tint)
        .disabled(isBusy)
        .accessibilityHint(isBusy ? "Please wait" : "")
    }
}

/// Press feedback for custom card-shaped buttons.
///
/// Used to be a 1.5% scale and an `easeOut` — so restrained it was hard to be sure it was there.
/// It is a real spring now: `MedxMotion.pop` is stiff enough that the card feels like it is being
/// pushed rather than animated, which is the whole point of a press state. 4% is the most a
/// full-width card can take before its neighbours look like they moved too.
public struct BouncyButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Pressable(configuration: configuration)
    }

    /// A nested `View` rather than styling `configuration.label` directly: `@Environment` read
    /// inside `makeBody` is not re-evaluated when the environment changes, and Reduce Motion has
    /// to be able to turn the scale off.
    private struct Pressable: View {
        let configuration: ButtonStyleConfiguration

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.82 : 1)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.12) : MedxMotion.pop,
                    value: configuration.isPressed
                )
        }
    }
}

// MARK: - Candy call to action

/// The full-width primary action on a section's own hue.
///
/// `.buttonStyle(.borderedProminent).tint(MedxCandy.lime)` cannot be used for these: SwiftUI
/// derives the label colour from the tint and picks white, which on lime measures under 1.5:1.
/// This is the same capsule with `MedxCandy.onSolid` on top instead — see the note there for
/// why the label does not invert with the appearance.
///
/// The label keeps its own font and frame, exactly as it would under `.borderedProminent`, so
/// this drops into a full-width bar and a 34pt inline Run button alike.
public struct MedxFilledButtonStyle: ButtonStyle {
    private let hue: Color

    public init(hue: Color) {
        self.hue = hue
    }

    public func makeBody(configuration: Configuration) -> some View {
        Filled(configuration: configuration, hue: hue)
    }

    /// A nested `View` rather than styling `configuration.label` directly, because
    /// `@Environment` read inside `makeBody` is not re-evaluated when the environment changes —
    /// and `isEnabled` is the whole reason a disabled Deal button has to look disabled.
    private struct Filled: View {
        let configuration: ButtonStyleConfiguration
        let hue: Color

        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? MedxCandy.onSolid : Color.secondary)
                .background(Capsule().fill(isEnabled ? hue : MedxInk.field))
                .contentShape(Capsule())
                .opacity(configuration.isPressed ? 0.86 : 1)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.12) : MedxMotion.pop,
                    value: configuration.isPressed
                )
        }
    }
}

public extension View {
    /// `.medxFilled(MedxSection.duel.fill)` — the candy equivalent of `.borderedProminent`.
    func medxFilled(_ hue: Color) -> some View {
        buttonStyle(MedxFilledButtonStyle(hue: hue))
    }
}
