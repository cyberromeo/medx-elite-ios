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
                    Color.primary.opacity(0.08),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )

            // Animated progress
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    gradient,
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8, dampingFraction: 0.7), value: progress)

            if let center = centerContent {
                center
            }
        }
        .frame(width: size, height: size)
    }
}
