import SwiftUI

// MARK: - Runner chrome
//
// A sitting is one dense block of text with controls floating over it, and it is the screen Liquid
// Glass is actually *for*. These two panels plus anything presented are the only glass left in the app;
// everything else is opaque ink.
//
// Two panels, and only two:
//
//   * `RunnerHUD` at the top. One glass panel, not a stack of glass chips: the ✕, the clock and the
//     bookmark live *inside* it as plain glyphs, because glass cannot sample glass and a chip of glass
//     on a panel of glass comes out as a smudge on a smudge.
//   * `RunnerActionBar` at the bottom. Here the pieces *are* separate glass — Back, Skip, Next — so they
//     share a `MedxGlassGroup` and are named with `medxGlassID`, which is what makes Skip appear by
//     flowing out of Next rather than by fading in on top of it.
//
// The progress strip is now `MedxAnswerSheet` at `track` scale, which is the same grid Home's hero and
// the post-sitting review draw. It used to be two different things behind a threshold: individual
// capsules up to 30 questions, and a gradient bar above that — so a 50-question block and a 20-question
// one reported progress in visually unrelated ways. One `Canvas` handles any length.

// MARK: - HUD

struct RunnerHUD: View {
    let number: Int
    let total: Int
    /// Set only for a paper sat in blocks. An unsectioned sitting shows nothing here — the mode and the
    /// subject do not change between questions, so putting them on the HUD spent width on a line that
    /// never said anything new, and it was that line's ideal width that squeezed the clock until it
    /// truncated.
    let blockLabel: String?
    /// Per-question state for the track, relative to the block being sat.
    let statuses: [RunnerQuestionStatus]
    let currentIndex: Int
    let remainingSeconds: Int
    /// What the clock was wound to, so the ring can show a fraction rather than a number.
    let capacitySeconds: Int
    let isPaused: Bool
    let isBookmarked: Bool
    let onClose: () -> Void
    let onNavigator: () -> Void
    let onBookmark: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLow: Bool { !isPaused && remainingSeconds <= 10 }

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                closeButton
                counter

                if let blockLabel {
                    MedxBadge(blockLabel)
                        .fixedSize()
                }

                Spacer(minLength: 6)

                RunnerTimerBadge(
                    remainingSeconds: remainingSeconds,
                    capacitySeconds: capacitySeconds,
                    isPaused: isPaused
                )
                // The clock is the one thing in this row that must never be shortened, so it is taken out
                // of the compression pool entirely rather than given a priority and hoped for.
                .fixedSize()

