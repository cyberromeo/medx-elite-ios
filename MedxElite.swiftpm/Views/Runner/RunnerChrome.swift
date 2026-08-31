import SwiftUI

// MARK: - Runner chrome
//
// A sitting is one dense block of text with controls floating over it, and it is the screen
// Liquid Glass is actually *for*. It is also, now, one of only two places in the app allowed to
// use it — the other being anything presented. Everything else is ink; see
// `Theme/MedxLiquidGlass.swift`.
//
// Two panels, and only two:
//
//   * `RunnerHUD` at the top. One glass panel, not a stack of glass chips: the ✕, the timer
//     and the bookmark live *inside* it as plain glyphs, because glass cannot sample glass and
//     a chip of glass on a panel of glass comes out as a smudge on a smudge.
//   * `RunnerActionBar` at the bottom. Here the pieces *are* separate glass — Back, Skip,
//     Next — so they share a `MedxGlassGroup` and are named with `medxGlassID`, which is what
//     makes Skip appear by flowing out of Next rather than by fading in on top of it.
//
// The old chrome was the system navigation bar plus a hairline progress strip plus an
// edge-to-edge `.bar`: three bands of furniture across a phone screen. This is two floating
// panels and the question in between — over pure black, with the question card opaque on top of
// it, so the glass has real text to refract and the text has nothing behind it to fight.

// MARK: - HUD

struct RunnerHUD: View {
    let number: Int
    let total: Int
    /// Set only for a paper sat in blocks. An unsectioned sitting shows nothing here — the mode
    /// and the subject do not change between questions, so putting them on the HUD spent width
    /// on a line that never said anything new, and it was that line's ideal width that squeezed
    /// the clock until it truncated.
    let blockLabel: String?
    /// Per-question state for the progress track, absolute in the paper.
    let statuses: [RunnerQuestionStatus]
    let currentIndex: Int
    let remainingSeconds: Int
    /// What the clock was wound to, so the ring can show a fraction rather than a number.
    let capacitySeconds: Int
    let isPaused: Bool
    let section: MedxSection
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
                    MedxPill(blockLabel, hue: section.fill)
                        .fixedSize()
                }

                Spacer(minLength: 6)

                RunnerTimerBadge(
                    remainingSeconds: remainingSeconds,
                    capacitySeconds: capacitySeconds,
                    isPaused: isPaused
                )
                // The clock is the one thing in this row that must never be shortened, so it is
                // taken out of the compression pool entirely rather than given a priority and
                // hoped for.
                .fixedSize()

                bookmarkButton
            }

            RunnerProgressTrack(
                statuses: statuses,
                currentIndex: currentIndex,
                section: section
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .medxSurface(
            RoundedRectangle(cornerRadius: MedxGlass.hudRadius, style: .continuous),
            hudSpec
        )
        .padding(.horizontal, MedxGlass.floatInset)
        .padding(.bottom, 10)
        .animation(reduceMotion ? nil : MedxMotion.snap, value: isLow)
    }

    /// The panel takes a red cast in the last ten seconds. It is the one moment in a sitting
    /// where the chrome should be impossible to ignore, and tinting the glass does it without
    /// adding a banner that would push the question down the screen.
    private var hudSpec: MedxSurfaceSpec {
        var spec = MedxSurfaceSpec.hud
        if isLow {
            spec.tint = MedxTheme.destructiveRed
            spec.strokeHue = MedxTheme.destructiveRed
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
        .buttonStyle(BouncyButtonStyle())
        .accessibilityLabel("Close sitting")
    }

    private var bookmarkButton: some View {
        Button {
            onBookmark()
        } label: {
            Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                .font(.footnote.weight(.bold))
                .foregroundStyle(isBookmarked ? MedxTheme.warningOrange : Color.secondary)
                .symbolEffect(.bounce, value: isBookmarked)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(BouncyButtonStyle())
        .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark question")
    }

    /// The counter is the navigator's own button, as it was in the toolbar — the number you are
    /// looking at is the most natural thing to tap to go somewhere else in the paper. One line,
    /// fixed width, so it cannot bid for room the clock needs.
    private var counter: some View {
        Button {
            onNavigator()
        } label: {
            HStack(spacing: 4) {
                Text("\(number)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                Text("/ \(total)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.tertiary)
            }
            .fixedSize()
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(BouncyButtonStyle())
        .accessibilityLabel("Question \(number) of \(total)")
        .accessibilityHint("Opens the question navigator")
    }
}

// MARK: - Clock

/// The clock, as a ring that drains plus the digits it is draining.
///
/// Deliberately *not* glass: it sits inside `RunnerHUD`'s glass panel, and glass cannot sample
/// glass — a translucent chip on a translucent panel comes out as a smudge on a smudge. A flat
/// tinted capsule on glass reads cleanly, which is the same reason the ✕ beside it is a bare
/// glyph rather than its own little pane.
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
        if isPaused { return MedxTheme.successGreen }
        return isLow ? MedxTheme.destructiveRed : MedxTheme.accent
    }

    private var clock: String {
        let clamped = max(remainingSeconds, 0)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(MedxInk.hairline, lineWidth: 2.5)

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

            Text(isPaused ? "Done" : clock)
                .font(.footnote.weight(.bold).monospacedDigit())
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

// MARK: - Progress

/// Where you are in the block, as the paper's own shape.
///
/// Up to thirty questions each one gets its own capsule, coloured by what happened to it, so
/// the track doubles as the answer sheet. Past that the segments would be sub-pixel, so it
/// becomes one bar in the section's hue.
struct RunnerProgressTrack: View {
    let statuses: [RunnerQuestionStatus]
    let currentIndex: Int
    let section: MedxSection

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double {
        guard !statuses.isEmpty else { return 0 }
        return Double(currentIndex + 1) / Double(statuses.count)
    }

    var body: some View {
        Group {
            if statuses.count > 1, statuses.count <= 30 {
                HStack(spacing: 2) {
                    ForEach(Array(statuses.enumerated()), id: \.offset) { index, status in
                        Capsule(style: .continuous)
                            .fill(status.trackColor(isCurrent: index == currentIndex))
                            .frame(height: index == currentIndex ? 5 : 3)
                    }
                }
                .frame(height: 5)
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(MedxInk.field)

                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [section.fill.opacity(0.75), section.fill],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(6, geo.size.width * fraction))
                    }
                }
                .frame(height: 4)
            }
        }
        .animation(reduceMotion ? nil : MedxMotion.snap, value: currentIndex)
        .accessibilityHidden(true)
    }
}

