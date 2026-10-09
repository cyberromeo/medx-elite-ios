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

// MARK: - Card swipe actions
//
// The platform's `.swipeActions` slide the whole list row sideways. On a page of inset cards that
// pushed the card's leading edge off the screen (the class number and the start of the title
// vanished under the left edge) and drew iOS 26's floating action circle with its label hanging
// underneath, neither the row's height nor centred on it.
//
// Here the card never leaves its margins. Swiping squeezes it from the side being uncovered and
// the actions grow into the space it gives up: each one a rounded tile the full height of the row,
// with the card's own corner radius, icon over label, centred. A tap anywhere on an open card
// closes it, opening one row closes any other, and every action is also offered to VoiceOver.

public struct MedxSwipeAction: Identifiable {
    public let id: String
    public let title: String
    public let icon: String
    public let tint: Color
    public let perform: () -> Void

    public init(_ title: String, icon: String, tint: Color, perform: @escaping () -> Void) {
        self.id = title + icon
        self.title = title
        self.icon = icon
        self.tint = tint
        self.perform = perform
    }
}

/// Which row is open, so opening one closes the last.
@MainActor
final class MedxSwipeCoordinator: ObservableObject {
    static let shared = MedxSwipeCoordinator()
    @Published var openRow: UUID?
    #if DEBUG
    var didDemo = false
    #endif
}

private struct MedxSwipeRowModifier: ViewModifier {
    let leading: [MedxSwipeAction]
    let trailing: [MedxSwipeAction]
    let cornerRadius: CGFloat

    @ObservedObject private var coordinator = MedxSwipeCoordinator.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var rowID = UUID()
    /// Positive: leading actions showing. Negative: trailing actions showing.
    @State private var reveal: CGFloat = 0
    @State private var dragBase: CGFloat?
    @GestureState private var isDragging = false

    private static let tileWidth: CGFloat = 76
    private static let gap: CGFloat = 8

    private func span(_ actions: [MedxSwipeAction]) -> CGFloat {
        guard !actions.isEmpty else { return 0 }
        let count = CGFloat(actions.count)
        return count * Self.tileWidth + count * Self.gap
    }

    private var settle: Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)
    }

    func body(content: Content) -> some View {
        let leadingShown = max(reveal, 0)
        let trailingShown = max(-reveal, 0)

        content
            // An open card answers a tap by closing, not by opening what it shows.
            .overlay {
                if reveal != 0 {
                    Color.white.opacity(0.001)
                        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .onTapGesture { close() }
                }
            }
            .padding(.leading, leadingShown)
            .padding(.trailing, trailingShown)
            .overlay(alignment: .leading) {
                if leadingShown > Self.gap {
                    tiles(leading, width: leadingShown - Self.gap)
                }
            }
            .overlay(alignment: .trailing) {
                if trailingShown > Self.gap {
                    tiles(trailing, width: trailingShown - Self.gap)
                }
            }
            .simultaneousGesture(drag)
            .onChange(of: isDragging) { _, dragging in
                // The scroll view can take a drag over without an end event; settle either way.
                if !dragging { settleAfterDrag(predicted: nil) }
            }
            .onChange(of: coordinator.openRow) { _, open in
                if open != rowID, reveal != 0 {
                    withAnimation(settle) { reveal = 0 }
                }
            }
            .accessibilityActions {
                ForEach(leading + trailing) { action in
                    Button(action.title) { action.perform() }
                }
            }
            #if DEBUG
            // Screenshot runs only (`-medxSwipeOpen YES`): the first row with trailing actions
            // opens them, so the swipe can be checked without a finger.
            .onAppear {
                guard MedxDemoMode.isOn,
                      UserDefaults.standard.bool(forKey: "medxSwipeOpen"),
                      !trailing.isEmpty,
                      !MedxSwipeCoordinator.shared.didDemo
                else { return }
                MedxSwipeCoordinator.shared.didDemo = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    coordinator.openRow = rowID
                    withAnimation(settle) { reveal = -span(trailing) }
                }
            }
            #endif
    }

    private func tiles(_ actions: [MedxSwipeAction], width: CGFloat) -> some View {
        HStack(spacing: Self.gap) {
            ForEach(actions) { action in
                Button {
                    HapticManager.light()
                    action.perform()
                    close()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: action.icon)
                            .font(.system(size: 17, weight: .semibold))
                        Text(action.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(.white)
                    // Labels arrive once there is room for them, instead of being squashed.
                    .opacity(width >= span(actions) * 0.6 ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(action.tint.gradient)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
                .buttonStyle(MedxPressStyle())
                .accessibilityHidden(true)
            }
        }
        .frame(width: max(width, 0))
        .frame(maxHeight: .infinity)
        .clipped()
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .local)
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if dragBase == nil {
                    // Only a clearly sideways drag belongs to the row; anything else is the scroll.
                    guard abs(dx) > abs(dy) * 1.3 else { return }
                    dragBase = reveal
                    coordinator.openRow = rowID
                }
                var next = (dragBase ?? 0) + dx
                if leading.isEmpty { next = min(next, 0) }
                if trailing.isEmpty { next = max(next, 0) }
                let maxLeading = span(leading)
                let maxTrailing = span(trailing)
                // Rubber band past the open width.
                if next > maxLeading { next = maxLeading + (next - maxLeading) * 0.2 }
                if next < -maxTrailing { next = -maxTrailing + (next + maxTrailing) * 0.2 }
                reveal = next
            }
            .onEnded { value in
                settleAfterDrag(predicted: (dragBase ?? reveal) + value.predictedEndTranslation.width)
            }
    }

    private func settleAfterDrag(predicted: CGFloat?) {
        guard dragBase != nil else { return }
        dragBase = nil
        let target = predicted ?? reveal
        withAnimation(settle) {
            if reveal > 0 {
                reveal = target > span(leading) / 2 ? span(leading) : 0
            } else if reveal < 0 {
                reveal = -target > span(trailing) / 2 ? -span(trailing) : 0
            }
        }
        if reveal != 0 { HapticManager.selection() }
    }

    private func close() {
        withAnimation(settle) { reveal = 0 }
    }
}

public extension View {
    /// Swipe actions for a card row that keep the card inside its margins. See the note above.
    func medxSwipeActions(
        leading: [MedxSwipeAction] = [],
        trailing: [MedxSwipeAction] = [],
        cornerRadius: CGFloat = MedxSurface.cardRadius
    ) -> some View {
        modifier(MedxSwipeRowModifier(leading: leading, trailing: trailing, cornerRadius: cornerRadius))
    }
}
