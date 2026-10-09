import SwiftUI
import UIKit

// MARK: - The candy palette
//
// Lifted from the PWA's `src/styles/tokens.css`, which is the design the two apps now
// share. The one rule that makes a loud palette navigable is carried over with it:
// **colour is assigned, never decorative** — a destination owns exactly one hue and keeps
// it on its header, its chips, its progress bars and its tile on Home.
//
// Every hue is a *dynamic* colour rather than a literal, so Dark Mode still works without
// a second palette: on black a mid saturation reads muddy, so the dark variant is pushed
// brighter, exactly as `[data-theme='dark']` does in the stylesheet. Semantic meaning —
// correct, wrong, ungraded — stays with `MedxTheme`'s system colours and is not re-hued
// here; these are wayfinding, not status.

public enum MedxCandy {
    // One accent (Sri, 9 Oct 2026: no pink + blue + purple + lime mix). The palette's names stay
    // so every call site keeps compiling, but each wayfinding hue now resolves to the accent
    // chosen in Settings, and the two that carry meaning resolve to their semantic colour:
    // mint is "done / correct" (system green) and tangerine is "streak / attention" (orange).
    public static var pink: Color { MedxTheme.accent }
    public static var lime: Color { MedxTheme.accent }
    public static var violet: Color { MedxTheme.accent }
    public static var blue: Color { MedxTheme.accent }
    public static var tangerine: Color { MedxTheme.accent }
    public static var mint: Color { MedxTheme.successGreen }
    public static var butter: Color { MedxTheme.accent }
    /// Sri's duel colour: the accent. Mathu's is the one other hue the app keeps (see
    /// `Profile.duelFill`), because a duel is two players on one row.
    public static var sky: Color { MedxTheme.accent }

    public static var pinkSoft: Color { wash(MedxTheme.accent) }
    public static var limeSoft: Color { wash(MedxTheme.accent) }
    public static var violetSoft: Color { wash(MedxTheme.accent) }
    public static var blueSoft: Color { wash(MedxTheme.accent) }
    public static var tangerineSoft: Color { wash(MedxTheme.accent) }
    public static var mintSoft: Color { wash(MedxTheme.successGreen) }
    public static var butterSoft: Color { wash(MedxTheme.accent) }
    public static var skySoft: Color { wash(MedxTheme.accent) }

    /// The soft version of a hue: a light alpha wash of it in either appearance.
    private static func wash(_ hue: Color) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hue).resolvedColor(with: traits)
                .withAlphaComponent(traits.userInterfaceStyle == .dark ? 0.18 : 0.14)
        })
    }

    // MARK: Builders

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? rgb(dark) : rgb(light)
        })
    }

    /// A soft wash: the literal tint in light mode, an alpha wash of the hue itself in
    /// dark. That is what keeps a lime chip lime on black instead of turning it grey.
    private static func soft(light: UInt32, dark: UInt32, darkAlpha: CGFloat) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? rgb(dark).withAlphaComponent(darkAlpha)
                : rgb(light)
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

    // MARK: Legibility

    /// The label colour for anything filled *solid* with a candy hue.
    ///
    /// Fixed rather than appearance-dependent, and deliberately not `.systemBackground`: every
    /// hue here is light in **both** appearances — that is what makes them candy — so a label
    /// that inverted with the appearance would put white on lime. Near-black rather than pure
    /// black so it reads as ink on the hue rather than as a hole in it.
    public static let onSolid = Color(red: 0.08, green: 0.07, blue: 0.06)

    /// Ink for a label on a solid fill of `hue`: near-black on a light hue (a teal, green or
    /// orange accent), white on a dark one (blue, indigo, purple).
    public static func ink(on hue: Color) -> Color {
        Color(uiColor: UIColor { traits in
            let base = UIColor(hue).resolvedColor(with: traits)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard base.getRed(&r, green: &g, blue: &b, alpha: &a) else { return .white }
            let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            return luminance > 0.62 ? UIColor(red: 0.08, green: 0.07, blue: 0.06, alpha: 1) : .white
        })
    }

    /// How far a candy hue has to be pulled toward the label colour to be legible on its
    /// *own* soft wash — 52% hue, 48% label.
    ///
    /// The number is measured rather than guessed, and the measurement came from the PWA:
    /// butter on butter-soft was 1.25:1, so the glyph was simply invisible in light mode.
    /// 52% is the point where the worst of the eight hues clears 3:1 with margin. It works
    /// in both appearances for one reason — in dark mode the label colour is white, so the
    /// same mix *brightens* the hue instead of darkening it.
    ///
    /// 3:1 is the floor for a non-text graphic, which is what these are: icon glyphs inside
    /// a 34–44pt chip.
    public static func onSoft(_ hue: Color) -> Color {
        Color(uiColor: UIColor { traits in
            let base = UIColor(hue).resolvedColor(with: traits)
            let ink = UIColor.label.resolvedColor(with: traits)
            return mix(base, ink, amount: 0.48, traits: traits)
        })
    }

    private static func mix(
        _ a: UIColor,
        _ b: UIColor,
        amount: CGFloat,
        traits: UITraitCollection
    ) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        guard a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa),
              b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        else { return a }
        let t = min(max(amount, 0), 1)
        return UIColor(
            red: ar + (br - ar) * t,
            green: ag + (bg - ag) * t,
            blue: ab + (bb - ab) * t,
            alpha: aa + (ba - aa) * t
        )
    }
}

