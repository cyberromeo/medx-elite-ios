import SwiftUI
import UIKit

// MARK: - Ink
//
// The app's surface stack, and the reason the glass came back out.
//
// The pass before this one wired `medxSurface` into every primitive, so a screen was thirty
// panes of `glassEffect` over a section-hued wash. Glass over glass over a gradient is haze —
// the same failure the *first* attempt hit from the opposite direction, and the note at the top
// of `MedxLiquidGlass.swift` is now about where glass is allowed rather than how to make it
// work.
//
// So: **content is ink, chrome is glass.** Ink is opaque, has no blur pass, and looks identical
// on iOS 17 and iOS 26. Glass is reserved for the three floating places listed in
// `MedxLiquidGlass.swift`.
//
// Dark is the design — pure black page, near-black cards, a white hairline for the edge and a
// top-lit rim for the elevation, because on `#000` a drop shadow is invisible and a bevel is
// the only thing left that can say "this is nearer". Light is not an afterthought though: the
// Appearance picker in Settings still works, so every token below is a *dynamic* colour with a
// real light value.

public enum MedxInk {
    /// The page. `#000` in dark — the whole point.
    public static let page = solid(dark: 0x000000, light: 0xFFFFFF)

    /// A card. One step off the page, which in dark is one step *up*.
    public static let raised = solid(dark: 0x101013, light: 0xF2F2F7)

    /// A tile inside a card — an answer row, a stat cell, a matrix square.
    public static let sunken = solid(dark: 0x17171C, light: 0xEBEBF0)

    /// A control's resting fill: text fields, unselected segments, disabled buttons.
    public static let field = solid(dark: 0x1D1D22, light: 0xE4E4EA)

    /// The edge. Never `.separator`: that token is tuned for a grey page and disappears on black.
    public static let hairline = wash(dark: 0xFFFFFF, darkAlpha: 0.09, light: 0x000000, lightAlpha: 0.09)

    /// The top-lit bevel that stands in for a shadow. See `MedxSurfaceModifier.rim`.
    public static let rim = wash(dark: 0xFFFFFF, darkAlpha: 0.14, light: 0xFFFFFF, lightAlpha: 0.85)

    // MARK: Builders

    private static func solid(dark: UInt32, light: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) })
    }

    private static func wash(
        dark: UInt32,
        darkAlpha: CGFloat,
        light: UInt32,
        lightAlpha: CGFloat
    ) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? rgb(dark).withAlphaComponent(darkAlpha)
                : rgb(light).withAlphaComponent(lightAlpha)
        })
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Geometry
//
// "No sharp ends" is a rule, not a preference: every rectangle in the app is
// `style: .continuous`, every control is a `Capsule`, and nothing is tighter than `control`.
// A 9pt radius on a 34pt chip reads as a sticker with corners; a squircle reads as a control.

public enum MedxRadius {
    /// A content card.
    public static let card: CGFloat = 20
    /// A tile inside a card.
    public static let tile: CGFloat = 16
    /// The smallest radius the app allows — small marks, badges, inline chips.
    public static let control: CGFloat = 12
    /// Floating chrome: the runner HUD, a bottom bar.
    public static let hud: CGFloat = 26
}

// MARK: - Motion
//
// One vocabulary, three entries, so "how fast does this move" is answered in a single place
// rather than by whichever `easeOut(duration:)` was nearest to hand. Every use is gated on
// `accessibilityReduceMotion` at the call site.

public enum MedxMotion {
    /// A state change the finger asked for: a segment switching, a button becoming Finish.
    public static let snap = Animation.snappy(duration: 0.26, extraBounce: 0.02)

    /// Something arriving or leaving — a card, an explanation, a sheet's content.
    public static let settle = Animation.spring(response: 0.42, dampingFraction: 0.84)

    /// Press feedback and small glyph pops. Stiff enough to feel like contact rather than
    /// like a delay.
    public static let pop = Animation.interpolatingSpring(stiffness: 320, damping: 22)
}

// MARK: - Entrance

/// A card rising into place, once.
///
/// Deliberately **not** a `scrollTransition`. There used to be one of those here and it was
/// removed for a good reason — content that dims and slides while you are trying to read it
/// fights the scroll instead of decorating it. This latches: `shown` is set on the first
/// `onAppear` and never goes back, so a card that has arrived stays arrived no matter how far
/// the page is scrolled past it and back.
///
/// `index` staggers a group, capped so a long grid does not end with a card arriving half a
/// second late.
public struct MedxAppearModifier: ViewModifier {
    private let index: Int

    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(index: Int) {
        self.index = index
    }

    public func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 8)
            .onAppear {
                guard !reduceMotion, !shown else { return }
                withAnimation(MedxMotion.settle.delay(Double(min(index, 6)) * 0.04)) {
                    shown = true
                }
            }
    }

    /// Under Reduce Motion the view is simply there — no fade, no rise, no wait for the
    /// animation that is not going to run.
    private var isVisible: Bool { shown || reduceMotion }
}

public extension View {
    /// Fades and lifts this view into place on its first appearance. `index` staggers siblings.
    func medxAppear(index: Int = 0) -> some View {
        modifier(MedxAppearModifier(index: index))
    }
}
