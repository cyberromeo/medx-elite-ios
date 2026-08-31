import SwiftUI

// MARK: - Liquid Glass
//
// The app tried glass once before and took it back out, and the note at the top of
// `GlassModifier.swift` says why: every rectangle was wrapped in `.ultraThinMaterial` over a
// flat grey page, which is haze rather than glass — there was nothing behind it to refract.
//
// This is the second attempt, built the way iOS 26 actually wants it:
//
//   1. **Something to refract.** `MedxAurora` puts a section-hued wash behind every screen.
//      Glass over a controlled gradient is legible and looks like glass; glass over
//      `systemGroupedBackground` looks like a smudge. The backdrop comes first, always.
//   2. **One material vocabulary.** Every surface in the app goes through `medxSurface`, so
//      there is exactly one place that decides what a rectangle is made of — and exactly one
//      place that has to answer for Reduce Transparency and the iOS 17 fallback.
//   3. **Never `.interactive()` inside a `Button` label.** The effect takes the touch and the
//      button stops firing; that is what broke the flashcard close button. Interactive glass
//      comes from `.buttonStyle(.glass)` / `.glassProminent`, which the system wires up
//      itself — see `medxBorderedButton()` and `medxFilledButton()`.
//   4. **Glass cannot sample glass.** Anything sitting near other glass shares a
//      `MedxGlassGroup`, which is `GlassEffectContainer` where there is one.
//
// Every iOS 26 API below sits behind `#available`; the deployment target is still 17.0 and
// the fallback is the flat surface the app shipped with, not a stub.

public enum MedxGlass {
    /// Corner radii. Rounder than the old flat set — iOS 26's own geometry is, and a tight
    /// radius makes a glass edge read as a sticker instead of a lens.
    public static let cardRadius: CGFloat = 22
    public static let tileRadius: CGFloat = 16
    public static let hudRadius: CGFloat = 24

    /// How close two glass shapes have to be before they should flow into each other.
    /// `GlassEffectContainer`'s spacing, and the gap the HUD and the action bar are built on.
    public static let groupSpacing: CGFloat = 20

    /// Inset of a floating bar from the screen edge. A bar that touches the edge is chrome;
    /// one that floats is glass.
    public static let floatInset: CGFloat = 14
}

// MARK: - Surface spec

/// What one rectangle in the app is made of.
///
/// Deliberately a value rather than a pile of modifier arguments: `medxCard`, `medxTile`,
/// every pill, chip, HUD and action bar builds one of these, so "what does a selected answer
/// look like" is answered in a single place and cannot drift between screens.
public struct MedxSurfaceSpec {
    /// Tints the glass, and the fallback's fill, with meaning — a chosen option, a correct
    /// answer, a section's own hue.
    public var tint: Color?
    /// `.clear` glass, for chrome floating over artwork rather than over a page.
    public var clear: Bool
    /// What the surface becomes on iOS 17, and under Reduce Transparency.
    public var fallbackFill: Color
    /// Hairline border. `nil` takes the system separator.
    public var strokeHue: Color?
    public var strokeOpacity: Double
    public var strokeWidth: CGFloat
    /// The top-lit hairline that makes an edge read as a bevel rather than as a cut. This is
    /// what carries the glass look down to iOS 17, where there is no real glass to be had.
    public var showsRim: Bool
    public var shadowOpacity: Double
    public var shadowRadius: CGFloat
    public var shadowY: CGFloat

