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

// MARK: - Section header

/// A heading for a group of cards inside a scroll view.
///
/// `.headline`, not `.title3`: every screen that uses one now also has the platform's *large*
/// navigation title above it, and two competing bold headings on one screen is the clutter this
/// rewrite is removing. One step down puts it clearly under the page title, which is what
/// Fitness and Health do with theirs.
public struct MedxSectionHeader<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let trailing: Trailing

    public init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            trailing
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

public extension MedxSectionHeader where Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil) {
        self.init(title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Metrics

/// A single figure in a stats row. Quiet by default: the glyph carries the colour,
/// the tile stays neutral so a row of them does not read as five different alerts.
public struct MedxMetric: View {
    public let icon: String
    public let value: String
    public let label: String
    public let color: Color

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(icon: String, value: String, label: String, color: Color) {
        self.icon = icon
        self.value = value
        self.label = label
        self.color = color
    }

    public var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(color)
                    Text(value)
                        .font(.body.monospacedDigit().weight(.semibold))
                        .contentTransition(.numericText())
                    Text(label.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Image(systemName: icon)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(color)

                    Text(value)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        // Rolls rather than cuts when a refresh lands a new figure. Monospaced
                        // digits are what make it a roll instead of a reflow.
                        .contentTransition(.numericText())

                    Text(label.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medxTile()
        .animation(.easeOut(duration: 0.28), value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

public struct MedxMetricsRow<Content: View>: View {
    private let content: Content

    @Environment(\.dynamicTypeSize) private var typeSize

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    /// Branched on the type size rather than wrapped in `ViewThatFits`.
    ///
    /// `ViewThatFits` builds *every* candidate in order to measure it and then throws all but one
    /// away, on every layout pass. Two candidates each holding three `MedxMetric`s is six metric
    /// subtrees built to show three. The condition here is the same one `MedxMetric` already branches
    /// on internally, so the two now agree instead of one measuring what the other decided.
    public var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                content
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                content
            }
        }
    }
}

// MARK: - Small controls

/// Circular icon button with a 44pt hit target — close, bookmark, overflow.
public struct MedxCircleButton: View {
    public let icon: String
    public var tint: Color?
    public var filled: Bool
    public let accessibilityLabel: String
    public var accessibilityValue: String?
    public let action: () -> Void

    public init(
        icon: String,
        tint: Color? = nil,
        filled: Bool = false,
        accessibilityLabel: String,
        accessibilityValue: String? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.tint = tint
        self.filled = filled
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(filled ? MedxCandy.onSolid : (tint ?? Color.primary))
                // Ink, not glass. This button appears on twenty screens; glass belongs to the
                // runner and to presented surfaces, and a translucent 34pt circle on a card
                // was one of the panes that made the last pass read as haze.
                .medxInkCircle(diameter: 34, tint: filled ? (tint ?? MedxTheme.accent) : nil)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(BouncyButtonStyle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue ?? "")
    }
}

/// Compact status chip. One weight, one shape, everywhere.
public struct MedxChip: View {
    public let text: String
    public var icon: String?
    public var tint: Color

    public init(_ text: String, icon: String? = nil, tint: Color = .secondary) {
        self.text = text
        self.icon = icon
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tint)
        .medxInkCapsule(tint: tint, horizontal: 9, vertical: 4)
        .accessibilityElement(children: .combine)
    }
}

/// Trailing disclosure glyph matching the system's grouped-list chevron.
public struct MedxDisclosure: View {
    public init() {}

    public var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}
