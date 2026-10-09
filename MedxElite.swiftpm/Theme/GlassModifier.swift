import SwiftUI

// MARK: - Surface System (Apple HIG)
//
// The app used to wrap almost every rectangle in Liquid Glass, which on iOS 26 turned
// content into frosted soup and cost a blur pass per card. The rule now is the one
// Apple actually uses in its own apps:
//
//   * Content sits on flat, semantic, grouped backgrounds.
//   * Glass / materials are reserved for chrome that genuinely floats over content
//     (nav bars, bottom action bars, media overlays).
//   * Never put an `interactive()` glass effect inside a `Button` label — the effect
//     takes the touch and the button stops firing.
//
// The old modifier names are kept as thin aliases so every existing call site keeps
// working while rendering the new, quieter surface.

public enum MedxSurface {
    /// Corner radii. Matched to the system's own grouped-list and widget geometry.
    /// iOS 26 rounded every grouped surface up — Settings' cells, widgets, sheets — and a 16 pt
    /// card next to the system's own now reads as a different app. 22 / 14 sit with them.
    public static let cardRadius: CGFloat = 22
    public static let tileRadius: CGFloat = 14
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

/// A flat content card: grouped fill, hairline border, no tint, no glow.
public struct MedxCardModifier: ViewModifier {
    public var cornerRadius: CGFloat
    /// A raised card gets a soft neutral shadow; the default sits flush on the page.
    public var raised: Bool

    public init(cornerRadius: CGFloat = MedxSurface.cardRadius, raised: Bool = false) {
        self.cornerRadius = cornerRadius
        self.raised = raised
    }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .environment(\.medxInsideCard, true)
            .background(shape.fill(MedxSurface.cardFill))
            .overlay(
                shape.strokeBorder(
                    MedxSurface.separator.opacity(raised ? 0.20 : 0.28),
                    lineWidth: MedxSurface.hairline
                )
            )
            .shadow(
                color: Color.black.opacity(raised ? 0.06 : 0),
                radius: raised ? 8 : 0,
                y: raised ? 3 : 0
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
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let accent = accentColor ?? MedxTheme.accent

        content
            .background(shape.fill(isSelected ? accent.opacity(0.12) : MedxSurface.tileFill))
            .overlay(
                shape.strokeBorder(
                    isSelected ? accent.opacity(0.75) : MedxSurface.separator.opacity(0.30),
                    lineWidth: isSelected ? 1.5 : MedxSurface.hairline
                )
            )
    }
}

public extension View {
    /// Flat content card. The canonical container for anything that is not chrome.
    func medxCard(cornerRadius: CGFloat = MedxSurface.cardRadius, raised: Bool = false) -> some View {
        modifier(MedxCardModifier(cornerRadius: cornerRadius, raised: raised))
    }

    /// Secondary surface used *inside* a card — answer options, matrix cells, stat tiles.
    func medxTile(cornerRadius: CGFloat = MedxSurface.tileRadius, accentColor: Color? = nil, isSelected: Bool = false) -> some View {
        modifier(MedxTileModifier(cornerRadius: cornerRadius, accentColor: accentColor, isSelected: isSelected))
    }

    /// A card inside a `List`, drawn exactly as it is inside a `VStack`.
    ///
    /// The three video screens are `List`s rather than `LazyVStack`s for one reason: `swipeActions`
    /// is a `List` feature and nothing else provides it — swipe a class left to save it offline,
    /// right to play it. That is worth having, and it should cost nothing visually, so the system
    /// cell gives up its own background, its separator and its insets, and the card the row was
    /// already drawing for itself becomes the only thing you see. Cell reuse comes along for free,
    /// which on 2,900 VOD rows is the difference that matters.
    func medxCardRow(vertical: CGFloat = 7) -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(
                EdgeInsets(
                    top: vertical,
                    leading: MedxSurface.gutter,
                    bottom: vertical,
                    trailing: MedxSurface.gutter
                )
            )
    }

    /// Bar-style chrome that floats over scrolling content: bottom action bars, toolbars.
    ///
    /// This is the only place in the app that uses a material. `.bar` is what a real
    /// `UIToolbar` uses, and as a `ShapeStyle` background it extends into the safe area on
    /// its own — so the bar reaches the bottom edge instead of leaving a stripe of page
    /// above the home indicator.
    func medxBar(topDivider: Bool = false) -> some View {
        self
            .background(.bar)
            .overlay(alignment: .top) {
                if topDivider {
                    Rectangle()
                        .fill(MedxSurface.separator.opacity(0.5))
                        .frame(height: MedxSurface.hairline)
                }
            }
    }

