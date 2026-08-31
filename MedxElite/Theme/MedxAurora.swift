import SwiftUI

// MARK: - Backdrop
//
// The reason the app's first pass at glass failed. Liquid Glass is a lens: it bends whatever
// is behind it, picks up its colour and throws a specular edge. Put it over
// `systemGroupedBackground` — one flat grey — and there is nothing to bend, so every panel
// comes out the same dull haze and the only thing glass has bought is a blur pass per card.
//
// So the backdrop comes first. Each destination washes its own page in the hue it already
// owns (`MedxSection.fill`), as two soft radial blooms plus a cool one from the chosen accent.
// Deliberately quiet: at these opacities it reads as depth rather than as colour, and the
// grouped background is still what you would call the page. It is what makes a glass card on
// the QBank look lime-lit and the same card on Tests look warm, with no per-screen styling.
//
// Static on purpose — no animation, no `TimelineView`. A drifting gradient behind text you
// are trying to read is exactly the kind of thing that gets an app called tiring, and this
// sits behind every screen in the app.

public struct MedxAurora: View {
    private let section: MedxSection
    private let intensity: Double

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// `intensity` scales the whole wash. The runner turns it down, because a question stem is
    /// the densest text in the app and wants the calmest page behind it.
    public init(section: MedxSection, intensity: Double = 1) {
        self.section = section
        self.intensity = max(intensity, 0)
    }

    public var body: some View {
        ZStack {
            MedxSurface.groupedBackground

            // Under Reduce Transparency the surfaces above go flat and opaque, so a wash they
            // would have refracted is just stray colour behind solid cards.
            if !reduceTransparency, intensity > 0 {
                bloom(section.fill, x: 0.88, y: 0.02, radius: 520, alpha: dark ? 0.30 : 0.22)
                bloom(section.fill, x: 0.06, y: 0.78, radius: 460, alpha: dark ? 0.17 : 0.13)
                bloom(MedxTheme.accent, x: 0.30, y: 0.30, radius: 420, alpha: dark ? 0.11 : 0.07)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var dark: Bool { scheme == .dark }

    private func bloom(_ hue: Color, x: Double, y: Double, radius: CGFloat, alpha: Double) -> some View {
        RadialGradient(
            colors: [hue.opacity(alpha * intensity), .clear],
            center: UnitPoint(x: x, y: y),
            startRadius: 0,
            endRadius: radius
        )
    }
}

public extension View {
    /// The page treatment every destination wears: the section's wash behind, and the
    /// platform's soft scroll edges above it so content dissolves under the bars.
    func medxPage(_ section: MedxSection, intensity: Double = 1) -> some View {
        self
            .background(MedxAurora(section: section, intensity: intensity))
            .medxScrollEdge()
    }
}
