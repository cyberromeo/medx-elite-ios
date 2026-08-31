import SwiftUI

// MARK: - Backdrop
//
// Pitch black, and one faint glow.
//
// The version of this file before it was a wash: three radial blooms of the section's hue plus a
// cool one from the accent, sitting behind every screen so that glass had something to refract.
// That was the right answer to the wrong question. The app does not put glass on content any
// more — see `Theme/MedxLiquidGlass.swift` — so the two places glass still appears (the runner's
// chrome, and anything presented) refract *real content* underneath them, which is a far better
// thing to bend than a gradient.
//
// What is left is a page. `MedxInk.page` is `#000` in dark, and on an OLED phone that is not a
// colour at all — the pixels are off. Everything above it is opaque, so the black is what gives
// the app its contrast rather than a grey that has to be lit.
//
// One bloom survives, at the top edge only and at 5%: enough that the QBank reads faintly lime
// and Tests faintly warm as you switch tabs, and not enough to stop the page being black. It is
// wayfinding at the threshold of visibility, which is the most a pitch-black app can spend on it.
//
// Static, as before — no `TimelineView`, no animation. A drifting gradient behind text you are
// trying to read is exactly the kind of thing that gets an app called tiring, and this sits
// behind every screen.

public struct MedxAurora: View {
    private let section: MedxSection
    private let intensity: Double

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// `intensity` scales the bloom. The runner passes `0`: a question stem is the densest text
    /// in the app and wants nothing behind it at all.
    public init(section: MedxSection, intensity: Double = 1) {
        self.section = section
        self.intensity = max(intensity, 0)
    }

    public var body: some View {
        ZStack {
            MedxInk.page

            // Under Reduce Transparency the surfaces above are opaque anyway, so a wash they
            // cannot refract is just stray colour behind solid cards.
            if !reduceTransparency, intensity > 0 {
                RadialGradient(
                    colors: [section.fill.opacity(alpha), .clear],
                    center: UnitPoint(x: 0.5, y: -0.06),
                    startRadius: 0,
                    endRadius: 440
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// A touch stronger in light, where the page is white and 5% of a candy hue disappears.
    private var alpha: Double {
        (scheme == .dark ? 0.05 : 0.08) * intensity
    }
}

public extension View {
    /// The page treatment every destination wears: black, the section's own glow at the top
    /// edge, and the platform's soft scroll edges so content dissolves under the bars.
    func medxPage(_ section: MedxSection, intensity: Double = 1) -> some View {
        self
            .background(MedxAurora(section: section, intensity: intensity))
            .medxScrollEdge()
    }
}
