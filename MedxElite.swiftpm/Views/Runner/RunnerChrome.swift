import SwiftUI

// MARK: - Runner chrome
//
// The sitting screen, redesigned to the reference: a black canvas with a faint dotted grid, and
// Liquid Glass controls floating over the question. This is the one screen glass is actually
// *for* — chrome floating over content that is already there.
//
//   * `RunnerHUD` at the top: a full-width **time-remaining** bar (green, red for the last 20%)
//     just under the status bar, then a row of a circular close button, a circular bookmark, and
//     the countdown pill. On iPad the question counter also rides at the top-right.
//   * `RunnerActionBar` at the bottom: `←  ·  3/50  ·  →` on iPhone; on iPad both arrows group in
//     the right corner. The blue circle advances (and becomes finish/submit on the last question).
//
// The circles are built like `MedxCircleButton` — the app's proven circular control — with a plain
// `Button`, an explicit circular frame and a `contentShape(Circle())` so the whole circle takes the
// tap. That last part matters: `.buttonStyle(.glass)` hit-tested only the bare glyph and its
// *interactive* glass swallowed the touch, which is what left the ✕ dead. Neutral circles wear
// non-interactive glass (`medxGlassCircle`); the primary Next is a solid tinted fill.
//
// The progress track that used to live here (`MedxAnswerSheet` at `track` scale) is gone from the
// HUD; the OMR grid still draws in the question navigator and the post-sitting review. What the top
// bar shows now is time, exactly as the reference annotates it: the block's clock in exam mode, the
// per-question 60s in revision.

// MARK: - Dotted canvas

/// The faint dot grid behind the question. One `Canvas`, drawn once, no assets — low-opacity dots on
/// a regular pitch, so the black page has texture without anything to read.
struct RunnerDotField: View {
    var pitch: CGFloat = 26
    var dot: CGFloat = 1.6

    var body: some View {
        Canvas { context, size in
            let color = GraphicsContext.Shading.color(.white.opacity(0.05))
            var y: CGFloat = pitch / 2
            while y < size.height {
                var x: CGFloat = pitch / 2
                while x < size.width {
                    let rect = CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot)
                    context.fill(Path(ellipseIn: rect), with: color)
                    x += pitch
                }
                y += pitch
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - A glass button

/// A round control in the runner chrome, built on the **same structure as `MedxCircleButton`** —
/// the app's proven circular control on every other page: a plain `Button`, an explicit circular
/// frame, and a `contentShape(Circle())` so the whole circle is the tap target. That last part is
/// why this exists instead of `.buttonStyle(.glass)` — the glass button style hit-tested only the
/// bare glyph and its interactive glass swallowed the touch, which is what left the ✕ dead.
///
/// Neutral buttons wear non-interactive Liquid Glass (`medxGlassCircle`); `prominent` is a solid
/// tinted fill (`medxInkCircle`) — the blue Next, drawn opaque exactly as the reference shows it.
///
/// `hitExpansion` grows the tap target *past* the visible circle without changing the layout: the
/// padding enlarges the hittable `Rectangle`, the matching negative padding collapses the footprint
/// back. The ✕ uses it because, sitting in the top-left corner behind a screen protector, taps that
/// landed a few points outside the 44pt circle were being missed even though the button was live.
struct RunnerCircleButton: View {
    let systemName: String
    var prominent: Bool = false
    var tint: Color? = nil
    var foreground: Color = .primary
    /// Visible circle *and* base hit target. Kept at HIG-comfortable sizes, not the oversized ones
    /// the glass control metrics were producing.
    var diameter: CGFloat = 44
    /// Extra tappable margin on every side, beyond the visible circle, with no layout cost.
    var hitExpansion: CGFloat = 0
    var bounceOn: Bool = false
    let action: () -> Void

    private var glyph: some View {
        Image(systemName: systemName)
            .font(.system(size: max(15, diameter * 0.36), weight: .semibold))
            .symbolEffect(.bounce, value: bounceOn)
    }

    var body: some View {
        Button(action: action) {
            if prominent {
                glyph
                    .foregroundStyle(.white)
                    .medxInkCircle(diameter: diameter, tint: tint ?? MedxTheme.accent)
            } else {
                glyph
                    .foregroundStyle(foreground)
                    .medxGlassCircle(diameter: diameter)
            }
        }
        .buttonStyle(MedxPressStyle())
        .modifier(HitExpansion(amount: hitExpansion))
    }
}

/// Enlarges a control's tap target by `amount` on every side without disturbing surrounding layout:
/// pad out, make that whole rectangle the content shape, then pad back in by the same amount.
private struct HitExpansion: ViewModifier {
    let amount: CGFloat

    func body(content: Content) -> some View {
        if amount > 0 {
            content
                .padding(amount)
                .contentShape(Rectangle())
                .padding(-amount)
        } else {
            content
        }
    }
}

// MARK: - Time bar

/// The progress bar that spans the top of the runner, just under the status bar. Not glass — a
/// filled track, the one solid element above the floating controls, exactly as the reference
/// draws it. **Green** while there is time; it flips to **red** for the final 20%. Non-interactive,
/// so it never eats a tap meant for the close button sitting under its left end.
struct RunnerTimeBar: View {
    let fraction: Double
    let isPaused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Red for the final fifth of the clock; green above it. Paused (revision, answer revealed)
    /// reads as a full green bar.
    private var isCritical: Bool { !isPaused && fraction <= 0.2 }
    private var tint: Color { isCritical ? MedxDS.wrong : MedxDS.correct }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(MedxDS.line)
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: max(0, min(1, isPaused ? 1 : fraction)) * geo.size.width)
            }
        }
        .frame(height: 7)
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .linear(duration: 0.9), value: fraction)
        .animation(reduceMotion ? nil : MedxDS.snap, value: isCritical)
        .accessibilityElement()
        .accessibilityLabel("Time remaining")
        .accessibilityValue("\(Int((isPaused ? 1 : fraction) * 100)) percent")
    }
}

