import SwiftUI

// MARK: - Runner chrome
//
// The sitting screen, redesigned to the reference mockup: a black canvas with a faint dotted grid,
// and native Liquid Glass controls floating over the question. This is the one screen glass is
// actually *for* — chrome floating over content that is already there.
//
//   * `RunnerHUD` at the top: a circular close button, a blue **time-remaining** bar, a circular
//     bookmark, and the countdown pill. On iPad the question counter also rides at the top-right.
//   * `RunnerActionBar` at the bottom: `←  ·  3/50  ·  →`. The counter opens the navigator; the
//     blue circle advances (and becomes the finish/submit action on the last question).
//
// The buttons use the iOS 26 SDK's own Liquid Glass button styles — `.buttonStyle(.glass)` for the
// neutral circles and `.buttonStyle(.glassProminent)` with a blue `.tint` for the primary Next —
// rather than a hand-rolled material, with an ink fallback on iOS 17. The glass goes on the
// `Button`, never on its label: an interactive glass effect inside a label eats the touch and the
// button stops firing.
//
// The progress track that used to live here (`MedxAnswerSheet` at `track` scale) is gone from the
// HUD; the OMR grid still draws in the question navigator and the post-sitting review. What the top
// bar shows now is time, exactly as the mockup annotates it: the block's clock in exam mode, the
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

// MARK: - A glass circle button

/// A round control in the runner chrome. Glass on iOS 26 via the SDK's own button styles; an ink
/// circle on iOS 17. `prominent` fills the glass with `tint` — the blue Next button.
struct RunnerCircleButton: View {
    let systemName: String
    var prominent: Bool = false
    var tint: Color? = nil
    var foreground: Color = .primary
    var diameter: CGFloat = 52
    var bounceOn: Bool = false
    let action: () -> Void

    private var glyph: some View {
        Image(systemName: systemName)
            .font(.system(size: diameter * 0.34, weight: .bold))
            .symbolEffect(.bounce, value: bounceOn)
            .frame(width: diameter, height: diameter)
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            // Exactly one button style per branch — layering `.glass` then `.glassProminent`
            // would leave the innermost (`.glass`) winning, so the prominent Next never filled.
            if prominent {
                Button(action: action) { glyph.foregroundStyle(foreground) }
                    .buttonStyle(.glassProminent)
                    .tint(tint ?? MedxTheme.accent)
                    .buttonBorderShape(.circle)
            } else {
                Button(action: action) { glyph.foregroundStyle(foreground) }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
            }
        } else if prominent {
            // iOS 17 fallback: a solid tinted circle, white glyph — the prominent look without glass.
            Button(action: action) {
                glyph
                    .foregroundStyle(.white)
                    .medxInkCircle(diameter: diameter, tint: tint ?? MedxTheme.accent)
            }
            .buttonStyle(MedxPressStyle())
        } else {
            Button(action: action) {
                glyph
                    .foregroundStyle(foreground)
                    .medxGlassCircle(diameter: diameter)
            }
            .buttonStyle(MedxPressStyle())
        }
    }
}

// MARK: - Time bar

/// The blue bar that drains as the clock does. Not glass — it is a filled track, so it reads as the
/// one solid element between the floating controls, exactly as the mockup draws it. Takes the same
/// red cast the panel used to in the last ten seconds.
struct RunnerTimeBar: View {
    let fraction: Double
    let isLow: Bool
    let isPaused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color {
        if isPaused { return MedxDS.correct }
        return isLow ? MedxDS.wrong : MedxTheme.accent
    }

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
        .animation(reduceMotion ? nil : .linear(duration: 0.9), value: fraction)
        .animation(reduceMotion ? nil : MedxDS.snap, value: isLow)
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
            .frame(minHeight: 40)
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
    /// What the clock was wound to, so the bar can show a fraction.
    let capacitySeconds: Int
    let isPaused: Bool
    let isBookmarked: Bool
    /// iPad: the question counter also rides at the top-right of the HUD.
    let showsInlineCounter: Bool
    let onClose: () -> Void
    let onNavigator: () -> Void
    let onBookmark: () -> Void

