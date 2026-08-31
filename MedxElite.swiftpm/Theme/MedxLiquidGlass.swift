import SwiftUI

// MARK: - Liquid Glass
//
// Glass has been in and out of this app twice, and both failures were the same mistake made
// from opposite ends. The first pass wrapped every rectangle in `.ultraThinMaterial` over a
// flat grey page: nothing behind it to refract, so it came out as haze. The second pass built
// a proper section-hued backdrop and then put glass on *everything* — cards, tiles, pills,
// chips, badges, segments — so a single screen was thirty translucent panes sampling each
// other. Also haze, and a blur pass per pane.
//
// The third answer is a rule about *place* rather than about technique:
//
//   **Content is ink. Chrome is glass. Glass floats.**
//
// Ink lives in `Theme/MedxInk.swift` — opaque, no blur, identical on iOS 17 and 26. Glass is
// allowed in exactly three places, and a `glassEffect` anywhere else is a bug:
//
//   1. `RunnerHUD` — the panel over the question.
//   2. `RunnerActionBar` — Back · Skip · Next, three panes over the question.
//   3. Anything *presented*: the rev/exam mode cards, the question navigator, the section
//      handover, and a `medxFloatingBar()` at the bottom of a sheet.
//
// What all three have in common is that they float over content that is *already there* — so
// there is something real to refract, which is the only condition under which glass reads as
// glass. A card in a scroll view has the page behind it and nothing else.
//
// Two rules survive from the previous pass unchanged, because both were learned the hard way:
//
//   * **Never `.interactive()` glass inside a `Button` label.** The effect takes the touch and
//     the button stops firing; that is what broke the flashcard close button. Interactive glass
//     comes from `.buttonStyle(.glass)` / `.glassProminent`, which the system wires up itself.
//   * **Glass cannot sample glass.** Neighbours share a `MedxGlassGroup`, and a chip of glass
//     never goes on a panel of glass — which is why the HUD's clock and ✕ are bare glyphs.
//
// Every iOS 26 API below sits behind `#available`; the deployment target is still 17.0.

public enum MedxGlass {
    /// Radii forward to `MedxRadius`, so "no sharp ends" is one file's decision.
    public static let cardRadius: CGFloat = MedxRadius.card
    public static let tileRadius: CGFloat = MedxRadius.tile
    public static let hudRadius: CGFloat = MedxRadius.hud

    /// How close two glass shapes have to be before they should flow into each other.
    /// `GlassEffectContainer`'s spacing, and the gap the runner's action bar is built on.
    public static let groupSpacing: CGFloat = 20

    /// Inset of a floating bar from the screen edge. A bar that touches the edge is chrome;
    /// one that floats is glass.
    public static let floatInset: CGFloat = 14
}

// MARK: - Surface spec

/// What a rectangle is made of.
///
/// Two materials and nothing else. `ink` is the app; `glass` is the three floating places named at
/// the top of this file. Both paint `MedxSurfaceSpec.fill` — `ink` as the surface itself, `glass` as
/// what it becomes on iOS 17 and under Reduce Transparency — so there is one colour per spec rather
/// than one for each material to drift apart.
public enum MedxMaterial {
    /// An opaque fill. Identical on every OS version, no blur pass, and what every card, tile,
    /// pill and badge in the app is.
    case ink
    /// `glassEffect` on iOS 26, falling back to `ink` below it. `clear` is for chrome floating over
    /// artwork rather than over a page.
    case glass(clear: Bool)
}