// MARK: - Action bar

/// Back · Skip · Next, as three separate panes of glass floating over the question.
///
/// This is the one place in the runner where the pieces really are separate glass, so they
/// share a `MedxGlassGroup` and carry `medxGlassID`s: Skip then arrives by flowing out of the
/// Next button and leaves by flowing back into it, and Next becoming Finish is the same shape
/// changing its mind rather than one label cross-fading into another.
///
/// Nothing here uses `.interactive()` glass. Inside a `Button` label the effect takes the touch
/// and the button stops firing — that is what broke the flashcard close button — so press
/// feedback comes from `BouncyButtonStyle` and the glass is inert.
///
/// There used to be a `hint` above the row: "Answer to reveal the explanation", shown on every
/// unanswered question of every revision sitting. A Next button that is visibly disabled has
/// already said it, and saying it again forty times a paper is what made the bar feel like a
/// tutorial. Gone, along with the fourth pane of glass it needed.
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

    /// Finishing is a different act from advancing, so it is a different colour. Green for the
    /// end of a block or a paper, the app's accent for one more question.
    private var advanceHue: Color {
        isLastQuestion ? MedxTheme.successGreen : MedxTheme.accent
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
        .animation(reduceMotion ? nil : MedxMotion.snap, value: showSkip)
        .animation(reduceMotion ? nil : MedxMotion.snap, value: isLastQuestion)
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
        .buttonStyle(BouncyButtonStyle())
        .disabled(!canGoBack)
        .opacity(canGoBack ? 1 : 0.45)
        .accessibilityLabel("Previous question")
    }

    private var skipButton: some View {
        Button {
            onSkip()
        } label: {
            Text("Skip")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 58, minHeight: 50)
                .medxSurface(
                    Capsule(style: .continuous),
                    MedxSurfaceSpec(
                        material: .glass(clear: false),
                        fill: MedxInk.field
                    )
                )
                .contentShape(Capsule(style: .continuous))
                .medxGlassID("runner.skip", in: glass)
        }
        .buttonStyle(BouncyButtonStyle())
        .accessibilityLabel("Skip question")
    }

    private var advanceButton: some View {
        Button {
            onAdvance()
        } label: {
            HStack(spacing: 7) {
                Text(advanceLabel)
                    .font(.headline.weight(.semibold))
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
                    fill: canAdvance ? advanceHue.opacity(0.24) : MedxInk.field,
                    tint: canAdvance ? advanceHue : nil,
                    strokeHue: canAdvance ? advanceHue : nil,
                    strokeOpacity: 0.55,
                    strokeWidth: canAdvance ? 1.2 : 0.5,
                    shadowOpacity: canAdvance ? 0.14 : 0,
                    shadowRadius: 12,
                    shadowY: 5
                )
            )
            .contentShape(Capsule(style: .continuous))
            .medxGlassID("runner.advance", in: glass)
        }
        .buttonStyle(BouncyButtonStyle())
        .disabled(!canAdvance)
        .accessibilityLabel(advanceLabel)
    }
}