    private var isLow: Bool { !isPaused && remainingSeconds <= 10 }

    private var fraction: Double {
        guard capacitySeconds > 0 else { return 0 }
        return min(max(Double(remainingSeconds) / Double(capacitySeconds), 0), 1)
    }

    var body: some View {
        MedxGlassGroup(spacing: 14) {
            HStack(spacing: 12) {
                RunnerCircleButton(
                    systemName: "xmark",
                    foreground: .secondary,
                    diameter: 46,
                    action: onClose
                )
                .accessibilityLabel("Close sitting")

                RunnerTimeBar(fraction: fraction, isLow: isLow, isPaused: isPaused)

                if let blockLabel {
                    MedxBadge(blockLabel).fixedSize()
                }

                RunnerCircleButton(
                    systemName: isBookmarked ? "bookmark.fill" : "bookmark",
                    tint: isBookmarked ? MedxDS.warn : nil,
                    foreground: isBookmarked ? MedxDS.warn : .secondary,
                    diameter: 46,
                    bounceOn: isBookmarked,
                    action: onBookmark
                )
                .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark question")

                RunnerTimerBadge(remainingSeconds: remainingSeconds, isPaused: isPaused)
                    .fixedSize()

                if showsInlineCounter {
                    RunnerCounter(number: number, total: total, onTap: onNavigator)
                        .fixedSize()
                }
            }
        }
        .padding(.horizontal, MedxGlass.floatInset)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

// MARK: - Clock pill

/// The countdown, as digits on a dark glass pill — the `00:57` in the mockup. The draining is now
/// the bar's job, so this is just the exact time, monospaced so it does not twitch.
struct RunnerTimerBadge: View {
    let remainingSeconds: Int
    let isPaused: Bool

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
            .frame(minHeight: 40)
            .modifier(RunnerCapsuleGlass())
            .accessibilityElement()
            .accessibilityLabel(isPaused ? "Answer revealed, timer paused" : "Time remaining \(clock)")
    }
}

// MARK: - Action bar

/// `←  ·  3/50  ·  →`, over the question. Back and the counter are neutral; Next is the one blue,
/// prominent thing on the screen, and it becomes the finish/submit action on the last question.
///
/// No Skip button and no text label, matching the mockup: in exam mode the arrow always advances
/// (skipping is just tapping it), and in revision it stays disabled until the answer is revealed.
struct RunnerActionBar: View {
    let number: Int
    let total: Int
    let isLastQuestion: Bool
    let canGoBack: Bool
    let canAdvance: Bool
    let onBack: () -> Void
    let onNavigator: () -> Void
    let onAdvance: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            RunnerCircleButton(
                systemName: "chevron.left",
                foreground: canGoBack ? .primary : .secondary,
                diameter: 56,
                action: onBack
            )
            .disabled(!canGoBack)
            .opacity(canGoBack ? 1 : 0.45)
            .accessibilityLabel("Previous question")

            Spacer(minLength: 8)

            RunnerCounter(number: number, total: total, onTap: onNavigator)

            Spacer(minLength: 8)

            RunnerCircleButton(
                systemName: isLastQuestion ? "checkmark" : "chevron.right",
                prominent: true,
                tint: isLastQuestion ? MedxDS.correct : MedxTheme.accent,
                foreground: .white,
                diameter: 56,
                bounceOn: isLastQuestion,
                action: onAdvance
            )
            .disabled(!canAdvance)
            .opacity(canAdvance ? 1 : 0.45)
            .accessibilityLabel(isLastQuestion ? "Finish" : "Next question")
        }
        .padding(.horizontal, MedxGlass.floatInset)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .animation(reduceMotion ? nil : MedxDS.snap, value: isLastQuestion)
    }
}