/// What one rectangle in the app is made of.
///
/// Deliberately a value rather than a pile of modifier arguments: `medxCard`, `medxTile`,
/// every pill, chip, HUD and action bar builds one of these, so "what does a selected answer
/// look like" is answered in a single place and cannot drift between screens.
public struct MedxSurfaceSpec {
    public var material: MedxMaterial
    /// The opaque fill. What `ink` paints, and what `glass` falls back to on iOS 17 and under
    /// Reduce Transparency.
    public var fill: Color
    /// Tints glass with meaning — a low clock, a chosen option. Ignored by `ink`, which carries
    /// meaning in `fill` and in its border instead.
    public var tint: Color?
    /// Hairline border. `nil` takes `MedxInk.hairline` at full strength.
    public var strokeHue: Color?
    public var strokeOpacity: Double
    public var strokeWidth: CGFloat
    /// The top-lit hairline that makes an edge read as a bevel rather than as a cut. On a black
    /// page this is the *only* thing that can say "nearer the eye" — a drop shadow on `#000`
    /// is invisible.
    public var showsRim: Bool
    public var shadowOpacity: Double
    public var shadowRadius: CGFloat
    public var shadowY: CGFloat

    public init(
        material: MedxMaterial = .ink,
        fill: Color = MedxInk.raised,
        tint: Color? = nil,
        strokeHue: Color? = nil,
        strokeOpacity: Double = 1,
        strokeWidth: CGFloat = 0.5,
        showsRim: Bool = true,
        shadowOpacity: Double = 0,
        shadowRadius: CGFloat = 0,
        shadowY: CGFloat = 0
    ) {
        self.material = material
        self.fill = fill
        self.tint = tint
        self.strokeHue = strokeHue
        self.strokeOpacity = strokeOpacity
        self.strokeWidth = strokeWidth
        self.showsRim = showsRim
        self.shadowOpacity = shadowOpacity
        self.shadowRadius = shadowRadius
        self.shadowY = shadowY
    }
}

public extension MedxSurfaceSpec {
    /// A content card. Ink, always — a card is content and content does not refract.
    ///
    /// `raised` used to mean a deeper shadow. On a black page a shadow is invisible, so it now
    /// means a brighter rim: the card catches more light at its top edge, which is what reads
    /// as nearer the eye.
    static func card(raised: Bool = false, tint: Color? = nil) -> MedxSurfaceSpec {
        MedxSurfaceSpec(
            fill: MedxInk.raised,
            strokeHue: tint,
            strokeOpacity: 0.45,
            strokeWidth: tint == nil ? 0.5 : 1,
            showsRim: true,
            // Kept for the light appearance, where a page *is* lighter than its cards and a
            // shadow still does something. Zero on black by virtue of being unseeable there.
            shadowOpacity: raised ? 0.10 : 0.04,
            shadowRadius: raised ? 14 : 6,
            shadowY: raised ? 6 : 2
        )
    }

    /// A secondary surface *inside* a card — answer options, matrix cells, stat tiles.
    ///
    /// Selection is carried by a real border and a hue wash rather than by tinted glass: a
    /// chosen answer has to be unmistakable at a glance, and a translucent pane cannot be
    /// relied on to out-shout the four rows around it.
    static func tile(accent: Color? = nil, selected: Bool = false) -> MedxSurfaceSpec {
        let hue = accent ?? MedxTheme.accent
        return MedxSurfaceSpec(
            fill: selected ? hue.opacity(0.14) : MedxInk.sunken,
            strokeHue: selected ? hue : nil,
            strokeOpacity: 0.75,
            strokeWidth: selected ? 1.5 : 0.5,
            showsRim: !selected
        )
    }

    /// Chrome that floats over scrolling content: the runner's HUD, a bottom action bar, a
    /// media overlay. **Glass** — there is real content underneath it to refract.
    static var hud: MedxSurfaceSpec {
        MedxSurfaceSpec(
            material: .glass(clear: false),
            fill: MedxInk.raised,
            strokeOpacity: 0.45,
            showsRim: true,
            shadowOpacity: 0.16,
            shadowRadius: 18,
            shadowY: 8
        )
    }

    /// A card inside a *presented* surface — the rev/exam mode picker, the question navigator.
    ///
    /// The one place a content-shaped rectangle is allowed to be glass, and it earns it: a
    /// sheet floats over the screen it was raised from, so there is a real page behind these
    /// to bend rather than the flat backdrop a scroll view would offer.
    static func sheetCard(tint: Color? = nil) -> MedxSurfaceSpec {
        MedxSurfaceSpec(
            material: .glass(clear: false),
            fill: MedxInk.raised,
            tint: tint,
            strokeHue: tint,
            strokeOpacity: 0.45,
            strokeWidth: tint == nil ? 0.5 : 1,
            showsRim: true,
            shadowOpacity: 0.14,
            shadowRadius: 16,
            shadowY: 7
        )
    }

