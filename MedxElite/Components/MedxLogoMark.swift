import SwiftUI

// MARK: - Glyph
//
// The mark is an "M" whose strokes are an ECG trace: two slanted stems, a middle valley
// that dips below the baseline like a QRS downstroke, and a flat lead-in and lead-out.
// Coordinates live in a 100 × 100 space and are scaled to whatever rect they are given, so
// the same numbers drive the SwiftUI mark and the 1024 px app icon generated from them.

/// The trace, as a stroke-able `Shape`. `trim` on this is what the splash animates.
public struct MedxLogoGlyph: Shape {
    /// Normalised path points, oldest-to-newest along the trace.
    public static let points: [CGPoint] = [
        CGPoint(x: 6, y: 62),
        CGPoint(x: 20, y: 62),
        CGPoint(x: 33, y: 20),
        CGPoint(x: 50, y: 78),
        CGPoint(x: 67, y: 20),
        CGPoint(x: 80, y: 62),
        CGPoint(x: 94, y: 62)
    ]

    public init() {}

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let scaleX = rect.width / 100
        let scaleY = rect.height / 100

        for (index, point) in Self.points.enumerated() {
            let resolved = CGPoint(
                x: rect.minX + point.x * scaleX,
                y: rect.minY + point.y * scaleY
            )
            if index == 0 {
                path.move(to: resolved)
            } else {
                path.addLine(to: resolved)
            }
        }
        return path
    }
}

// MARK: - Mark

/// The app mark, drawn rather than shipped as an image so it stays sharp at every size and
/// can be animated.
///
/// This is the one place in the app that is allowed a glass treatment — a tinted gradient
/// tile, a specular sweep across the top and a rim light. Everywhere *inside* the app the
/// rule from `GlassModifier` still holds: flat semantic surfaces, materials only in
/// `medxBar`. An icon is chrome about the app, not content within it.
public struct MedxLogoMark: View {
    public var size: CGFloat
    /// 0…1 — how much of the trace is drawn. The splash animates this to 1.
    public var trim: CGFloat
    public var showsGlow: Bool

    public init(size: CGFloat = 96, trim: CGFloat = 1, showsGlow: Bool = true) {
        self.size = size
        self.trim = trim
        self.showsGlow = showsGlow
    }

    private var cornerRadius: CGFloat { size * 0.2237 }
    private var lineWidth: CGFloat { size * 0.105 }
    private var inset: CGFloat { size * 0.16 }

    public var body: some View {
        ZStack {
            base
            specular
            glyph
            rim
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(showsGlow ? 0.28 : 0), radius: size * 0.09, y: size * 0.035)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("MedX Elite")
    }

    private var base: some View {
        LinearGradient(
            colors: [
                Color(red: 0.24, green: 0.56, blue: 1.00),
                Color(red: 0.16, green: 0.30, blue: 0.92),
                Color(red: 0.29, green: 0.18, blue: 0.82)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// The lens reflection: a wide, very soft ellipse riding the top edge, plus a bright
    /// pinpoint at the top-leading corner where the light is coming from.
    private var specular: some View {
        ZStack {
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.42), Color.white.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 1.35, height: size * 0.82)
                .offset(y: -size * 0.46)
                .blur(radius: size * 0.045)

            RadialGradient(
                colors: [Color.white.opacity(0.55), Color.white.opacity(0)],
                center: UnitPoint(x: 0.22, y: 0.16),
                startRadius: 0,
                endRadius: size * 0.5
            )
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    private var glyph: some View {
        MedxLogoGlyph()
            .trim(from: 0, to: max(0, min(trim, 1)))
            .stroke(
                LinearGradient(
                    colors: [Color.white, Color.white.opacity(0.86)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
            .padding(inset)
            .shadow(color: Color(red: 0.05, green: 0.08, blue: 0.35).opacity(0.45), radius: size * 0.03, y: size * 0.012)
    }

    /// Hairline rim so the tile has an edge of its own against a dark background.
    private var rim: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.55), Color.white.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: max(0.75, size * 0.012)
            )
            .allowsHitTesting(false)
    }
}

// MARK: - Wordmark

public struct MedxWordmark: View {
    public var size: CGFloat
    public var alignment: HorizontalAlignment

    public init(size: CGFloat = 30, alignment: HorizontalAlignment = .center) {
        self.size = size
        self.alignment = alignment
    }

    public var body: some View {
        VStack(alignment: alignment, spacing: size * 0.1) {
            Text("MedX Elite")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("FMGE PREP")
                .font(.system(size: size * 0.34, weight: .semibold))
                .tracking(size * 0.14)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("MedX Elite, F M G E prep")
    }
}