    /// Everything a card `List` sets, so it reads as the same page a `ScrollView` screen does:
    /// plain rows, no system grouped background, the app's own underneath. Pair with `medxCardRow()`.
    func medxCardList(_ section: MedxSection? = nil) -> some View {
        self
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background {
                if let section {
                    MedxBackdrop(section: section)
                } else {
                    MedxSurface.groupedBackground.ignoresSafeArea()
                }
            }
            .medxScrollEdge()
            .scrollIndicators(.automatic)
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
                    .font(.title3.weight(.bold))
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
    @Environment(\.colorScheme) private var scheme
    @Environment(\.medxInsideCard) private var nested

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
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(color.medxInk(in: scheme))
                        .frame(width: 24, height: 24)
                        .background(color.gradient, in: Circle())

                    Text(value)
                        .font(.system(nested ? .title3 : .title2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text(label.capitalized)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, nested ? 10 : 13)
        .padding(.vertical, nested ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(MedxMetricSurface(nested: nested))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

/// A metric on the page is a small card of its own; inside a card it drops to a tile, so a summary
/// card does not grow a second border around each figure.
private struct MedxMetricSurface: ViewModifier {
    let nested: Bool

    func body(content: Content) -> some View {
        if nested {
            content.medxTile()
        } else {
            content.medxCard(cornerRadius: 18)
        }
    }
}

private struct MedxInsideCardKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Set by `medxCard()` on everything it wraps.
    var medxInsideCard: Bool {
        get { self[MedxInsideCardKey.self] }
        set { self[MedxInsideCardKey.self] = newValue }
    }
}

public struct MedxMetricsRow<Content: View>: View {
    private let content: Content

    @Environment(\.dynamicTypeSize) private var typeSize

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    /// Side by side at every ordinary text size — each figure's label wraps to a second line
    /// rather than the row giving up and stacking three full-width tiles. At an accessibility
    /// size the figures stack, which is where `MedxMetric` switches to its one-line form anyway.
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
                .foregroundStyle(filled ? Color.white : (tint ?? Color.primary))
                .frame(width: 32, height: 32)
                .background {
                    Circle().fill(filled ? (tint ?? MedxTheme.accent) : MedxSurface.fieldFill)
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
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
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14), in: Capsule())
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


// MARK: - Loading placeholder

/// What a list screen shows while its first fetch is in flight: the shape of the page it is about
/// to become — a header block and a run of card rows — breathing gently, instead of a spinner in
/// the middle of an empty screen. The pulse animates opacity only, and stops under Reduce Motion.
public struct MedxSkeleton: View {
    private let rows: Int
    private let label: String
    private let showsHeader: Bool

    @State private var dimmed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ label: String, rows: Int = 7, showsHeader: Bool = true) {
        self.label = label
        self.rows = rows
        self.showsHeader = showsHeader
    }

    private var fill: Color { Color(uiColor: .tertiarySystemFill) }
    private let titleWidths: [CGFloat] = [150, 190, 120, 170, 140, 200, 130]
    private let detailWidths: [CGFloat] = [90, 120, 70, 110, 100, 80, 115]

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if showsHeader {
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(fill)
                            .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 8) {
                            Capsule().fill(fill).frame(width: 90, height: 9)
                            Capsule().fill(fill).frame(height: 11)
                            Capsule().fill(fill).frame(width: 180, height: 11)
                        }
                    }
                    .padding(.bottom, 6)

                    HStack(spacing: 10) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(MedxSurface.cardFill)
                                .frame(height: 84)
                        }
                    }
                }

                ForEach(0..<rows, id: \.self) { index in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(fill)
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 8) {
                            Capsule().fill(fill)
                                .frame(width: titleWidths[index % titleWidths.count], height: 11)
                            Capsule().fill(fill.opacity(0.7))
                                .frame(width: detailWidths[index % detailWidths.count], height: 9)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .medxCard()
                }
            }
            .padding(.horizontal, MedxSurface.gutter)
            .padding(.top, 8)
        }
        .scrollDisabled(true)
        .opacity(dimmed ? 0.5 : 1)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
            value: dimmed
        )
        .onAppear { dimmed = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}
