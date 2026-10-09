import SwiftUI

// MARK: - Page header
//
// The page's introduction — mark, eyebrow, lead — as content rather than chrome.
//
// **It does not draw the title, and that is the point.** It used to: a `.largeTitle.bold` set from
// the same string the screen handed `navigationTitle`, with the display mode forced to `.inline` so
// the bar would draw it small. The result was the word "Tests" twice on the screen at once, once in
// the bar and once forty points below it, on all nine screens that used this. Now the title belongs
// to the navigation bar alone — `.large`, so it is still the biggest thing on the page, still
// collapses into the bar on scroll, and comes with the back-button label and the accessibility
// title the platform wants to give it for free.
//
// What is left is what the bar could never say: the section's mark, a line of context above it, and
// a paragraph explaining what the screen is for.
//
// The mark is an SF Symbol in the section's hue, not a sticker. It leads the block now that nothing
// sits beside it — the same rounded square the system uses in Settings and Shortcuts.

public struct MedxPageHeader: View {
    private let section: MedxSection
    private let eyebrow: String?
    private let lead: String?
    private let symbol: String?

    @Environment(\.dynamicTypeSize) private var typeSize

    /// `symbol` defaults to the section's own, so a screen only names one when it wants
    /// something more specific than "this is the QBank".
    public init(
        section: MedxSection,
        eyebrow: String? = nil,
        lead: String? = nil,
        symbol: String? = nil
    ) {
        self.section = section
        self.eyebrow = eyebrow
        self.lead = lead
        self.symbol = symbol
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // At an accessibility type size the mark is the first thing that should give up its
            // room — the lead paragraph needs it more.
            if !typeSize.isAccessibilitySize {
                MedxSymbolMark(symbol ?? section.symbol, hue: section.fill, size: 44)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow ?? section.eyebrow)
                    .font(.caption2.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.7)
                    .foregroundStyle(section.onSoft)

                if let lead, !lead.isEmpty {
                    Text(lead)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
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
    /// An SF Symbol for the tab-style switcher (`MedxGlassTabs`); the pill control ignores it.
    public let icon: String?

    public var id: Value { value }

    public init(value: Value, label: String, count: Int? = nil, icon: String? = nil) {
        self.value = value
        self.label = label
        self.count = count
        self.icon = icon
    }
}

// MARK: - Glass tabs

/// A switcher drawn the way iOS 26 draws its own tab bar: one capsule of Liquid Glass, each choice
/// a symbol over its label, and the current one lifted on a soft pill that slides between them.
///
/// For a choice that changes the *whole page* underneath it — which bank the QBank is showing —
/// rather than a filter inside it. That is the line between this and `MedxSegmented`: a filter is a
/// row of pills, a switch of worlds looks like the control that switches worlds everywhere else.
///
/// The glass is non-interactive and sits on the container, never inside a button's label, so the
/// buttons keep every tap (the rule the runner's ✕ taught). Below iOS 26, or with Reduce
/// Transparency, the capsule is the system's regular material.
public struct MedxGlassTabs<Value: Hashable>: View {
    private let section: MedxSection
    private let segments: [MedxSegment<Value>]
    private let countNoun: String?
    @Binding private var selection: Value

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme

    /// `countNoun` turns a segment's count into a caption — "20 subjects".
    public init(
        section: MedxSection,
        segments: [MedxSegment<Value>],
        selection: Binding<Value>,
        countNoun: String? = nil
    ) {
        self.section = section
        self.segments = segments
        self.countNoun = countNoun
        self._selection = selection
    }

    private func caption(_ count: Int) -> String {
        guard let countNoun else { return count.formatted() }
        return "\(count.formatted()) \(countNoun)"
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(segments) { segment in
                tab(segment)
            }
        }
        .padding(5)
        .modifier(MedxGlassCapsule(reduceTransparency: reduceTransparency))
    }

    private func tab(_ segment: MedxSegment<Value>) -> some View {
        let isOn = segment.value == selection
        let ink: Color = isOn ? (scheme == .dark ? section.fill : section.onSoft) : Color.secondary

        return Button {
            guard !isOn else { return }
            HapticManager.selection()
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.32)) {
                selection = segment.value
            }
        } label: {
            HStack(spacing: 8) {
                if let icon = segment.icon {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .symbolVariant(isOn ? .fill : .none)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text(segment.label)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                    if let count = segment.count {
                        Text(caption(count))
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .opacity(0.7)
                            .lineLimit(1)
                    }
                }
            }
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background {
                if isOn {
                    Capsule(style: .continuous)
                        .fill(section.fill.opacity(scheme == .dark ? 0.2 : 0.24))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(section.fill.opacity(0.45), lineWidth: 1)
                        )
                        .matchedGeometryEffect(id: "medx.glassTabs.selection", in: namespace)
                }
            }
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(segment.label)
        .accessibilityValue(segment.count.map { caption($0) } ?? "")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// The capsule behind `MedxGlassTabs`: Liquid Glass where the system has it, the regular material
/// otherwise, with a hairline so it still has an edge over a busy background.
private struct MedxGlassCapsule: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular, in: Capsule(style: .continuous))
        } else {
            content
                .background(.regularMaterial, in: Capsule(style: .continuous))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(MedxSurface.separator.opacity(0.4), lineWidth: 0.5)
                )
        }
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
                .lineLimit(1)
                .truncationMode(.tail)
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
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Flow layout

/// Chips that wrap onto the next line instead of running off the edge of their card. Each chip is
/// offered the full row width at most, so a long module name truncates inside the card rather than
/// being cut mid-word by it.
public struct MedxFlowLayout: Layout {
    public var spacing: CGFloat
    public var lineSpacing: CGFloat

    public init(spacing: CGFloat = 6, lineSpacing: CGFloat = 6) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let width = min(size.width, maxWidth)
            if x > 0, x + width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            let width = min(size.width, maxWidth)
            if x > bounds.minX, x + width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: size.height)
            )
            x += width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// `MedxFlowLayout` as a view: `MedxFlow { chips }`.
public struct MedxFlow<Content: View>: View {
    private let spacing: CGFloat
    private let lineSpacing: CGFloat
    private let content: Content

    public init(spacing: CGFloat = 6, lineSpacing: CGFloat = 6, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.content = content()
    }

    public var body: some View {
        let layout = MedxFlowLayout(spacing: spacing, lineSpacing: lineSpacing)
        return layout {
            content
        }
    }
}
