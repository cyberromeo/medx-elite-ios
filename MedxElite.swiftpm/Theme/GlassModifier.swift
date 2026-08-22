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
    public static let cardRadius: CGFloat = 16
    public static let tileRadius: CGFloat = 12
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
        let accent = accentColor ?? Color.accentColor

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
                .foregroundStyle(filled ? Color.white : (tint ?? Color.primary))
                .frame(width: 32, height: 32)
                .background {
                    Circle().fill(filled ? (tint ?? Color.accentColor) : MedxSurface.fieldFill)
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