// MARK: - Counter

/// The `3 / 50` capsule. Tapping it opens the navigator — the number you are looking at is the most
/// natural thing to tap to go elsewhere. Figure voice so the digits do not shift as they count.
struct RunnerCounter: View {
    let number: Int
    let total: Int
    /// Matched to the neighbouring circles' diameter so the row is one uniform height.
    var height: CGFloat = 44
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                Text("\(number)")
                    .font(MedxType.value)
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text("/ \(total)")
                    .font(MedxType.value)
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
            .padding(.horizontal, 16)
            .frame(height: height)
            .contentShape(Capsule(style: .continuous))
            .modifier(RunnerCapsuleGlass())
        }
        .buttonStyle(MedxPressStyle())
        .accessibilityLabel("Question \(number) of \(total)")
        .accessibilityHint("Opens the question navigator")
    }
}

/// A dark glass capsule for the counter and the timer, with the iOS 17 ink fallback.
struct RunnerCapsuleGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), !reduceTransparency {
            content.glassEffect(.regular, in: Capsule(style: .continuous))
        } else {
            content.background(MedxDS.sunken, in: Capsule(style: .continuous))
        }
    }
}

// MARK: - HUD

struct RunnerHUD: View {
    let number: Int
    let total: Int
    /// Set only for a paper sat in blocks.
    let blockLabel: String?
    let remainingSeconds: Int
    /// What the clock was wound to, so the ring can show a fraction.
    let capacitySeconds: Int
    let isPaused: Bool
    let isBookmarked: Bool
    /// iPad: kept for the call site; the counter now lives in the HUD's title on every device.
    let showsInlineCounter: Bool
    /// iPad sizes the chrome up.
    let isPad: Bool
    /// What is being sat ("Gram-Positive Cocci"), shown small above the question number.
    var title: String = ""
    /// "Exam" or "Revision", shown as the eyebrow's first word.
    var modeLabel: String? = nil
    /// The block's questions as answer-sheet cells, drawn as the progress track under the row.
    var trackCells: [MedxSheetCell] = []
    /// Index into `trackCells` of the question on screen.
    var trackCurrent: Int? = nil
    /// The paper number of `trackCells[0]`, so the pills are labelled the way the key numbers them.
    var trackStart: Int = 0
    /// Indices into `trackCells` the student has bookmarked: a small dot on the pill.
    var trackMarked: Set<Int> = []
    /// Tapping a pill jumps to that question (index into `trackCells`).
    var onJump: ((Int) -> Void)? = nil
    let onClose: () -> Void
    let onNavigator: () -> Void
    let onBookmark: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var elementHeight: CGFloat { isPad ? 48 : 42 }

