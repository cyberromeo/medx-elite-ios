import SwiftUI

// MARK: - Page header
//
// The PWA's page shape — eyebrow, title, lead — rendered as a scroll header rather than as
// chrome. `navigationTitle` is still set by every screen that uses this and the display mode
// is `.inline`, so the accessibility title, the back-button label and the collapse behaviour
// all remain the platform's; this is content that happens to introduce the page.
//
// The sticker is the only thing here that is purely decorative, and it is the thing that
// makes a screen recognisable from across a room, which is the whole point of the redesign.

public struct MedxPageHeader<Trailing: View>: View {
    private let section: MedxSection
    private let eyebrow: String?
    private let title: String
    private let lead: String?
    private let sticker: String?
    private let trailing: Trailing

    @Environment(\.dynamicTypeSize) private var typeSize

    public init(
        section: MedxSection,
        eyebrow: String? = nil,
        title: String,
        lead: String? = nil,
        sticker: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.section = section
        self.eyebrow = eyebrow
        self.title = title
        self.lead = lead
        self.sticker = sticker
        self.trailing = trailing()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(eyebrow ?? section.eyebrow)
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                        .tracking(0.7)
                        .foregroundStyle(section.onSoft)

                    Text(title)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)

                // At an accessibility type size the art is the first thing that should give
                // up its room — the lead paragraph needs it more.
                if let sticker, !typeSize.isAccessibilitySize {
                    MedxSticker(sticker, size: 46, tilt: -8)
                }

                trailing
            }
            .padding(.trailing, 2)

            if let lead, !lead.isEmpty {
                Text(lead)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

public extension MedxPageHeader where Trailing == EmptyView {
    init(
        section: MedxSection,
        eyebrow: String? = nil,
        title: String,
        lead: String? = nil,
        sticker: String? = nil
    ) {
        self.init(
            section: section,
            eyebrow: eyebrow,
            title: title,
            lead: lead,
            sticker: sticker
        ) { EmptyView() }
    }
}

// MARK: - Segmented control

/// One option in a `MedxSegmented`.
public struct MedxSegment<Value: Hashable>: Identifiable {
    public let value: Value
    public let label: String
    /// Shown as a small trailing figure — "GTs 119". Omitted while the count is unknown, so
    /// the control does not flicker from `0` to the real number once the catalogue lands.
    public let count: Int?

    public var id: Value { value }

    public init(value: Value, label: String, count: Int? = nil) {
        self.value = value
        self.label = label
        self.count = count
    }
}

/// A section-tinted segmented control.
///
/// Hand-built rather than a `Picker(.segmented)` wrapper for two reasons the screens
/// actually need: the system control has no room for a count beside a label, and tinting its
/// selection means setting `UISegmentedControl.appearance().selectedSegmentTintColor`, which
/// is global mutable state — the QBank's lime would leak into every other segmented control
/// in the app, including the ones inside Settings.
///
/// It scrolls horizontally when the labels no longer fit, which is what keeps the Marrow
/// series' three groups usable at an accessibility type size.
public struct MedxSegmented<Value: Hashable>: View {
    private let section: MedxSection
    private let segments: [MedxSegment<Value>]
    @Binding private var selection: Value

    public init(
        section: MedxSection,
        segments: [MedxSegment<Value>],
        selection: Binding<Value>
    ) {
        self.section = section
        self.segments = segments
        self._selection = selection
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            row
            ScrollView(.horizontal, showsIndicators: false) { row }
        }
    }

    private var row: some View {
        HStack(spacing: 6) {
            ForEach(segments) { segment in
                let isOn = segment.value == selection
                Button {
                    guard !isOn else { return }
                    HapticManager.selection()
                    selection = segment.value
                } label: {
                    HStack(spacing: 5) {
                        Text(segment.label)
                            .font(.subheadline.weight(.semibold))
                        if let count = segment.count {
                            Text(count.formatted())
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .opacity(isOn ? 0.75 : 0.55)
                        }
                    }
                    .foregroundStyle(isOn ? section.onSoft : Color.secondary)
                    .padding(.horizontal, 13)
                    .frame(minHeight: 34)
                    .background(Capsule().fill(isOn ? section.soft : MedxSurface.fieldFill))
                    .overlay(
                        Capsule().strokeBorder(
                            isOn ? section.fill.opacity(0.55) : Color.clear,
                            lineWidth: 1
                        )
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
        .animation(.snappy(duration: 0.18), value: selection)
    }
}

// MARK: - Pill

/// The PWA's chip, in three weights.
///
/// `MedxChip` in `Theme/GlassModifier.swift` is the semantic one — "No official key" in
/// orange, a wrong count in red — and stays exactly as it is. This is the wayfinding one: a
/// bank tag, a section length, a paper's `3 × 50` shape.
public struct MedxPill: View {
    public enum Weight {
        /// Filled with the hue. For the one thing on a row that must be read first.
        case solid
        /// The hue's soft wash. The default, and what most rows want.
        case soft
        /// Hairline only, no fill — for a figure that is context rather than status.
        case outline
    }

    private let text: String
    private let hue: Color
    private let weight: Weight
    private let icon: String?

    public init(_ text: String, hue: Color = MedxCandy.mint, weight: Weight = .soft, icon: String? = nil) {
        self.text = text
        self.hue = hue
        self.weight = weight
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(background)
        .overlay {
            if weight == .outline {
                Capsule().strokeBorder(MedxSurface.separator, lineWidth: MedxSurface.hairline)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// On a solid fill the text is a fixed near-black rather than `.systemBackground`.
    /// Every hue in the palette is light in *both* appearances — that is what makes them
    /// candy — so a foreground that inverts with the appearance would put white on lime.
    private var foreground: Color {
        switch weight {
        case .solid: return MedxCandy.onSolid
        case .soft: return MedxCandy.onSoft(hue)
        case .outline: return .secondary
        }
    }

    @ViewBuilder
    private var background: some View {
        switch weight {
        case .solid: Capsule().fill(hue)
        case .soft: Capsule().fill(hue.opacity(0.18))
        case .outline: Capsule().fill(Color.clear)
        }
    }
}

// MARK: - Month / group rule

/// The section divider the Marrow series and the VOD feed both use: a heading, a hairline
/// that takes the slack, and a tally. Scrolling down one of those screens is going back in
/// time, and this is what makes the boundaries between days or months legible while doing it.
public struct MedxRuleHeader: View {
    private let title: String
    private let count: Int?

    public init(_ title: String, count: Int? = nil) {
        self.title = title
        self.count = count
    }

    public var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            Rectangle()
                .fill(MedxSurface.separator)
                .frame(height: MedxSurface.hairline)

            if let count {
                Text(count.formatted())
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
