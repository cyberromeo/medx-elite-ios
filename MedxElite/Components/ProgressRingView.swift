import SwiftUI

/// Circular progress indicator. Solid stroke, rounded caps, no blur halo — the old glow
/// layer drew a second blurred arc on every frame of the animation for no legibility gain.
public struct ProgressRingView: View {
    public var progress: Double // 0.0 ... 1.0
    public var strokeWidth: CGFloat
    public var size: CGFloat
    public var stroke: AnyShapeStyle
    public var centerContent: AnyView?

    @State private var animatedProgress: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        progress: Double,
        strokeWidth: CGFloat = 10,
        size: CGFloat = 80,
        tint: Color = .accentColor,
        centerContent: AnyView? = nil
    ) {
        self.progress = min(max(progress, 0.0), 1.0)
        self.strokeWidth = strokeWidth
        self.size = size
        self.stroke = AnyShapeStyle(tint)
        self.centerContent = centerContent
    }

    public init(
        progress: Double,
        strokeWidth: CGFloat = 10,
        size: CGFloat = 80,
        gradient: LinearGradient,
        centerContent: AnyView? = nil
    ) {
        self.progress = min(max(progress, 0.0), 1.0)
        self.strokeWidth = strokeWidth
        self.size = size
        self.stroke = AnyShapeStyle(gradient)
        self.centerContent = centerContent
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(
                    Color(uiColor: .quaternaryLabel),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )

            Circle()
                .trim(from: 0, to: CGFloat(animatedProgress))
                .stroke(stroke, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            if let centerContent {
                centerContent
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.6)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.35)) {
                animatedProgress = newValue
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}
