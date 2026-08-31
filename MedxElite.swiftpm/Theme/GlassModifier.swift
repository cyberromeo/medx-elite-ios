import SwiftUI

// MARK: - Surface System
//
// The app's shared primitives — cards, tiles, metrics, chips, circle buttons — all of which now
// draw **ink**. See `Theme/MedxInk.swift` for the palette and `Theme/MedxLiquidGlass.swift` for
// the one rule that governs both files: content is ink, chrome is glass, and glass floats.
//
// This file used to open with an apology for the app's first glass attempt. The apology now
// covers two: the first wrapped everything in `.ultraThinMaterial` over flat grey, the second
// built a proper backdrop and then glassed all 75 call sites below. Both came out as haze. What
// survived both is the discipline, and it is what makes a third rewrite a small diff:
//
//   * One place decides what a rectangle is made of — `medxSurface` — and it also owns the
//     iOS 17 fallback and the Reduce Transparency escape hatch.
//   * Never put an `interactive()` glass effect inside a `Button` label. The effect takes the
//     touch and the button stops firing; that is what broke the flashcard close button.
//   * Glass near glass shares a `MedxGlassGroup`, because glass cannot sample glass.
//
// Every `medxCard` / `medxTile` call site in the app is untouched by this rewrite and simply
// renders opaque now.

public enum MedxSurface {
    /// Geometry and colour both forward to the token files, so there is one place to change a
    /// radius and one place to change a fill. Kept as `MedxSurface.*` because 60-odd call sites
    /// spell them that way and renaming them would be churn rather than work.
    public static let cardRadius: CGFloat = MedxRadius.card
    public static let tileRadius: CGFloat = MedxRadius.tile
    public static let hairline: CGFloat = 0.5

    public static var cardFill: Color { MedxInk.raised }
    public static var tileFill: Color { MedxInk.sunken }
    public static var fieldFill: Color { MedxInk.field }
    public static var groupedBackground: Color { MedxInk.page }
    public static var separator: Color { MedxInk.hairline }

    /// Standard content inset for full-width cards on iPhone.
    public static let gutter: CGFloat = 16
}

// MARK: - Cards

/// A content card. Opaque near-black over the pitch-black page, with a hairline for its edge
/// and a top-lit rim for its elevation.
public struct MedxCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    /// A raised card is the one card on a screen that *is* the screen's subject — a score
    /// hero, a live invite. It gets the deeper shadow so it reads as nearer the eye.
    public var raised: Bool
    /// Carries meaning through the glass: a duel card in a player's colour, a correct answer.
    public var tint: Color?

    public init(cornerRadius: CGFloat = MedxSurface.cardRadius, raised: Bool = false, tint: Color? = nil) {
        self.cornerRadius = cornerRadius
        self.raised = raised
        self.tint = tint
    }

    public func body(content: Content) -> some View {
        content.medxSurface(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            .card(raised: raised, tint: tint)
        )
    }
}

/// A secondary surface used inside a card — answer options, matrix cells, segment fills.
public struct MedxTileModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var accentColor: Color?
    public var isSelected: Bool

    public init(cornerRadius: CGFloat = MedxSurface.tileRadius, accentColor: Color? = nil, isSelected: Bool = false) {
        self.cornerRadius = cornerRadius
        self.accentColor = accentColor
        self.isSelected = isSelected
    }

    public func body(content: Content) -> some View {
        content.medxSurface(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            .tile(accent: accentColor, selected: isSelected)
        )
    }
}

public extension View {
    /// The canonical container for anything that is not chrome.
    func medxCard(cornerRadius: CGFloat = MedxSurface.cardRadius, raised: Bool = false) -> some View {
        modifier(MedxCardModifier(cornerRadius: cornerRadius, raised: raised))
    }

    /// A card that carries a hue on its border — used where the card's colour *is* the
    /// information, as in a duel row or a live invite.
    func medxCard(tint: Color, cornerRadius: CGFloat = MedxSurface.cardRadius, raised: Bool = false) -> some View {
        modifier(MedxCardModifier(cornerRadius: cornerRadius, raised: raised, tint: tint))
    }

