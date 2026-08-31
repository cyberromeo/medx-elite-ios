import SwiftUI
import UIKit

// MARK: - The design system
//
// One file for what a surface is made of, what a number looks like, how round a corner is and how
// fast anything moves. Four rules, and every one of them is a reaction to something this app got
// wrong twice:
//
//   1. **Black with nothing on it.** The page is `#000` and there is no gradient behind it. The
//      section-hued bloom that used to sit there existed to say which tab you were on, which the
//      tab bar already says in the same colour — decoration that encodes nothing, composited under
//      every scroll on 36 screens.
//   2. **A surface is one fill.** No border, no rim gradient, no shadow. On an OLED black page the
//      step from `#000` to `#0E0E11` is legible on its own, and it costs one draw. The previous
//      pass painted fill + hairline + gradient rim + shadow on all 82 surfaces, and the shadow was
//      invisible on black.
//   3. **Colour means outcome, never location.** Correct, wrong, pending. The candy palette in
//      `MedxSections.swift` has exactly one consumer left — the tab tint.
//   4. **Three type voices, mechanically assigned.** A number is always `MedxType.figure`, a
//      category is always the Tag voice, everything else is prose. See `MedxType`.
//
// Glass is not here. It lives in `MedxGlass.swift` and is allowed in three places, listed there.

public enum MedxDS {

    // MARK: Surfaces

    /// The page. `#000` in dark — on an OLED panel the pixels are simply off.
    public static let page = solid(dark: 0x000000, light: 0xFFFFFF)

    /// A list cell. One step off the page, which in dark is one step up.
    public static let row = solid(dark: 0x0F0F13, light: 0xFFFFFF)

    /// A card, or the content of a sheet — something that is *not* in a list.
    public static let raised = solid(dark: 0x1A1A20, light: 0xF2F2F7)

    /// A control at rest: a field, an unselected segment, a monogram, a disabled button.
    ///
    /// The three dark steps are 15, 11 and 12 units apart. That is finer than the system's dark stack
    /// (`#000` → `#1C1C1E` → `#2C2C2E`, 28 and 16 apart) because the whole point of this palette is to
    /// stay *near* black, and coarser than the last attempt's 13-8-6, where a tile inside a card was
    /// indistinguishable from it. With no border and no shadow to help — see rule 2 — the step is the
    /// only thing separating two surfaces, so it has to be a real one.
    public static let sunken = solid(dark: 0x26262E, light: 0xE9E9EF)

    /// Separators only. Never a card outline — see rule 2.
    public static let line = wash(dark: 0xFFFFFF, darkAlpha: 0.08, light: 0x000000, lightAlpha: 0.09)

    // MARK: Outcome
    //
    // The only colours allowed inside a row. Deliberately the system's own greens and reds rather
    // than candy: these are status, and status has to survive being the third colour on a row of
    // small cells.

    public static let correct = Color(uiColor: .systemGreen)
    public static let wrong = Color(uiColor: .systemRed)
    public static let warn = Color(uiColor: .systemOrange)
    /// Answered but not yet scored, and the resting state of a cell nobody has reached.
    public static let pending = wash(dark: 0xFFFFFF, darkAlpha: 0.16, light: 0x000000, lightAlpha: 0.14)

    // MARK: Geometry
    //
    // Nothing sharp. Every rectangle is `.continuous`, every control is a `Capsule`, and nothing is
    // tighter than `control` — except an answer-sheet cell, which is 6pt across and has no visible
    // corner to be sharp about.

    /// A card, and a list row's background.
    public static let card: CGFloat = 22
    /// A control: a field, a segment, a small tile.
    public static let control: CGFloat = 14
    /// Floating chrome — the runner's HUD, a bottom bar.
    public static let hud: CGFloat = 26

    public static func shape(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    /// The page's horizontal margin, matching what `List` insets a plain row by.
    public static let gutter: CGFloat = 16

    // MARK: Motion
    //
    // Three curves, and one rule that matters more than the curves: **animate transforms and
    // opacity, never a blur, a material or a gradient.** That rule is why the last pass felt slow —
    // it animated glass.

    /// A state change the finger asked for: a segment switching, Next becoming Finish.
    public static let snap = Animation.snappy(duration: 0.24, extraBounce: 0.02)

    /// Something arriving or leaving: an explanation, a sheet's content, the answer sheet filling.
    public static let settle = Animation.spring(response: 0.40, dampingFraction: 0.86)

    /// Press feedback and small glyph pops. Stiff enough to read as contact rather than as delay.
    public static let pop = Animation.interpolatingSpring(stiffness: 340, damping: 24)

    // MARK: Builders

    private static func solid(dark: UInt32, light: UInt32) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) })
    }

    private static func wash(
        dark: UInt32,
        darkAlpha: CGFloat,
        light: UInt32,
        lightAlpha: CGFloat
    ) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? rgb(dark).withAlphaComponent(darkAlpha)
                : rgb(light).withAlphaComponent(lightAlpha)
        })
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Three voices
//
// The app used to have one: SF Text at five sizes, which is why every screen read the same. Three
// now, and the assignment is a rule rather than a judgement call at each call site:
//
//   * **Figure** — every number. Rounded, semibold, monospaced digits. This app is almost entirely
//     numbers, and a column of them that jitters as it updates is the single thing that makes a
//     dashboard feel cheap. Rounded because it is the one Apple face with warmth in it.
//   * **Prose** — titles, question stems, explanations. The system text face, nothing exotic.
//   * **Tag** — the *one* category a row carries: its subject, its bank, its block. Small, tracked,
//     uppercased. Never used for anything that is not a category, because that is what turns a
//     signal into decoration.
//
// No font files, so no binary cost and no licence: `.rounded` and `.default` are both SF.