// MARK: - Category icon colours

/// The per-feature colours, kept for category icon tiles only (the Library grid, Home's quick
/// tiles). Sri, 9 Oct 2026: the one-accent rule covers buttons, selection, progress and
/// backgrounds, never the icons that tell one door from another. These are the candy values
/// the app shipped with before the accent pass.
public enum MedxIconHue {
    public static let pink = tone(light: 0xFF4D8D, dark: 0xFF3D85)
    public static let lime = tone(light: 0x8BC34A, dark: 0xC2F53F)
    public static let violet = tone(light: 0x8B5CF6, dark: 0x9B6CFF)
    public static let purple = tone(light: 0xA855F7, dark: 0xB57BFF)
    public static let blue = tone(light: 0x3D7DFF, dark: 0x4B86FF)
    public static let tangerine = tone(light: 0xFF8A3D, dark: 0xFF9440)
    public static let teal = tone(light: 0x14B8A6, dark: 0x17E0BB)
    public static let yellow = tone(light: 0xF5B800, dark: 0xFFDF55)
    public static let sky = tone(light: 0x1EA7E1, dark: 0x3AD3FF)

    private static func tone(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

// MARK: - Sections

/// A destination and the one hue it owns, mirroring the `--sec-*` aliases in the PWA's
/// stylesheet. Screens read a section, never a raw candy value, so re-hueing a whole area
/// of the app is a one-line change here.
public enum MedxSection: String, CaseIterable, Identifiable, Sendable {
    case home, qbank, tests, cards, videos, vod, library, duel, custom

    public var id: String { rawValue }

    public var fill: Color {
        switch self {
        case .home, .duel: return MedxCandy.pink
        case .qbank, .custom: return MedxCandy.lime
        case .tests: return MedxCandy.tangerine
        case .cards: return MedxCandy.butter
        case .videos: return MedxCandy.violet
        case .vod: return MedxCandy.blue
        case .library: return MedxCandy.mint
        }
    }

    public var soft: Color {
        switch self {
        case .home, .duel: return MedxCandy.pinkSoft
        case .qbank, .custom: return MedxCandy.limeSoft
        case .tests: return MedxCandy.tangerineSoft
        case .cards: return MedxCandy.butterSoft
        case .videos: return MedxCandy.violetSoft
        case .vod: return MedxCandy.blueSoft
        case .library: return MedxCandy.mintSoft
        }
    }

    /// The hue pulled far enough toward the label colour to sit on its own `soft` wash.
    public var onSoft: Color { MedxCandy.onSoft(fill) }

    public var sticker: String {
        switch self {
        case .home: return "wave"
        case .qbank: return "brain"
        case .tests: return "trophy"
        case .cards: return "cards"
        case .videos: return "clapper"
        case .vod: return "satellite"
        case .library: return "filebox"
        case .duel: return "bolt"
        case .custom: return "memo"
        }
    }

    /// The SF Symbol that stands for this destination.
    ///
    /// Symbols, not the Fluent stickers, are what the app's *chrome* is built from: they take
    /// the section hue, scale with Dynamic Type, switch weight with the surrounding font and
    /// carry a real accessibility name — none of which a WebP image does. The stickers stay
    /// where a picture is the content rather than the label: profile marks, empty states and
    /// the end of a sitting.
    public var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .qbank: return "books.vertical.fill"
        case .tests: return "list.clipboard.fill"
        case .cards: return "rectangle.stack.fill"
        case .videos: return "play.rectangle.fill"
        case .vod: return "antenna.radiowaves.left.and.right"
        case .library: return "square.grid.2x2.fill"
        case .duel: return "bolt.fill"
        case .custom: return "slider.horizontal.3"
        }
    }

    public var eyebrow: String {
        switch self {
        case .home: return "Today"
        case .qbank: return "Two banks"
        case .tests: return "Marrow · FMGE"
        case .cards: return "High-yield visuals"
        case .videos: return "ARISE · recorded classes"
        case .vod: return "ARISE · all recordings"
        case .library: return "Everything else"
        case .duel: return "Head to head"
        case .custom: return "Your mixes"
        }
    }
}

