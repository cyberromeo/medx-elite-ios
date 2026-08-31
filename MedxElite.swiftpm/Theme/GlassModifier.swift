import SwiftUI

// MARK: - Surface System
//
// The app's first pass at Liquid Glass wrapped every rectangle in `.ultraThinMaterial` over a
// flat grey page and got frosted soup: nothing behind the panels to refract, a blur pass per
// card, and text sitting on haze. It was taken back out and the app went flat.
//
// It is glass again now, but built the other way round — see `Theme/MedxLiquidGlass.swift`
// for the four rules, of which the first is the one that was missing: **the backdrop comes
// first**. `MedxAurora` washes each page in the hue that destination already owns, so a glass
// card has something to bend, and the same card looks lime-lit on the QBank and warm on Tests
// without a line of per-screen styling.
//
// What survives from the flat era, unchanged, is the discipline:
//
//   * One place decides what a rectangle is made of — `medxSurface`, which also owns the
//     iOS 17 fallback and the Reduce Transparency escape hatch.
//   * Never put an `interactive()` glass effect inside a `Button` label. The effect takes the
//     touch and the button stops firing; that is what broke the flashcard close button.
//     Interactive glass comes from `.buttonStyle(.glass)`, which the system wires up itself.
//   * Glass near glass shares a `MedxGlassGroup`, because glass cannot sample glass.
//
// Every call site of `medxCard` / `medxTile` / `medxBar` in the app — 75 of them — is
// unchanged and simply renders the new material.

public enum MedxSurface {
    /// Corner radii. Rounder than the flat set they replace: iOS 26's own geometry is, and a
    /// tight radius makes a glass edge read as a sticker rather than as a lens.
    public static let cardRadius: CGFloat = MedxGlass.cardRadius
    public static let tileRadius: CGFloat = MedxGlass.tileRadius
    public static let hairline: CGFloat = 0.5

    public static var cardFill: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    public static var tileFill: Color { Color(uiColor: .tertiarySystemGroupedBackground) }
    public static var fieldFill: Color { Color(uiColor: .tertiarySystemFill) }
    public static var groupedBackground: Color { Color(uiColor: .systemGroupedBackground) }
    public static var separator: Color { Color(uiColor: .separator) }

    /// Standard content inset for full-width cards on iPhone.
    public static let gutter: CGFloat = 16
}

// MARK: - Cards

/// A content card. Glass on iOS 26 over the page's own wash, the flat grouped fill below it.
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

    /// A card that carries a hue through its glass — used where the card's colour *is* the
    /// information, as in a duel row or a live invite.
    func medxCard(tint: Color, cornerRadius: CGFloat = MedxSurface.cardRadius, raised: Bool = false) -> some View {
        modifier(MedxCardModifier(cornerRadius: cornerRadius, raised: raised, tint: tint))
    }

    /// Secondary surface used *inside* a card — answer options, matrix cells, stat tiles.
    func medxTile(cornerRadius: CGFloat = MedxSurface.tileRadius, accentColor: Color? = nil, isSelected: Bool = false) -> some View {
        modifier(MedxTileModifier(cornerRadius: cornerRadius, accentColor: accentColor, isSelected: isSelected))
    }

    /// Bar-style chrome pinned to an edge: bottom action bars on the screens that want a
    /// full-width one rather than the floating capsule (`medxFloatingBar`).
    ///
    /// `.bar` is what a real `UIToolbar` uses and, as a `ShapeStyle` background, it extends
    /// into the safe area on its own — so the bar reaches the bottom edge instead of leaving a
    /// stripe of page above the home indicator. On iOS 26 the system renders that material as
    /// glass already; what is added here is the specular top rim, so the bar has an edge
    /// instead of a seam.
    func medxBar(topDivider: Bool = false) -> some View {
        self
            .background(.bar)
            .overlay(alignment: .top) {
                if topDivider {
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 1)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(MedxSurface.separator.opacity(0.45))
                            .frame(height: MedxSurface.hairline)
                    }
                    .allowsHitTesting(false)
                }
            }
    }
}

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
// The rule from the top of this file still holds — glass goes on chrome that floats over
// content, never on content — so what is adopted here is the tab bar's own behaviour, the
// scroll edges, and button styles. Cards stay flat.

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
    @ViewBuilder
    func medxScrollEdge() -> some View {
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
    }

    /// A secondary action. Deliberately does **not** set a border shape: the call sites that
    /// want a capsule already say so, and imposing one here would re-shape a dozen buttons
    /// that are meant to be the system's default rounded rectangle.
    @ViewBuilder
    func medxBorderedButton() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// The primary action on a screen — Start, Submit, Deal.
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

/// `Text` in the system's grouped-list header voice, for use above cards in a ScrollView.
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
                    .font(.title3.weight(.semibold))
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

public struct MedxMetricsRow<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 10) {
                content
            }

            VStack(spacing: 8) {
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
                .medxGlassCircle(diameter: 34, tint: filled ? (tint ?? MedxTheme.accent) : tint)
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
        .medxGlassCapsule(tint: tint, horizontal: 9, vertical: 4)
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
