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

    /// One height for the whole row — the ✕ / bookmark circles' diameter *and* the timer/counter
    /// capsules' height — so the HUD reads as a single uniform band. A touch taller on iPad.
    private var elementHeight: CGFloat { isPad ? 50 : 44 }

    private var fraction: Double {
        guard capacitySeconds > 0 else { return 0 }
        return min(max(Double(remainingSeconds) / Double(capacitySeconds), 0), 1)
    }

    var body: some View {
        VStack(spacing: 10) {
            // The progress bar rides the very top, full width, just under the status bar — the
            // reference's layout. The controls sit on their own row below it.
            RunnerTimeBar(fraction: fraction, isPaused: isPaused)

            // No `MedxGlassGroup` here on purpose: the `GlassEffectContainer` it wraps the row in
            // was swallowing the ✕'s taps (the bottom action bar, which is *not* in a container,
            // never had the problem). Each control keeps its own glass; they just no longer morph.
            HStack(spacing: 10) {
                RunnerCircleButton(
                    systemName: "xmark",
                    foreground: .secondary,
                    diameter: elementHeight,
                    hitExpansion: 16,
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
                    diameter: elementHeight,
                    bounceOn: isBookmarked,
                    action: onBookmark
                )
                .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark question")

                RunnerTimerBadge(remainingSeconds: remainingSeconds, isPaused: isPaused, height: elementHeight)
                    .fixedSize()

                if showsInlineCounter {
                    RunnerCounter(number: number, total: total, height: elementHeight, onTap: onNavigator)
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
    /// The centre `3/50` counter. Dropped on iPad, where the HUD already carries it at the
    /// top-right — one question number on screen, not two.
    let showsCounter: Bool
    /// iPad groups the arrows on the right and sizes them up to `.extraLarge`.
    let isPad: Bool
    let onBack: () -> Void
    let onNavigator: () -> Void
    let onAdvance: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The action bar's arrows are the primary controls, so a touch larger than the HUD circles,
    /// and larger again on iPad — but nowhere near the oversized glass-metric sizes.
    private var arrowDiameter: CGFloat { isPad ? 60 : 54 }

    private var backButton: some View {
        RunnerCircleButton(
            systemName: "chevron.left",
            foreground: canGoBack ? .primary : .secondary,
            diameter: arrowDiameter,
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
            diameter: arrowDiameter,
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
                    RunnerCounter(number: number, total: total, height: arrowDiameter, onTap: onNavigator)
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