    public init(
        tint: Color? = nil,
        clear: Bool = false,
        fallbackFill: Color = MedxSurface.cardFill,
        strokeHue: Color? = nil,
        strokeOpacity: Double = 0.20,
        strokeWidth: CGFloat = 0.5,
        showsRim: Bool = true,
        shadowOpacity: Double = 0,
        shadowRadius: CGFloat = 0,
        shadowY: CGFloat = 0
    ) {
        self.tint = tint
        self.clear = clear
        self.fallbackFill = fallbackFill
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
    /// A content card. `raised` lifts it off the page with a soft shadow — used for the one
    /// card on a screen that is the screen's subject.
    static func card(raised: Bool = false, tint: Color? = nil) -> MedxSurfaceSpec {
        MedxSurfaceSpec(
            tint: tint,
            fallbackFill: MedxSurface.cardFill,
            strokeHue: tint,
            strokeOpacity: tint == nil ? 0.20 : 0.45,
            showsRim: true,
            shadowOpacity: raised ? 0.10 : 0.04,
            shadowRadius: raised ? 14 : 6,
            shadowY: raised ? 6 : 2
        )
    }

    /// A secondary surface *inside* a card — answer options, matrix cells, stat tiles.
    static func tile(accent: Color? = nil, selected: Bool = false) -> MedxSurfaceSpec {
        let hue = selected ? (accent ?? MedxTheme.accent) : nil
        return MedxSurfaceSpec(
            tint: hue,
            fallbackFill: selected
                ? (accent ?? MedxTheme.accent).opacity(0.12)
                : MedxSurface.tileFill,
            strokeHue: hue,
            strokeOpacity: selected ? 0.70 : 0.16,
            strokeWidth: selected ? 1.4 : 0.5,
            showsRim: true
        )
    }

    /// Chrome that floats over scrolling content: the runner's HUD, a bottom action bar, a
    /// media overlay. Lifted, because the shadow is what says it is above the page.
    static var hud: MedxSurfaceSpec {
        MedxSurfaceSpec(
            fallbackFill: Color(uiColor: .secondarySystemBackground),
            strokeOpacity: 0.16,
            showsRim: true,
            shadowOpacity: 0.16,
            shadowRadius: 18,
            shadowY: 8
        )
    }

    /// A capsule carrying a hue: a bank tag, a section length, a timer.
    static func pill(_ hue: Color, solid: Bool = false) -> MedxSurfaceSpec {
        MedxSurfaceSpec(
            tint: solid ? nil : hue,
            fallbackFill: solid ? hue : hue.opacity(0.16),
            strokeHue: hue,
            strokeOpacity: solid ? 0 : 0.35,
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
        // Reduce Transparency is the accessible escape hatch, and it lands on exactly the
        // same flat surface iOS 17 gets — so there is one fallback to maintain, not two.
        if #available(iOS 26.0, *), !reduceTransparency {
            content
                .glassEffect(glassStyle, in: shape)
                .overlay { edge }
                .shadow(
                    color: Color.black.opacity(spec.shadowOpacity),
                    radius: spec.shadowRadius,
                    y: spec.shadowY
                )
        } else {
            content
                .background(shape.fill(spec.fallbackFill))
                .overlay { edge }
                .shadow(
                    color: Color.black.opacity(spec.shadowOpacity),
                    radius: spec.shadowRadius,
                    y: spec.shadowY
                )
        }
    }

    /// Built inside its own availability island: `Glass` does not exist on iOS 17, so it
    /// cannot be a stored property or a parameter — only a value made here and used there.
    @available(iOS 26.0, *)
    private var glassStyle: Glass {
        var value: Glass = spec.clear ? .clear : .regular
        if let tint = spec.tint {
            value = value.tint(tint.opacity(0.42))
        }
        return value
    }

    /// Hairline plus specular rim, in one overlay that never takes a touch.
    private var edge: some View {
        ZStack {
            shape.strokeBorder(
                (spec.strokeHue ?? MedxSurface.separator).opacity(spec.strokeOpacity),
                lineWidth: spec.strokeWidth
            )

            if spec.showsRim {
                shape.strokeBorder(rim, lineWidth: 0.9)
            }
        }
        .allowsHitTesting(false)
    }

    /// Light comes from the top of the screen, so the bevel is bright at the top edge and
    /// gone by the bottom. Weaker in Dark Mode, where a white rim at full strength reads as
    /// a drawn outline instead of a highlight.
    private var rim: LinearGradient {
        let top = scheme == .dark ? 0.26 : 0.62
        let middle = scheme == .dark ? 0.05 : 0.14
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
    /// cross-fading — the Next button becoming Finish, the timer growing as it runs out.
    @ViewBuilder
    func medxGlassID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
    }

    /// Extends and blurs artwork out under the bars instead of letting it stop at a hard
    /// line. Used on the few screens that have a hero image worth bleeding.
    @ViewBuilder
    func medxBackgroundExtension() -> some View {
        if #available(iOS 26.0, *) {
            self.backgroundExtensionEffect()
        } else {
            self
        }
    }
}

// MARK: - Floating bar

public extension View {
    /// A bar that floats: inset from the screen edges, fully rounded, its own glass, its own
    /// shadow. This replaces the old edge-to-edge `.bar` for the runner and every other
    /// bottom action bar, because a capsule of glass over the page is what iOS 26 does and an
    /// opaque stripe pinned to the bottom is what iOS 13 did.
    func medxFloatingBar(cornerRadius: CGFloat = 26) -> some View {
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

    /// A round glass button surface — close, bookmark, overflow. Not a `ButtonStyle`: the
    /// caller owns the `Button`, and the glass has to sit on the *label* so the tap lands on
    /// the button rather than on the effect.
    func medxGlassCircle(diameter: CGFloat = 38, tint: Color? = nil) -> some View {
        self
            .frame(width: diameter, height: diameter)
            .medxSurface(
                Circle(),
                MedxSurfaceSpec(
                    tint: tint,
                    fallbackFill: tint?.opacity(0.18) ?? MedxSurface.fieldFill,
                    strokeHue: tint,
                    strokeOpacity: tint == nil ? 0.18 : 0.45
                )
            )
            .contentShape(Circle())
    }

    /// A glass capsule around a label — the timer, a counter, a status pill in chrome.
    func medxGlassCapsule(tint: Color? = nil, horizontal: CGFloat = 12, vertical: CGFloat = 7) -> some View {
        self
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .medxSurface(
                Capsule(style: .continuous),
                MedxSurfaceSpec(
                    tint: tint,
                    fallbackFill: tint?.opacity(0.16) ?? MedxSurface.fieldFill,
                    strokeHue: tint,
                    strokeOpacity: tint == nil ? 0.16 : 0.40
                )
            )
    }
}
