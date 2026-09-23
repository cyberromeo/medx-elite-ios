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

// MARK: - A glass button

/// A round control in the runner chrome, on the iOS 26 SDK's glass button styles at Apple's own
/// HIG control metrics — `controlSize` is the size lever, so the buttons come out the native
/// size, not a cramped glyph. `prominent` fills the glass with `tint` (the blue Next); every
/// runner button is a circle now, so the chrome reads as one family.
struct RunnerCircleButton: View {
    let systemName: String
    var prominent: Bool = false
    var tint: Color? = nil
    var foreground: Color = .primary
    var controlSize: ControlSize = .regular
    var circle: Bool = false
    var bounceOn: Bool = false
    let action: () -> Void

    /// Glyph point size per control size — chosen so the SF Symbol reads at a comfortable weight
    /// inside the glass Apple lays around it.
    private var iconPointSize: CGFloat {
        switch controlSize {
        case .mini, .small: return 15
        case .regular: return 17
        case .large: return 21
        case .extraLarge: return 26
        @unknown default: return 17
        }
    }

    /// iOS 17 has no glass control metrics to lean on, so the ink fallback sizes its own circle.
    private var fallbackDiameter: CGFloat {
        switch controlSize {
        case .mini, .small: return 44
        case .regular: return 48
        case .large: return 54
        case .extraLarge: return 64
        @unknown default: return 48
        }
    }

    private var glyph: some View {
        Image(systemName: systemName)
            .font(.system(size: iconPointSize, weight: .semibold))
            .symbolEffect(.bounce, value: bounceOn)
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            // Inline rather than in an `@available` helper: `.agents/availability_audit.py`
            // stands in for the compiler here and only recognises an `if #available` block as a
            // guard. Exactly one button style per branch — layering `.glass` then
            // `.glassProminent` would leave the innermost (`.glass`) winning.
            if prominent {
                shaped(
                    Button(action: action) { glyph.foregroundStyle(foreground) }
                        .buttonStyle(.glassProminent)
                        .tint(tint ?? MedxTheme.accent)
                )
                .controlSize(controlSize)
            } else {
                shaped(
                    Button(action: action) { glyph.foregroundStyle(foreground) }
                        .buttonStyle(.glass)
                )
                .controlSize(controlSize)
            }
        } else {
            inkButton
        }
    }

    /// A full circle only where asked; otherwise the glass style's own default rounded shape.
    /// `.buttonBorderShape` is iOS 17 API, so this needs no availability island of its own.
    @ViewBuilder
    private func shaped<V: View>(_ button: V) -> some View {
        if circle {
            button.buttonBorderShape(.circle)
        } else {
            button
        }
    }

    /// iOS 17 fallback: an opaque ink pane in the same shape the glass draws on 26.
    private var inkButton: some View {
        Button(action: action) {
            glyph
                .foregroundStyle(prominent ? .white : foreground)
                .frame(width: fallbackDiameter, height: fallbackDiameter)
                .background {
                    if circle {
                        Circle().fill(prominent ? (tint ?? MedxTheme.accent) : MedxDS.sunken)
                    } else {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(prominent ? (tint ?? MedxTheme.accent) : MedxDS.sunken)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(MedxPressStyle())
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
    /// iPad sizes the chrome up — the close/bookmark circles go `.large` rather than `.regular`.
    let isPad: Bool
    let onClose: () -> Void
    let onNavigator: () -> Void
    let onBookmark: () -> Void

    private var circleSize: ControlSize { isPad ? .extraLarge : .large }

    private var fraction: Double {
        guard capacitySeconds > 0 else { return 0 }
        return min(max(Double(remainingSeconds) / Double(capacitySeconds), 0), 1)
    }

    var body: some View {
        VStack(spacing: 10) {
            // The progress bar rides the very top, full width, just under the status bar — the
            // reference's layout. The controls sit on their own row below it.
            RunnerTimeBar(fraction: fraction, isPaused: isPaused)

            MedxGlassGroup(spacing: 14) {
                HStack(spacing: 12) {
                    RunnerCircleButton(
                        systemName: "xmark",
                        foreground: .secondary,
                        controlSize: circleSize,
                        circle: true,
                        action: onClose
                    )
                    .accessibilityLabel("Close sitting")

                    Spacer(minLength: 8)

                    if let blockLabel {
                        MedxBadge(blockLabel).fixedSize()
                    }

                    RunnerCircleButton(
                        systemName: isBookmarked ? "bookmark.fill" : "bookmark",
                        tint: isBookmarked ? MedxDS.warn : nil,
                        foreground: isBookmarked ? MedxDS.warn : .secondary,
                        controlSize: circleSize,
                        circle: true,
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
    /// The centre `3/50` counter. Dropped on iPad, where the HUD already carries it at the
    /// top-right — one question number on screen, not two.
    let showsCounter: Bool
    /// iPad groups the arrows on the right and sizes them up to `.extraLarge`.
    let isPad: Bool
    let onBack: () -> Void
    let onNavigator: () -> Void
    let onAdvance: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var controlSize: ControlSize { isPad ? .extraLarge : .large }

    private var backButton: some View {
        RunnerCircleButton(
            systemName: "chevron.left",
            foreground: canGoBack ? .primary : .secondary,
            controlSize: controlSize,
            circle: true,
            action: onBack
        )
        .disabled(!canGoBack)
        .opacity(canGoBack ? 1 : 0.45)
        .accessibilityLabel("Previous question")
    }

    private var nextButton: some View {
        RunnerCircleButton(
            systemName: isLastQuestion ? "checkmark" : "chevron.right",
            prominent: true,
            tint: isLastQuestion ? MedxDS.correct : MedxTheme.accent,
            foreground: .white,
            controlSize: controlSize,
            circle: true,
            bounceOn: isLastQuestion,
            action: onAdvance
        )
        .disabled(!canAdvance)
        .opacity(canAdvance ? 1 : 0.45)
        .accessibilityLabel(isLastQuestion ? "Finish" : "Next question")
    }

    var body: some View {
        HStack(spacing: 12) {
            if isPad {
                // Both arrows in the right corner, Previous immediately left of Next.
                Spacer(minLength: 8)
                backButton
                nextButton
            } else {
                backButton
                Spacer(minLength: 8)
                if showsCounter {
                    RunnerCounter(number: number, total: total, onTap: onNavigator)
                    Spacer(minLength: 8)
                }
                nextButton
            }
        }
        .padding(.horizontal, MedxGlass.floatInset)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .animation(reduceMotion ? nil : MedxDS.snap, value: isLastQuestion)
    }
}
