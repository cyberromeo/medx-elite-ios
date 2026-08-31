import SwiftUI

// MARK: - The row vocabulary
//
// Every browse screen in this app is a list, and until now none of them used one. Ten screens were a
// `ScrollView` wrapping a `LazyVStack` of `Button`s wrapping `medxCard` — which builds a live SwiftUI
// subtree per row and *keeps* every row it has scrolled past. On 352 papers, 1,211 modules and 2,900
// VOD documents that is the whole performance problem in one shape.
//
// A `List` is a `UICollectionView` underneath: cells are reused, off-screen rows are released, and the
// scrolling is the system's. It is also what "pure Apple" concretely means — Mail, Music, Files and
// Settings are all this.
//
// So this file is the row, and nothing else. One layout, used by every list in the app:
//
//     ┌──────┬────────────────────────────────┬──────────┐
//     │ 08/19│ Grand Test 41                  │ ▓▓▓▒ ›   │
//     │      │ 3 × 50 · 150 QUESTIONS         │          │
//     └──────┴────────────────────────────────┴──────────┘
//       lead   title over tag/detail            trailing
//
// The lead is a **figure**, not an icon, and it is a fixed-width column so titles align all the way
// down a list — which is the job the hue-washed icon square used to do, minus the surface. See
// `MedxType` for why a number is always set in the rounded monospaced face.

public struct MedxRow<Trailing: View>: View {
    /// The width of the leading figure column. Wide enough for `08/19` at the largest non-accessibility
    /// type size; a longer lead truncates rather than pushing the title out of alignment.
    private static var leadWidth: CGFloat { 46 }

    private let lead: String?
    private let title: String
    private let tag: String?
    private let detail: String?
    private let trailing: Trailing

    @Environment(\.dynamicTypeSize) private var typeSize