                bookmarkButton
            }

            MedxAnswerSheet(
                cells: statuses.map(\.sheetCell),
                scale: .track,
                current: currentIndex
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .medxSurface(MedxDS.shape(MedxDS.hud), hudSpec)
        .padding(.horizontal, MedxGlass.floatInset)
        .padding(.bottom, 10)
        .animation(reduceMotion ? nil : MedxDS.snap, value: isLow)
    }

    /// The panel takes a red cast in the last ten seconds. It is the one moment in a sitting where the
    /// chrome should be impossible to ignore, and tinting the glass does it without adding a banner that
    /// would push the question down the screen.
    private var hudSpec: MedxSurfaceSpec {
        var spec = MedxSurfaceSpec.hud
        if isLow {
            spec.tint = MedxDS.wrong
            spec.strokeHue = MedxDS.wrong
            spec.strokeOpacity = 0.45
        }
        return spec
    }

    // MARK: Pieces

    private var closeButton: some View {
        Button {
            onClose()
        } label: {
            Image(systemName: "xmark")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(MedxPressStyle())
        .accessibilityLabel("Close sitting")
    }

    private var bookmarkButton: some View {
        Button {
            onBookmark()
        } label: {
            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                .font(.footnote.weight(.bold))
                .foregroundStyle(isBookmarked ? MedxDS.warn : Color.secondary)
                .symbolEffect(.bounce, value: isBookmarked)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(MedxPressStyle())
        .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark question")
    }

    /// The counter is the navigator's own button — the number you are looking at is the most natural
    /// thing to tap to go somewhere else in the paper. One line, fixed width, so it cannot bid for room
    /// the clock needs. Both figures are in the Figure voice, so the number does not shift the chevron
    /// sideways as it counts past 9 and 99.
    private var counter: some View {
        Button {
            onNavigator()
        } label: {
            HStack(spacing: 4) {
                Text("\(number)")
                    .font(MedxType.value)
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text("/ \(total)")
                    .font(MedxType.lead)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.tertiary)
            }
            .fixedSize()
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(MedxPressStyle())
        .accessibilityLabel("Question \(number) of \(total)")
        .accessibilityHint("Opens the question navigator")
    }
}

// MARK: - Clock

/// The clock, as a ring that drains plus the digits it is draining.
///
/// Deliberately *not* glass: it sits inside `RunnerHUD`'s glass panel, and glass cannot sample glass — a
/// translucent chip on a translucent panel comes out as a smudge on a smudge. A flat tinted capsule on
/// glass reads cleanly, which is the same reason the ✕ beside it is a bare glyph rather than its own pane.
struct RunnerTimerBadge: View {
    let remainingSeconds: Int
    let capacitySeconds: Int
    let isPaused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double {
        guard capacitySeconds > 0 else { return 0 }
        return min(max(Double(remainingSeconds) / Double(capacitySeconds), 0), 1)
    }

    private var isLow: Bool { !isPaused && remainingSeconds <= 10 }

    private var tint: Color {
        if isPaused { return MedxDS.correct }
        return isLow ? MedxDS.wrong : MedxTheme.accent
    }

    private var clock: String {
        let clamped = max(remainingSeconds, 0)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(MedxDS.line, lineWidth: 2.5)

                Circle()
                    .trim(from: 0, to: CGFloat(isPaused ? 1 : fraction))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                if isPaused {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: 18, height: 18)
            // One second per tick, so the ring should walk rather than spring.
            .animation(reduceMotion ? nil : .linear(duration: 0.9), value: fraction)

            // `MedxType.clock` is monospaced, which is the whole reason the digits stop twitching: with a
            // proportional face every second changed the badge's width and nudged everything beside it.
            Text(isPaused ? "Done" : clock)
                .font(MedxType.clock)
                .foregroundStyle(tint)
                .contentTransition(.numericText(countsDown: true))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(isLow ? 0.22 : 0.15), in: Capsule(style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isPaused ? "Answer revealed, timer paused" : "Time remaining \(clock)")
    }
}

// MARK: - Action bar

/// Back · Skip · Next, as three separate panes of glass floating over the question.
///
/// This is the one place in the runner where the pieces really are separate glass, so they share a
/// `MedxGlassGroup` and carry `medxGlassID`s: Skip then arrives by flowing out of the Next button and
/// leaves by flowing back into it, and Next becoming Finish is the same shape changing its mind rather
/// than one label cross-fading into another.
///
/// Nothing here uses `.interactive()` glass. Inside a `Button` label the effect takes the touch and the
/// button stops firing — that is what broke the flashcard close button — so press feedback comes from
/// `MedxPressStyle` and the glass is inert.
///
/// There used to be a `hint` above the row: "Answer to reveal the explanation", shown on every unanswered
/// question of every revision sitting. A Next button that is visibly disabled has already said it, and
/// saying it again forty times a paper is what made the bar feel like a tutorial. Gone, along with the
/// fourth pane of glass it needed.
struct RunnerActionBar: View {
    let advanceLabel: String
    let isLastQuestion: Bool
    let canGoBack: Bool
    let canAdvance: Bool
    let showSkip: Bool
    let onBack: () -> Void
    let onSkip: () -> Void
    let onAdvance: () -> Void

    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Finishing is a different act from advancing, so it is a different colour. Green for the end of a
    /// block or a paper, the app's accent for one more question.
    private var advanceHue: Color {
        isLastQuestion ? MedxDS.correct : MedxTheme.accent
    }

    var body: some View {
        MedxGlassGroup(spacing: 18) {
            HStack(spacing: 10) {
                backButton
                if showSkip {
                    skipButton
                }
                advanceButton
            }
        }
        .padding(.horizontal, MedxGlass.floatInset)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .animation(reduceMotion ? nil : MedxDS.snap, value: showSkip)
        .animation(reduceMotion ? nil : MedxDS.snap, value: isLastQuestion)
    }

    // MARK: Pieces

    private var backButton: some View {
        Button {
            onBack()
        } label: {
            Image(systemName: "chevron.left")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(canGoBack ? Color.primary : Color.secondary)
                .medxGlassCircle(diameter: 50)
                .medxGlassID("runner.back", in: glass)
        }
        .buttonStyle(MedxPressStyle())
        .disabled(!canGoBack)
        .opacity(canGoBack ? 1 : 0.45)
        .accessibilityLabel("Previous question")
    }

    private var skipButton: some View {
        Button {
            onSkip()
        } label: {
            Text("Skip")
                .font(MedxType.title)
                .foregroundStyle(.secondary)
                .frame(minWidth: 58, minHeight: 50)
                .medxSurface(
                    Capsule(style: .continuous),
                    MedxSurfaceSpec(material: .glass(clear: false), fill: MedxDS.sunken)
                )
                .contentShape(Capsule(style: .continuous))
                .medxGlassID("runner.skip", in: glass)
        }
        .buttonStyle(MedxPressStyle())
        .accessibilityLabel("Skip question")
    }

    private var advanceButton: some View {
        Button {
            onAdvance()
        } label: {
            HStack(spacing: 7) {
                Text(advanceLabel)
                    .font(MedxType.heading)
                Image(systemName: isLastQuestion ? "checkmark" : "chevron.right")
                    .font(.footnote.weight(.black))
                    .symbolEffect(.bounce, value: isLastQuestion)
            }
            .foregroundStyle(canAdvance ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .medxSurface(
                Capsule(style: .continuous),
                MedxSurfaceSpec(
                    material: .glass(clear: false),
                    fill: canAdvance ? advanceHue.opacity(0.24) : MedxDS.sunken,
                    tint: canAdvance ? advanceHue : nil,
                    strokeHue: canAdvance ? advanceHue : nil,
                    strokeOpacity: 0.55,
                    strokeWidth: canAdvance ? 1.2 : 0.5
                )
            )
            .contentShape(Capsule(style: .continuous))
            .medxGlassID("runner.advance", in: glass)
        }
        .buttonStyle(MedxPressStyle())
        .disabled(!canAdvance)
        .accessibilityLabel(advanceLabel)
    }
}
