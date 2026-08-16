import SwiftUI

public struct ProgressRingView: View {
    public var progress: Double // 0.0 ... 1.0
    public var strokeWidth: CGFloat = 10
    public var size: CGFloat = 80
    public var gradient: LinearGradient = LinearGradient(
        colors: [MedxTheme.primaryBlue, MedxTheme.cyanAccent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    public var centerContent: AnyView?

    @State private var animatedProgress: Double = 0

    public init(
        progress: Double,
        strokeWidth: CGFloat = 10,
        size: CGFloat = 80,
        gradient: LinearGradient = LinearGradient(
            colors: [MedxTheme.primaryBlue, MedxTheme.cyanAccent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ),
        centerContent: AnyView? = nil
    ) {
        self.progress = min(max(progress, 0.0), 1.0)
        self.strokeWidth = strokeWidth
        self.size = size
        self.gradient = gradient
        self.centerContent = centerContent
    }

    public var body: some View {
        ZStack {
            // Background track
            Circle()
                .stroke(
                    Color.primary.opacity(0.06),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )

            // Animated progress arc
            Circle()
                .trim(from: 0, to: CGFloat(animatedProgress))
                .stroke(
                    gradient,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Glow effect at the leading edge
            if animatedProgress > 0.02 {
                Circle()
                    .trim(from: max(0, CGFloat(animatedProgress) - 0.01), to: CGFloat(animatedProgress))
                    .stroke(
                        gradient,
                        style: StrokeStyle(lineWidth: strokeWidth + 4, lineCap: .round)
                    )
                    .blur(radius: 4)
                    .opacity(0.4)
                    .rotationEffect(.degrees(-90))
            }

            if let center = centerContent {
                center
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.75).delay(0.2)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                animatedProgress = newValue
            }
        }
    }
}