    public init(
        lead: String? = nil,
        title: String,
        tag: String? = nil,
        detail: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.lead = lead
        self.title = title
        self.tag = tag
        self.detail = detail
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let lead, !lead.isEmpty {
                Text(lead)
                    .font(MedxType.lead)
                    .foregroundStyle(.secondary)
                    // At an accessibility size the fixed column stops being an alignment aid and
                    // starts stealing the title's room, so it gives up its width first.
                    .frame(
                        width: typeSize.isAccessibilitySize ? nil : Self.leadWidth,
                        alignment: .leading
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(MedxType.title)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let second, !second.isEmpty {
                    Text(second)
                        .medxTag()
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            trailing
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    /// Tag and detail share one line, because two secondary lines under a title is what made the old
    /// rows 72 points tall. The tag comes first — it is the category — and the detail follows it.
    private var second: String? {
        let parts = [tag, detail].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

public extension MedxRow where Trailing == MedxChevron {
    /// The common case: a row that pushes.
    init(lead: String? = nil, title: String, tag: String? = nil, detail: String? = nil) {
        self.init(lead: lead, title: title, tag: tag, detail: detail) { MedxChevron() }
    }
}

// MARK: - Chevron

/// The push affordance, at the weight iOS draws it in Settings.
///
/// Drawn by hand rather than left to `NavigationLink`'s own, because these rows are often `Button`s
/// that present a sheet instead of pushing, and a list where half the rows have a chevron and half
/// do not reads as half of them being broken.
public struct MedxChevron: View {
    public init() {}

    public var body: some View {
        Image(systemName: "chevron.forward")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

// MARK: - Section header

/// A section's heading and its tally.
///
/// Replaces `MedxRuleHeader`, which drew a hairline `Rectangle` stretching to take up the slack
/// between the title and the count. A list already separates its sections; the rule was drawing a
/// boundary that the layout had drawn for it.
public struct MedxHeader: View {
    private let title: String
    private let count: Int?

    public init(_ title: String, count: Int? = nil) {
        self.title = title
        self.count = count
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .medxTag()

            Spacer(minLength: 8)

            if let count {
                Text(count.formatted())
                    .font(MedxType.figure(11, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Badge

/// A small capsule carrying a figure or a status word.
///
/// One fill and no border, and its colour comes from `MedxDS`'s outcome set rather than from a section
/// hue — see the colour rule at the top of `MedxDS.swift`. This replaces `MedxPill` (three weights,
/// each a fill plus a hairline plus a gradient rim) and `MedxChip`.
public struct MedxBadge: View {
    private let text: String
    private let tint: Color?

    /// `tint` nil is the neutral badge: a count, a length, a shape like `3 × 50`. A tint means the
    /// badge is reporting an *outcome*, and there are only three of those.
    public init(_ text: String, tint: Color? = nil) {
        self.text = text
        self.tint = tint
    }

    public var body: some View {
        Text(text)
            .font(MedxType.figure(12, weight: .bold))
            .foregroundStyle(tint ?? .secondary)
            .contentTransition(.numericText())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(tint?.opacity(0.16) ?? MedxDS.sunken)
            )
            .accessibilityElement(children: .combine)
    }
}

// MARK: - Stat

/// A figure over its label. The unit a summary row is built from.
///
/// Replaces `MedxMetric`, which was an icon, a value and a label inside its own surface, laid out by a
/// `MedxMetricsRow` that used `ViewThatFits` — so both candidate layouts were built and measured on
/// every pass. Three of these in an `HStack` needs neither the surface nor the measuring.
public struct MedxStat: View {
    private let value: String
    private let label: String
    private let tint: Color?

    public init(_ value: String, label: String, tint: Color? = nil) {
        self.value = value
        self.label = label
        self.tint = tint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(MedxType.value)
                .foregroundStyle(tint ?? .primary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .medxTag()
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}

// MARK: - Caption

/// One quiet line under a platform large title.
///
/// The screen's lead figure goes above it in the Figure voice; this is the words that qualify it.
public struct MedxCaption: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .medxTag()
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The list itself

public extension View {
    /// A row's surface: one rounded fill, no border, no shadow, and a 4pt gap to its neighbour.
    ///
    /// Applied to the row rather than to the `List` so a section can opt a row out — the answer-sheet
    /// hero on Home sits on the page, not on a card.
    func medxListRow() -> some View {
        self
            .listRowBackground(
                MedxDS.shape(MedxDS.card)
                    .fill(MedxDS.row)
                    .padding(.vertical, 2)
            )
            .listRowSeparator(.hidden)
            .listRowInsets(
                EdgeInsets(top: 10, leading: MedxDS.gutter, bottom: 10, trailing: MedxDS.gutter)
            )
    }

    /// A row that is content rather than a card — a hero, a chart, a summary strip.
    func medxPlainRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(
                EdgeInsets(top: 8, leading: MedxDS.gutter, bottom: 8, trailing: MedxDS.gutter)
            )
    }

    /// Everything every list in the app sets, in one call.
    ///
    /// `scrollContentBackground(.hidden)` is what lets `#000` through: a `List` paints
    /// `systemGroupedBackground` behind itself otherwise, and that grey is the single most common way
    /// a pitch-black app stops being pitch black.
    func medxList() -> some View {
        self
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .medxPage()
            .scrollIndicators(.automatic)
    }
}

// MARK: - Close

/// The ✕ over a full-screen figure, and the only round button left in the app.
///
/// `MedxCircleButton` used to be this, plus a bookmark, plus an overflow, plus a download control —
/// four different jobs behind one API, each of them a fill and a hairline and a gradient rim. The other
/// three are now bare glyphs in their own rows, so what is left is one button with one job: get me out
/// of this image.
public struct MedxCloseButton: View {
    private let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.black.opacity(0.45)))
                .contentShape(Circle())
        }
        .buttonStyle(MedxPressStyle())
        .accessibilityLabel("Close figure")
    }
}
