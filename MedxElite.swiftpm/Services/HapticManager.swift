import UIKit

/// Tactile feedback, callable from anywhere.
///
/// Deliberately **not** `@MainActor`. Haptics are fired from button actions, gesture handlers,
/// `contextMenu` items and `Task` bodies all over the app, most of which are nonisolated —
/// annotating every one of those call sites just to reach a feedback generator would be noise,
/// and the compiler rejected thirteen of them. The hop lives here instead, and is skipped
/// entirely when we are already on the main thread so the tap and the tick are not a frame apart.
public enum HapticManager {
    public static func selection() {
        onMain {
            let generator = UISelectionFeedbackGenerator()
            generator.prepare()
            generator.selectionChanged()
        }
    }

    public static func light() { impact(.light) }

    public static func medium() { impact(.medium) }

    public static func heavy() { impact(.heavy) }

    public static func success() { notify(.success) }

    public static func error() { notify(.error) }

    public static func warning() { notify(.warning) }

    private static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        onMain {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred()
        }
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        onMain {
            let generator = UINotificationFeedbackGenerator()
            generator.prepare()
            generator.notificationOccurred(type)
        }
    }

    /// UIKit's feedback generators are main-actor only.
    private static func onMain(_ work: @escaping @Sendable @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            Task { @MainActor in work() }
        }
    }
}