// MARK: - Duel colours
//
// Faceoff is the one exception to "a destination owns one accent": what the screen is
// *about* is which of the two of them answered what, so it carries both player colours and
// the split between them is the wayfinding.

public extension Profile {
    /// Mathu runs hot, Sri runs electric. Sri's is deliberately not their profile blue —
    /// see the note on `MedxCandy.sky`.
    var duelFill: Color {
        id == Profile.graveyard.id ? MedxTheme.warningOrange : MedxTheme.accent
    }

    var duelSoft: Color {
        id == Profile.graveyard.id ? MedxTheme.warningOrange.opacity(0.16) : MedxCandy.skySoft
    }

    /// The sticker that stands in for a player on a lobby card or a reveal row.
    var sticker: String {
        id == Profile.graveyard.id ? "skull" : "atom"
    }

    /// The line under their name in the lobby.
    var tag: String {
        id == Profile.graveyard.id ? "buried in books" : "in superposition"
    }
}

// MARK: - Where a sitting came from

public extension RunnerPayload {
    /// Which palette a sitting wears.
    ///
    /// The runner is the one screen reachable from four different places, so it takes its
    /// colour from the paper rather than owning one: a Marrow grand paper stays tangerine all
    /// the way through to its review, and a duel review stays pink.
    var section: MedxSection {
        switch kind {
        case "test", "series": return .tests
        case "custom": return .custom
        case "duel": return .duel
        default: return .qbank
        }
    }
}

public extension MedxAttemptKind {
    /// The hue an activity-log row wears, so the log reads as a trail across the five
    /// destinations rather than as an undifferentiated list.
    var hue: Color {
        switch self {
        case .qbank: return MedxCandy.lime
        case .test: return MedxCandy.tangerine
        case .series: return MedxCandy.tangerine
        case .custom: return MedxCandy.lime
        case .duel: return MedxCandy.pink
        }
    }

    static func hue(_ raw: String) -> Color {
        MedxAttemptKind(rawValue: raw)?.hue ?? MedxCandy.mint
    }
}


// MARK: - Ambient backdrop
//
// Liquid Glass needs something behind it. The first glass pass in this app put translucent panes
// over flat grey and got haze, because there was nothing to refract; the fix then was to take the
// glass off content, which was right. What iOS 26 still wants is colour *under the chrome* — the
// navigation bar, the toolbar buttons and the floating tab bar are glass whether the app asks for
// it or not, and over a flat background they read as grey bands.
//
// So each screen gets one soft wash of its section's hue, pinned to the top of the page and fading
// to the grouped background a third of the way down. It is drawn once, it never animates, and it
// never sits on a card: content stays opaque on top of it, exactly as before. The bars are what
// sample it, which is the job glass is for.

public extension MedxSection {
    /// The second hue in a section's wash — a neighbour on the wheel, so the wash reads as light
    /// rather than as a flag.
    var partner: Color {
        switch self {
        case .home: return MedxCandy.violet
        case .qbank: return MedxCandy.mint
        case .custom: return MedxCandy.butter
        case .tests: return MedxCandy.pink
        case .cards: return MedxCandy.tangerine
        case .videos: return MedxCandy.blue
        case .vod: return MedxCandy.sky
        case .library: return MedxCandy.sky
        case .duel: return MedxCandy.sky
        }
    }
}

public struct MedxBackdrop: View {
    private let section: MedxSection
    private let intensity: Double

    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    public init(section: MedxSection, intensity: Double = 1) {
        self.section = section
        self.intensity = intensity
    }

    public var body: some View {
        // Flat: no wash at all (Sri, 9 Oct 2026: no gradient behind sheets and pages). The bars'
        // glass and the cards' own surfaces give the depth.
        ZStack(alignment: .top) {
            MedxSurface.groupedBackground
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

public extension View {
    /// The page background for a screen that belongs to `section`: the grouped background with
    /// the section's wash at the top. Replaces `.background(MedxSurface.groupedBackground…)`.
    func medxBackdrop(_ section: MedxSection, intensity: Double = 1) -> some View {
        background { MedxBackdrop(section: section, intensity: intensity) }
    }
}

// MARK: - Ink on a hue

public extension Color {
    /// Whether this colour, resolved in `scheme`, is light enough that text on it should be dark.
    /// The candy palette has both kinds — lime and butter want ink, violet and pink want white.
    func medxIsLight(in scheme: ColorScheme) -> Bool {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let resolved = UIColor(self).resolvedColor(with: traits)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard resolved.getRed(&r, green: &g, blue: &b, alpha: &a) else { return false }
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance > 0.62
    }

    /// Ink for a glyph or a label set on a solid fill of this colour.
    func medxInk(in scheme: ColorScheme) -> Color {
        medxIsLight(in: scheme) ? MedxCandy.onSolid : .white
    }
}
