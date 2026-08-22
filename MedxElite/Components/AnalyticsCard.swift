import SwiftUI
import Charts

/// Accuracy across recent sittings. Real data only — the old version drew five invented
/// data points when the student had no attempts, which made an empty account look busy.
public struct AnalyticsCard: View {
    public let attempts: [SittingAttempt]

    public init(attempts: [SittingAttempt]) {
        self.attempts = attempts
    }

    private struct Point: Identifiable {
        let id: Int
        let label: String
        let accuracy: Double
        let attempted: Int
    }

    private var recentAttempts: [SittingAttempt] {
        Array(
            attempts
                .filter { $0.attempted > 0 }
                .sorted { ($0.finishedAt ?? "") < ($1.finishedAt ?? "") }
                .suffix(10)
        )
    }

    private var points: [Point] {
        recentAttempts.enumerated().map { index, attempt in
            Point(
                id: index,
                label: "\(index + 1)",
                accuracy: Double(attempt.score) / Double(max(attempt.attempted, 1)) * 100,
                attempted: attempt.attempted
            )
        }
    }

    private var averageAccuracy: Int {
        let attemptedTotal = attempts.reduce(0) { $0 + $1.attempted }
        guard attemptedTotal > 0 else { return 0 }
        let correctTotal = attempts.reduce(0) { $0 + $1.score }
        return Int((Double(correctTotal) / Double(attemptedTotal) * 100).rounded())
    }

    private var solvedTotal: Int {
        attempts.reduce(0) { $0 + $1.attempted }
    }

    private var trend: Int? {
        guard points.count >= 4 else { return nil }
        let half = points.count / 2
        let earlier = points.prefix(half).map(\.accuracy).reduce(0, +) / Double(half)
        let later = points.suffix(points.count - half).map(\.accuracy).reduce(0, +) / Double(points.count - half)
        return Int((later - earlier).rounded())
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if points.isEmpty {
                emptyState
            } else {
                statsRow
                chart
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medxCard(cornerRadius: 20)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Accuracy")
                .font(.headline)

            Spacer(minLength: 8)

            if let trend, trend != 0 {
                Label(
                    "\(trend > 0 ? "+" : "")\(trend)%",
                    systemImage: trend > 0 ? "arrow.up.right" : "arrow.down.right"
                )
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(trend > 0 ? MedxTheme.successGreen : MedxTheme.warningOrange)
                .accessibilityLabel(trend > 0 ? "Improving by \(trend) percent" : "Down \(abs(trend)) percent")
            } else if !points.isEmpty {
                Text("Last \(points.count) sittings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 20) {
            figure(value: "\(averageAccuracy)%", label: "average")
            figure(value: solvedTotal.formatted(), label: "answered")
            figure(value: "\(attempts.count)", label: "sittings")
            Spacer(minLength: 0)
        }
    }

    private func figure(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    private var chart: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("Sitting", point.id),
                y: .value("Accuracy", point.accuracy)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Sitting", point.id),
                y: .value("Accuracy", point.accuracy)
            )
            .foregroundStyle(Color.accentColor)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.monotone)

            PointMark(
                x: .value("Sitting", point.id),
                y: .value("Accuracy", point.accuracy)
            )
            .foregroundStyle(Color.accentColor)
            .symbolSize(22)
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(MedxSurface.separator)
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text("\(intValue)%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis(.hidden)
        .frame(height: 132)
        .accessibilityLabel("Accuracy over the last \(points.count) sittings")
        .accessibilityValue("Average \(averageAccuracy) percent")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No sittings yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text("Finish a QBank module or a batch test and your accuracy trend appears here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}