    /// Secondary surface used *inside* a card — answer options, matrix cells, stat tiles.
    func medxTile(cornerRadius: CGFloat = MedxSurface.tileRadius, accentColor: Color? = nil, isSelected: Bool = false) -> some View {
        modifier(MedxTileModifier(cornerRadius: cornerRadius, accentColor: accentColor, isSelected: isSelected))
    }

    /// A card inside a *presented* surface — the rev/exam mode picker, the question navigator.
    /// The one content-shaped glass in the app; see `MedxSurfaceSpec.sheetCard`.
    func medxSheetCard(cornerRadius: CGFloat = MedxSurface.cardRadius, tint: Color? = nil) -> some View {
        medxSurface(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
            .sheetCard(tint: tint)
        )
    }
}

// MARK: - Bars
//
// `medxBar(topDivider:)` is gone. It backed a bar with `.bar` and drew a hairline across the
// top of the screen, and all six of its call sites were inside a sheet or a full-screen cover.
// They all use `medxFloatingBar()` now: same job, one inset capsule of glass instead of an
// opaque stripe plus a rule. The removal is most of what "declump" meant — a screen used to
// end in three stacked bands of furniture.

// MARK: - Scroll
//
// There used to be a `medxScrollReveal()` here: a `scrollTransition` that faded and lifted
// each card as it came into view. It is gone, not disabled. Content that dims and slides
// while you are trying to read it fights the scroll instead of decorating it, and none of
// Apple's own list screens do this. Scrolling is now the platform's, untouched.

// MARK: - iOS 26 chrome
//
// The Liquid Glass adoptions, each behind its own availability check and each in exactly one
// place, because the deployment target is iOS 17 and every API below is iOS 26. The fallback
// is never a stub: it is what the screen should look like on iOS 17, which is the version
// three of the four target devices were on when this was written.
//
// What is adopted here is chrome the *platform* owns — the tab bar's minimise behaviour, the
// scroll edges — plus one button style. `.glassProminent` is kept for the primary action
// because that is the control iOS 26 itself draws in glass and there is one per screen.
// `.glass` is **not** kept for secondary buttons: a screen with four glass pills on it was the
// "too much glass" this rewrite is undoing, and `.bordered` on black is a clean ink capsule.

public extension View {
    /// Lets the tab bar shrink out of the way as you scroll down a long list, which on iOS 26
    /// is what gives a five-tab app its screen back. Below 26 the bar is fixed and there is
    /// nothing to ask for.
    @ViewBuilder
    func medxTabBarMinimize() -> some View {
        if #available(iOS 26.0, *) {
            self.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }

    /// Softens a scroll view's edges so content dissolves under the bars instead of sliding
    /// under a hard line.
    ///
    /// **Gone, not disabled.** `scrollEdgeEffectStyle(.soft, for: .all)` is a live blur along all four
    /// scroll edges, recomputed every frame of every scroll, and `medxPage` applied it to all 36
    /// screens. It was the most expensive thing in the app by a distance, and on a `#000` page there is
    /// no gradient of content for it to soften — it was blurring black into black. The default hard
    /// edge is what the design wants anyway: content meets the bar and stops.
    ///
    /// Kept as a no-op only until the last `medxPage(_:intensity:)` call site loses its arguments; the
    /// body is `self` and there is no availability branch left, so nothing here can come back by
    /// accident.
    func medxScrollEdge() -> some View {
        self
    }

    /// A secondary action. Flat on every OS version — see the note above. Deliberately does
    /// **not** set a border shape: the call sites that want a capsule already say so, and
    /// imposing one here would re-shape a dozen buttons that are meant to be the system's
    /// default rounded rectangle.
    func medxBorderedButton() -> some View {
        buttonStyle(.bordered)
    }

    /// The primary action on a screen — Start, Submit, Deal. One per screen, and the one
    /// control that keeps its glass.
    @ViewBuilder
    func medxFilledButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}
