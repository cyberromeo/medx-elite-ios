import SwiftUI

// MARK: - Ink (forwarder)
//
// The palette moved to `Theme/MedxDS.swift`. This file is what carries the move to the ~90 call sites
// that spell it `MedxInk.raised` / `MedxRadius.card` / `MedxMotion.snap`, without touching any of them:
// every token below is a one-line forward, so the new surface stack, the new radii and the new motion
// curves arrive everywhere at once and the diff stays readable.
//
// It goes away when the screens are rewritten. Nothing new should reach for `MedxInk`.
//
// One token is deliberately *not* forwarded, because it no longer exists: there is no `rim`. The
// top-lit bevel it fed was drawn as a `LinearGradient` `strokeBorder` on every one of the app's 82
// surfaces, on top of a hairline, on top of a `.shadow` that was invisible on a black page — four
// layers to say "this rectangle is nearer the eye" when a 15-unit step in fill says it for one. See
// rule 2 at the top of `MedxDS.swift`.

public enum MedxInk {
    public static var page: Color { MedxDS.page }
    /// Was `#101013`. Now the card step, which is also what a list row sits on.
    public static var raised: Color { MedxDS.raised }
    public static var sunken: Color { MedxDS.sunken }
    /// A control's resting fill. `field` and `sunken` were two names for nearly the same colour; both
    /// now land on `sunken`, which is the one the design has.
    public static var field: Color { MedxDS.sunken }
    public static var hairline: Color { MedxDS.line }
}

// MARK: - Geometry

public enum MedxRadius {
    public static var card: CGFloat { MedxDS.card }
    /// A tile is a control-sized rectangle. The separate 16pt step went with the tile surface.
    public static var tile: CGFloat { MedxDS.control }
    public static var control: CGFloat { MedxDS.control }
    public static var hud: CGFloat { MedxDS.hud }
}

// MARK: - Motion

public enum MedxMotion {
    public static var snap: Animation { MedxDS.snap }
    public static var settle: Animation { MedxDS.settle }
    public static var pop: Animation { MedxDS.pop }
}

// MARK: - Entrance

/// **A no-op, deliberately.**
///
/// This lifted and faded a card into place on its first `onAppear`, staggered by index. Home applied it
/// to nine children and Library to eleven, which meant twenty springs resolving in the first frames
/// after a tab switch — on the two screens a student opens most. An entrance animation on a whole page
/// of cards is not motion, it is latency you can see.
///
/// The app's one arrival animation is now the answer sheet filling in (`MedxAnswerSheet`), which is a
/// single interpolated `Double` driving one `Canvas`. That is one animation on the screen instead of
/// twenty, and it is the screen's subject rather than its furniture.
///
/// Left as a no-op rather than deleted so this phase stays a small diff; the 11 call sites go with the
/// screens that carry them.
public struct MedxAppearModifier: ViewModifier {
    public init(index: Int) {}

    public func body(content: Content) -> some View {
        content
    }
}

public extension View {
    func medxAppear(index: Int = 0) -> some View {
        modifier(MedxAppearModifier(index: index))
    }
}