public enum MedxType {

    // MARK: Figure

    /// A number, at a size that still tracks Dynamic Type.
    ///
    /// `UIFontMetrics` rather than a text style because the sizes wanted here (52pt for Home's
    /// count) have no text style near them, and a frozen point size would ignore the Larger Text
    /// setting entirely. Capped at 1.6× so a three-digit hero cannot push the sheet under it off
    /// screen. Same approach as `HTMLRichTextView.resolvedFontSize`.
    public static func figure(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        let scaled = UIFontMetrics(forTextStyle: .body).scaledValue(for: size)
        let capped = min(max(scaled, size), size * 1.6)
        return .system(size: capped, weight: weight, design: .rounded).monospacedDigit()
    }

    /// Home's answer count. The largest number in the app.
    public static var hero: Font { figure(52, weight: .bold) }
    /// A screen's lead figure — "352" over Tests, "62" over the countdown.
    public static var display: Font { figure(28, weight: .bold) }
    /// A row's trailing value: a score, a count, a duration.
    public static var value: Font { figure(16) }
    /// A row's leading figure: a paper's month, a subject's code, an option's letter.
    public static var lead: Font { figure(14, weight: .bold) }
    /// The runner's clock.
    public static var clock: Font { figure(19, weight: .bold) }

    // MARK: Prose

    /// A row's title.
    public static let title = Font.system(.subheadline, design: .default, weight: .semibold)
    /// A row's second line, and body copy.
    public static let body = Font.system(.footnote, design: .default)
    /// A section's heading, where it is words rather than a category.
    public static let heading = Font.system(.headline, design: .default, weight: .semibold)

    // MARK: Tag

    /// The category voice. Apply with `medxTag()`, which adds the tracking and the case.
    public static let tag = Font.system(.caption2, design: .default, weight: .medium)
}

public extension View {
    /// The Tag voice, whole: face, tracking, upper case and the secondary ink, in one call so no
    /// screen can half-apply it.
    func medxTag() -> some View {
        self
            .font(MedxType.tag)
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

// MARK: - The page

public extension View {
    /// Black, and nothing else.
    ///
    /// This replaces `medxPage(_ section:intensity:)`, which did two expensive things: it painted a
    /// full-screen radial gradient of the section's hue behind every screen, and it applied
    /// `scrollEdgeEffectStyle(.soft, for: .all)` — a live blur at all four scroll edges, recomputed
    /// every frame of every scroll, on 36 screens. The gradient said which tab you were on, which the
    /// tab bar says in the same colour; the blur was invisible on `#000`.
    ///
    /// It takes no section argument because there is nothing left for a section to change here. Where
    /// a screen still needs its hue it reads `MedxSection.fill` directly, and there is one such place:
    /// the tab tint.
    func medxPage() -> some View {
        background(MedxDS.page.ignoresSafeArea())
    }
}

// MARK: - Press

/// Contact, as a transform.
///
/// The style it replaces animated `scale 0.985` over `easeOut(0.12)`, which is below the threshold
/// where a press registers as having happened at all. 0.97 on a stiff spring does, and a transform is
/// the cheapest thing the compositor can be asked for.
///
/// For tappable things *outside* a `List`. Inside one, the system's own row highlight already does
/// this and doing both reads as a double-tap.
public struct MedxPressStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Pressable(configuration: configuration)
    }

    /// A nested `View` rather than inline modifiers on `configuration.label`, because
    /// `accessibilityReduceMotion` is an `@Environment` read and a `ButtonStyle` is not a `View`.
    private struct Pressable: View {
        let configuration: ButtonStyleConfiguration

        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.85 : 1)
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
                .animation(
                    reduceMotion ? .easeOut(duration: 0.12) : MedxDS.pop,
                    value: configuration.isPressed
                )
        }
    }
}
