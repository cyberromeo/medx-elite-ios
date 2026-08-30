import SwiftUI

// MARK: - Activity chrome
//
// Compiled into **both** the app and the `MedxWidgets` extension, like `MedxSharedState.swift`, so
// the three Live Activities read as one family instead of three one-off layouts. It therefore
// imports nothing app-specific: no theme, no models, no `MedxSurface`. Colour arrives as a hex
// string in the activity's attributes, exactly as the snapshot does.

public extension Color {
    /// The accent or duel colour travelling as hex, because an extension cannot resolve the app's
    /// dynamic `UIColor` tokens.
    init(medxHex: String) {
        let components = medxHex.medxRGBComponents
        self.init(.sRGB, red: components.red, green: components.green, blue: components.blue, opacity: 1)
    }
}

/// A progress ring with something in the middle.
///
/// The ring is what makes an activity glanceable: a bar tells you a fraction, a ring plus a number
/// tells you the fraction *and* the figure in the same 44 points. Used at three sizes — the Lock
/// Screen, the expanded island, and the compact island, where it is the only thing that fits.
public struct MedxActivityRing<Center: View>: View {
    private let fraction: Double
    private let tint: Color
    private let lineWidth: CGFloat
    private let center: Center

    public init(
        fraction: Double,
        tint: Color,
        lineWidth: CGFloat = 7,
        @ViewBuilder center: () -> Center
    ) {
        self.fraction = min(max(fraction, 0), 1)
        self.tint = tint
        self.lineWidth = lineWidth
        self.center = center()
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.22), lineWidth: lineWidth)

            Circle()
                // A hair of trim always drawn, so a ring at zero still reads as a ring rather than
                // as a flat grey circle somebody forgot to fill.
                .trim(from: 0, to: max(fraction, 0.004))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            center
                .padding(lineWidth + 1)
        }
        .accessibilityHidden(true)
    }
}

public extension MedxActivityRing where Center == EmptyView {
    init(fraction: Double, tint: Color, lineWidth: CGFloat = 7) {
        self.init(fraction: fraction, tint: tint, lineWidth: lineWidth) { EmptyView() }
    }
}

/// Answered against elapsed — the number that actually says whether you are behind.
///
/// A plain progress bar of "23 of 50 answered" is not enough on a timed paper: 23 of 50 with forty
/// minutes left is comfortable and with four minutes left is not. The pace mark is where the
/// *clock* is, so the gap between the fill and the mark is the whole reading.
public struct MedxPaceBar: View {
    private let done: Double
    private let elapsed: Double
    private let tint: Color

    public init(done: Double, elapsed: Double, tint: Color) {
        self.done = min(max(done, 0), 1)
        self.elapsed = min(max(elapsed, 0), 1)
        self.tint = tint
    }

    /// Behind means less answered than time spent. Amber rather than red: it is a nudge, and a
    /// red bar on a paper somebody is still sitting is just unkind.
    private var isBehind: Bool { done + 0.02 < elapsed }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(0.2))

                Capsule()
                    .fill(isBehind ? Color.orange : tint)
                    .frame(width: max(3, geo.size.width * done))

                Capsule()
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: 2)
                    .offset(x: max(0, geo.size.width * elapsed - 1))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// Two halves sized by points, each in its owner's duel colour.
///
/// Level pegging — including 0–0 before the first question — splits down the middle rather than
/// collapsing to one side, so the bar always reads as a contest rather than as a bug.
public struct MedxActivityVersusBar: View {
    private let share: Double
    private let mine: Color
    private let theirs: Color

    public init(share: Double, mine: Color, theirs: Color) {
        self.share = min(max(share, 0), 1)
        self.mine = mine
        self.theirs = theirs
    }

    public var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(mine)
                    .frame(width: max(3, geo.size.width * share))
                Rectangle()
                    .fill(theirs)
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// `Text(timerInterval:)` lets the system tick the clock, so the app only pushes an update when a
/// *count* changes — not once a second. The range is clamped because a finished sitting can leave
/// its end date in the past, and an inverted range traps.
public struct MedxActivityTimer: View {
    private let endDate: Date

    public init(endDate: Date) {
        self.endDate = endDate
    }

    public var body: some View {
        let now = Date()
        let end = max(endDate, now.addingTimeInterval(1))
        return Text(timerInterval: now...end, countsDown: true)
    }
}