    /// A capsule carrying a hue: a bank tag, a section length, a count.
    static func pill(_ hue: Color, solid: Bool = false) -> MedxSurfaceSpec {
        MedxSurfaceSpec(
            fill: solid ? hue : hue.opacity(0.18),
            strokeHue: solid ? nil : hue,
            strokeOpacity: 0.32,
            showsRim: !solid
        )
    }
}

// MARK: - The one surface modifier

public extension View {
    /// The app's only material decision. Everything that draws a filled rectangle goes
    /// through here, so glass, the iOS 17 fallback and Reduce Transparency are handled once.
    func medxSurface<S: InsettableShape>(
        _ shape: S,
        _ spec: MedxSurfaceSpec = .card()
    ) -> some View {
        modifier(MedxSurfaceModifier(shape: shape, spec: spec))
    }
}

public struct MedxSurfaceModifier<S: InsettableShape>: ViewModifier {
    public let shape: S
    public let spec: MedxSurfaceSpec

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme

    public init(shape: S, spec: MedxSurfaceSpec) {
        self.shape = shape
        self.spec = spec
    }

    @ViewBuilder
    public func body(content: Content) -> some View {
        switch spec.material {
        case .ink:
            inked(content)

        case .glass(let clear):
            // Reduce Transparency is the accessible escape hatch, and it lands on exactly the
            // same opaque surface iOS 17 gets — so there is one fallback to maintain, not two.
            //
            // The `glassEffect` call is inline rather than in an `@available` helper on purpose:
            // `.agents/availability_audit.py` stands in for the compiler on this machine, and it
            // only recognises an `if #available` block as a guard.
            if #available(iOS 26.0, *), !reduceTransparency {
                content
                    .glassEffect(glassStyle(clear: clear), in: shape)
                    .overlay { edge }
                    .shadow(
                        color: Color.black.opacity(spec.shadowOpacity),
                        radius: spec.shadowRadius,
                        y: spec.shadowY
                    )
            } else {
                inked(content)
            }
        }
    }

    private func inked(_ content: Content) -> some View {
        content
            .background(shape.fill(spec.fill))
            .overlay { edge }
            .shadow(
                color: Color.black.opacity(spec.shadowOpacity),
                radius: spec.shadowRadius,
                y: spec.shadowY
            )
    }

    /// Built inside its own availability island: `Glass` does not exist on iOS 17, so it
    /// cannot be a stored property or a parameter — only a value made here and used there.
    @available(iOS 26.0, *)
    private func glassStyle(clear: Bool) -> Glass {
        var value: Glass = clear ? .clear : .regular
        if let tint = spec.tint {
            value = value.tint(tint.opacity(0.42))
        }
        return value
    }

    /// Hairline plus specular rim, in one overlay that never takes a touch.
    ///
    /// `strokeOpacity` applies to `strokeHue`. With no hue the edge is `MedxInk.hairline` at
    /// full strength — that token carries its own alpha, tuned for a black page, and dimming
    /// it further would erase the only line separating a card from the void behind it.
    private var edge: some View {
        ZStack {
            if let hue = spec.strokeHue {
                shape.strokeBorder(hue.opacity(spec.strokeOpacity), lineWidth: spec.strokeWidth)
            } else {
                shape.strokeBorder(MedxInk.hairline, lineWidth: spec.strokeWidth)
            }

            if spec.showsRim {
                shape.strokeBorder(rim, lineWidth: 0.9)
            }
        }
        .allowsHitTesting(false)
    }

    /// Light comes from the top of the screen, so the bevel is bright at the top edge and gone
    /// by the bottom. On black this is doing the whole job a shadow would do on grey.
    private var rim: LinearGradient {
        let top = scheme == .dark ? 0.16 : 0.75
        let middle = scheme == .dark ? 0.04 : 0.18
        return LinearGradient(
            colors: [
                Color.white.opacity(top),
                Color.white.opacity(middle),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Grouping

/// Glass cannot sample other glass, so two glass shapes near each other have to be told they
/// are neighbours — otherwise each one refracts the page independently and the pair reads as
/// two stickers rather than one control cluster.
///
/// This is `GlassEffectContainer` where there is one, and a plain pass-through below iOS 26,
/// which is exactly right: with no glass to group there is nothing to co-ordinate.
public struct MedxGlassGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(spacing: CGFloat = MedxGlass.groupSpacing, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    public var body: some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

public extension View {
    /// Names a shape inside a `MedxGlassGroup` so it morphs into its neighbours instead of
    /// cross-fading — the Next button becoming Finish, Skip flowing out of it.
    ///
    /// `RunnerActionBar` is the only caller, which is the point: it is the only place in the app
    /// with two panes of glass side by side.
    @ViewBuilder
    func medxGlassID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}

// A `medxBackgroundExtension()` wrapping `backgroundExtensionEffect()` used to live here, for
// bleeding a hero image out under the bars. Nothing ever called it, and on a pitch-black page
// there is no artwork to bleed — the pages are `#000` and the one image-led screen (the video
// player) is already full-bleed by itself.

// MARK: - Floating bar

public extension View {
    /// A bar that floats: inset from the screen edges, fully rounded, its own glass, its own
    /// shadow.
    ///
    /// This is the *only* bottom bar in the app now. The edge-to-edge `medxBar` it replaced was
    /// an opaque stripe with a hairline across the top — three bands of furniture on a phone
    /// screen — and every one of its call sites was inside a sheet or a cover, which is exactly
    /// where a pane of glass has real content behind it to refract.
    func medxFloatingBar(cornerRadius: CGFloat = MedxRadius.hud) -> some View {
        self
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .medxSurface(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                .hud
            )
            .padding(.horizontal, MedxGlass.floatInset)
            .padding(.bottom, 6)
    }
}

// MARK: - Small surfaces
//
// An ink pair and a glass one, deliberately named apart. Reaching for `medxGlassCircle`
// outside the runner is the mistake this redesign exists to undo, and a name that says which
// material it is makes that mistake visible in the diff.

public extension View {
    /// A round *ink* button surface — close, bookmark, overflow, a download control in a row.
    /// The app-wide one. Not a `ButtonStyle`: the caller owns the `Button`, and the surface has
    /// to sit on the label.
    func medxInkCircle(diameter: CGFloat = 38, tint: Color? = nil) -> some View {
        self
            .frame(width: diameter, height: diameter)
            .medxSurface(
                Circle(),
                MedxSurfaceSpec(
                    fill: tint ?? MedxInk.field,
                    strokeHue: tint,
                    strokeOpacity: 0.45
                )
            )
            .contentShape(Circle())
    }

    /// An ink capsule around a small label — a chip, a count, an inline tag.
    func medxInkCapsule(tint: Color? = nil, horizontal: CGFloat = 12, vertical: CGFloat = 7) -> some View {
        self
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .medxSurface(
                Capsule(style: .continuous),
                MedxSurfaceSpec(
                    fill: tint?.opacity(0.16) ?? MedxInk.field,
                    strokeHue: tint,
                    strokeOpacity: 0.34
                )
            )
    }

    /// A round *glass* button surface. Runner chrome only — see the list at the top of this
    /// file. The glass sits on the label rather than on the `Button` so the tap still lands.
    func medxGlassCircle(diameter: CGFloat = 38, tint: Color? = nil) -> some View {
        self
            .frame(width: diameter, height: diameter)
            .medxSurface(
                Circle(),
                MedxSurfaceSpec(
                    material: .glass(clear: false),
                    fill: tint?.opacity(0.18) ?? MedxInk.field,
                    tint: tint,
                    strokeHue: tint,
                    strokeOpacity: 0.45
                )
            )
            .contentShape(Circle())
    }
}