    private var eyebrow: String {
        var parts: [String] = []
        if let modeLabel, !modeLabel.isEmpty { parts.append(modeLabel) }
        if let blockLabel, !blockLabel.isEmpty { parts.append(blockLabel) }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { parts.append(trimmed) }
        return parts.joined(separator: " · ")
    }

    private var positionFraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(number) / Double(total), 0), 1)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                RunnerCircleButton(
                    systemName: "xmark",
                    foreground: .secondary,
                    diameter: elementHeight,
                    hitExpansion: 10,
                    action: onClose
                )
                .accessibilityLabel("Close sitting")

                // The title doubles as the way into the navigator: tapping "Question 3 of 50"
                // is where a student expects the list of questions to be.
                Button(action: onNavigator) {
                    VStack(alignment: .leading, spacing: 1) {
                        if !eyebrow.isEmpty {
                            Text(eyebrow)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("Q\(number)")
                                .font(MedxType.figure(19, weight: .bold))
                                .foregroundStyle(.primary)
                                .contentTransition(.numericText())
                            Text("of \(total)")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                        .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Question \(number) of \(total)")
                .accessibilityHint("Opens the question navigator")

                RunnerTimerRing(
                    remainingSeconds: remainingSeconds,
                    capacitySeconds: capacitySeconds,
                    isPaused: isPaused,
                    height: elementHeight
                )
                .fixedSize()

                RunnerCircleButton(
                    systemName: isBookmarked ? "bookmark.fill" : "bookmark",
                    tint: isBookmarked ? MedxDS.warn : nil,
                    foreground: isBookmarked ? MedxDS.warn : .secondary,
                    diameter: elementHeight,
                    bounceOn: isBookmarked,
                    action: onBookmark
                )
                .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark question")
            }

            // Progress: one small numbered pill per question, coloured by state. The question on
            // screen is the same size as the rest and only changes colour.
            if trackCells.count > 1 {
                RunnerQuestionPills(
                    cells: trackCells,
                    current: trackCurrent,
                    start: trackStart,
                    marked: trackMarked,
                    onJump: onJump
                )
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(MedxDS.sunken)
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [MedxTheme.accent.opacity(0.75), MedxTheme.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(proxy.size.width * positionFraction, 6))
                    }
                }
                .frame(height: 5)
                .animation(reduceMotion ? nil : MedxDS.settle, value: number)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, MedxDS.gutter)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        // A soft fade from the page colour so the stem scrolling underneath never fights the row.
        .background {
            LinearGradient(
                colors: [MedxDS.page, MedxDS.page.opacity(0.92), MedxDS.page.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Question pills

/// The HUD's progress: a scrolling row of small numbered capsules, one per question in the block.
/// Colour alone carries state (answered, right, wrong, timed out, untouched), the current question
/// is the one solid light pill at the same size as the others, and a bookmarked one carries a dot.
struct RunnerQuestionPills: View {
    let cells: [MedxSheetCell]
    let current: Int?
    let start: Int
    let marked: Set<Int>
    let onJump: ((Int) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 6) {
                    ForEach(cells.indices, id: \.self) { index in
                        pill(index)
                            .id(index)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .frame(height: 30)
            .onAppear {
                if let current { proxy.scrollTo(current, anchor: .center) }
            }
            .onChange(of: current) { _, next in
                guard let next else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                    proxy.scrollTo(next, anchor: .center)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Questions")
    }

    private func pill(_ index: Int) -> some View {
        let isCurrent = index == current
        let style = Self.style(for: cells[index])

        return Button {
            guard !isCurrent else { return }
            HapticManager.selection()
            onJump?(index)
        } label: {
            Text("\(start + index + 1)")
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(isCurrent ? MedxDS.page : style.ink)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(minWidth: 34)
                .frame(height: 24)
                .background(Capsule(style: .continuous).fill(isCurrent ? Color.primary : style.fill))
                .overlay(alignment: .topTrailing) {
                    if marked.contains(index) {
                        Circle()
                            .fill(MedxDS.warn)
                            .frame(width: 7, height: 7)
                            .offset(x: 1, y: -1)
                    }
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(onJump == nil)
        .accessibilityLabel("Question \(start + index + 1)")
        .accessibilityValue(isCurrent ? "Current" : Self.label(for: cells[index]))
    }

    private static func style(for cell: MedxSheetCell) -> (fill: Color, ink: Color) {
        switch cell {
        case .answered: return (MedxTheme.accent.opacity(0.30), MedxTheme.accent)
        case .correct: return (MedxDS.correct.opacity(0.28), MedxDS.correct)
        case .wrong: return (MedxDS.wrong.opacity(0.28), MedxDS.wrong)
        case .missed: return (MedxDS.warn.opacity(0.28), MedxDS.warn)
        case .pending: return (MedxDS.sunken, Color.secondary)
        }
    }

    private static func label(for cell: MedxSheetCell) -> String {
        switch cell {
        case .answered: return "Answered"
        case .correct: return "Correct"
        case .wrong: return "Wrong"
        case .missed: return "Timed out"
        case .pending: return "Not answered"
        }
    }
}

// MARK: - Clock ring

/// The countdown as a pill: a small ring that drains around a clock glyph, then the exact time.
/// Green with plenty left, orange past the last third, red in the last ten seconds or the last
/// fifth; "Done" with a tick once a revision answer pauses it.
struct RunnerTimerRing: View {
    let remainingSeconds: Int
    let capacitySeconds: Int
    let isPaused: Bool
    var height: CGFloat = 42

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double {
        guard capacitySeconds > 0 else { return 0 }
        return min(max(Double(remainingSeconds) / Double(capacitySeconds), 0), 1)
    }

    private var tint: Color {
        if isPaused { return MedxDS.correct }
        if remainingSeconds <= 10 || fraction <= 0.2 { return MedxDS.wrong }
        if fraction <= 0.34 { return MedxDS.warn }
        return MedxDS.correct
    }

    private var clock: String {
        let clamped = max(remainingSeconds, 0)
        if clamped >= 3600 {
            return String(format: "%d:%02d:%02d", clamped / 3600, (clamped % 3600) / 60, clamped % 60)
        }
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    var body: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.22), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: isPaused ? 1 : fraction)
                    .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .linear(duration: 0.9), value: fraction)
                Image(systemName: isPaused ? "checkmark" : "clock")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(tint)
            }
            .frame(width: 20, height: 20)

            Text(isPaused ? "Done" : clock)
                .font(MedxType.figure(16, weight: .bold))
                .foregroundStyle(remainingSeconds <= 10 && !isPaused ? MedxDS.wrong : .primary)
                .contentTransition(.numericText(countsDown: true))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: height)
        .modifier(RunnerCapsuleGlass())
        .accessibilityElement()
        .accessibilityLabel(isPaused ? "Answer revealed, timer paused" : "Time remaining \(clock)")
    }
}

// MARK: - Clock pill

/// The countdown, as digits on a dark glass pill — the `00:57` in the mockup. The draining is now
/// the bar's job, so this is just the exact time, monospaced so it does not twitch.
struct RunnerTimerBadge: View {
    let remainingSeconds: Int
    let isPaused: Bool
    /// Matched to the neighbouring circles' diameter so the HUD row is one uniform height.
    var height: CGFloat = 44

    private var isLow: Bool { !isPaused && remainingSeconds <= 10 }

    private var tint: Color {
        if isPaused { return MedxDS.correct }
        return isLow ? MedxDS.wrong : .primary
    }

    private var clock: String {
        let clamped = max(remainingSeconds, 0)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    var body: some View {
        Text(isPaused ? "Done" : clock)
            .font(MedxType.clock)
            .foregroundStyle(tint)
            .contentTransition(.numericText(countsDown: true))
            .padding(.horizontal, 14)
            .frame(height: height)
            .modifier(RunnerCapsuleGlass())
            .accessibilityElement()
            .accessibilityLabel(isPaused ? "Answer revealed, timer paused" : "Time remaining \(clock)")
    }
}

// MARK: - Action bar

/// The bottom controls, built on the same circular glass structure as the prominent Next: on
/// iPhone `←  ·  3/50  ·  →` across the width; on iPad both arrows sit together in the right
/// corner (the counter is the HUD's job there) and step up to the `.extraLarge` glass size.
///
/// No Skip button and no text label, matching the mockup: in exam mode the arrow always advances
/// (skipping is just tapping it), and in revision it stays disabled until the answer is revealed.
struct RunnerActionBar: View {
    let number: Int
    let total: Int
    let isLastQuestion: Bool
    let canGoBack: Bool
    let canAdvance: Bool
    /// Kept for the call site; the counter is part of the bar on every device now.
    let showsCounter: Bool
    let isPad: Bool
    let onBack: () -> Void
    let onNavigator: () -> Void
    let onAdvance: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var controlHeight: CGFloat { isPad ? 54 : 50 }

    private var advanceTint: Color { isLastQuestion ? MedxDS.correct : MedxTheme.accent }

    var body: some View {
        // One capsule of glass with three opaque controls on it. Nothing inside is glass, so
        // nothing samples glass; the buttons are plain `Button`s with their own content shapes,
        // which is what keeps every tap alive.
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(canGoBack ? Color.primary : Color.secondary)
                    .frame(width: controlHeight, height: controlHeight)
                    .background(Circle().fill(MedxDS.sunken))
                    .contentShape(Circle())
            }
            .buttonStyle(MedxPressStyle())
            .disabled(!canGoBack)
            .opacity(canGoBack ? 1 : 0.4)
            .accessibilityLabel("Previous question")

            Button(action: onNavigator) {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.3x3.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("\(number)/\(total)")
                        .font(MedxType.figure(16, weight: .bold))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
                .frame(height: controlHeight)
                .background(Capsule(style: .continuous).fill(MedxDS.sunken))
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(MedxPressStyle())
            .fixedSize()
            .accessibilityLabel("Question \(number) of \(total)")
            .accessibilityHint("Opens the question navigator")

            Button(action: onAdvance) {
                HStack(spacing: 8) {
                    Text(isLastQuestion ? "Submit" : "Next")
                        .font(.headline.weight(.bold))
                    Image(systemName: isLastQuestion ? "checkmark" : "arrow.right")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: controlHeight)
                .background {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [advanceTint.opacity(0.82), advanceTint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: advanceTint.opacity(canAdvance ? 0.45 : 0), radius: 10, y: 4)
                }
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(MedxPressStyle())
            .disabled(!canAdvance)
            .opacity(canAdvance ? 1 : 0.4)
            .accessibilityLabel(isLastQuestion ? "Submit" : "Next question")
        }
        .padding(6)
        .modifier(RunnerCapsuleGlass())
        .frame(maxWidth: isPad ? 560 : CGFloat.infinity)
        .padding(.horizontal, MedxDS.gutter)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .animation(reduceMotion ? nil : MedxDS.snap, value: isLastQuestion)
        .animation(reduceMotion ? nil : MedxDS.snap, value: canAdvance)
    }
}
