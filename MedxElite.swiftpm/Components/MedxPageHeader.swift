import SwiftUI

// MARK: - Page header
//
// **Only for a screen that has no navigation bar of its own.**
//
// This used to be on the tab roots as well, and that is how the app ended up saying everything
// twice: `QBankSubjectListView` set `.navigationTitle("Question Bank")` *and* drew
// `MedxPageHeader(title: "Question Bank")`, so the words appeared in the bar and again forty
// points below it. Tests, Classes, Cards, Faceoff, Custom modules, Batch papers and the VOD feed
// all did the same, and so did the two detail sheets whose nav title was already the paper's or
// the module's name. Every one of them now uses the platform's *large* title with
// `MedxPageCaption` for the one figure the lead sentence was actually carrying.
//
// What is left is exactly one caller: `MedxSectionHandoverSheet`, a full-screen cover between two
// blocks of a grand paper with no bar and no way back, where the page really does have to introduce
// itself. If a second caller ever appears, check first that it is not about to print its own
// navigation title twice.
//
// The mark is an SF Symbol in the section's hue, not a sticker: as a symbol it takes the section
// colour, tracks Dynamic Type and sits in the same rounded square the system uses in Settings
// and Shortcuts.

public struct MedxPageHeader<Trailing: View>: View {
    private let section: MedxSection
    private let eyebrow: String?
    private let title: String
    private let lead: String?
    private let symbol: String?
    private let trailing: Trailing

    @Environment(\.dynamicTypeSize) private var typeSize

    /// `symbol` defaults to the section's own, so a screen only names one when it wants
    /// something more specific than "this is the QBank".
    public init(
        section: MedxSection,
        eyebrow: String? = nil,
        title: String,
        lead: String? = nil,
        symbol: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.section = section
        self.eyebrow = eyebrow
        self.title = title
        self.lead = lead
        self.symbol = symbol
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

                // At an accessibility type size the mark is the first thing that should give
                // up its room — the lead paragraph needs it more.
                if !typeSize.isAccessibilitySize {
                    MedxSymbolMark(symbol ?? section.symbol, hue: section.fill, size: 44)
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
        symbol: String? = nil
    ) {
        self.init(
            section: section,
            eyebrow: eyebrow,
            title: title,
            lead: lead,
            symbol: symbol
        ) { EmptyView() }
    }
}

// MARK: - Page caption

/// One quiet line under a platform large title.
///
/// This is what is left of `MedxPageHeader` on the nine screens that now use
/// `.navigationBarTitleDisplayMode(.large)`. Their leads were two sentences each, and only the
/// first half of the first one ever said anything a student did not already know — "32,467
/// questions across two banks" is a figure, "Marrow's ids are prefixed, so a module runs the
/// same either way" is release notes.
///
/// So: the figure stays, as a caption; the prose goes. `.footnote` and secondary, which is the
/// weight iOS puts under a large title in Settings and in Health.
public struct MedxPageCaption: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    /// The row is a real `View` type rather than a computed property for one specific reason:
    /// `ViewThatFits` builds *both* candidates in order to measure them, and the row carries a
    /// `matchedGeometryEffect`. Two rows sharing one `@Namespace` would put two sources in the same
    /// geometry group. A separate type gives each candidate its own namespace, which is the only
    /// way the slide stays a slide.
    public var body: some View {
        ViewThatFits(in: .horizontal) {
            MedxSegmentedRow(section: section, segments: segments, selection: $selection)

            ScrollView(.horizontal, showsIndicators: false) {
                MedxSegmentedRow(section: section, segments: segments, selection: $selection)
            }
        }
    }
}

/// One pill sliding along a track, rather than four each lighting up in turn.
///
/// The slide is a `matchedGeometryEffect`: exactly one segment draws the pill at a time, and because
/// every segment names the same geometry id, SwiftUI interpolates the pill's frame from the old
/// label to the new one. This replaced a `glassEffectID` morph that only existed on iOS 26 — a real
/// slide, on every OS version, and four fewer panes of glass.
private struct MedxSegmentedRow<Value: Hashable>: View {
    let section: MedxSection
    let segments: [MedxSegment<Value>]
    @Binding var selection: Value

    @Namespace private var slider
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(segments) { segment in
                segmentButton(segment)
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(MedxInk.sunken))
        .animation(reduceMotion ? nil : MedxMotion.snap, value: selection)
    }

    private func segmentButton(_ segment: MedxSegment<Value>) -> some View {
        let isOn = segment.value == selection

        return Button {
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
            .foregroundStyle(isOn ? MedxCandy.onSolid : Color.secondary)
            .padding(.horizontal, 14)
            .frame(minHeight: 34)
            .background {
                if isOn {
                    Capsule(style: .continuous)
                        .fill(section.fill)
                        .matchedGeometryEffect(id: "medx.segmented.selection", in: slider)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
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
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .medxPillSurface(weight: weight, hue: hue)
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
}

private extension View {
    /// A pill's surface, by weight. All three are ink.
    ///
    /// `soft` and `outline` were glass, which was wrong twice over: a pill is the *smallest*
    /// surface in the app and there are often four in one row, so each one was a backdrop sample
    /// of the same patch of page — and a row of them came out as a single smear rather than as
    /// four readable tags.
    @ViewBuilder
    func medxPillSurface(weight: MedxPill.Weight, hue: Color) -> some View {
        switch weight {
        case .solid:
            self.background(Capsule(style: .continuous).fill(hue))
        case .soft:
            self.background(Capsule(style: .continuous).fill(hue.opacity(0.18)))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(hue.opacity(0.30), lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
        case .outline:
            self.overlay {
                Capsule(style: .continuous)
                    .strokeBorder(MedxInk.hairline, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
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
