import SwiftUI

public struct CountdownWidgetView: View {
    public let targetDate: Date

    public init(targetDate: Date = Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 9)) ?? Date()) {
        self.targetDate = targetDate
    }

    public var body: some View {
        TimelineView(.periodic(from: Date(), by: 1.0)) { context in
            let remaining = computeRemaining(at: context.date)

            VStack(spacing: 14) {
                // Header Bar
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(MedxTheme.primaryPink)
                            .frame(width: 7, height: 7)
                            .shadow(color: MedxTheme.primaryPink.opacity(0.6), radius: 3)

                        Text("FMGE · 9 JAN 2027")
                            .font(MedxFont.mono(11, weight: .bold))
                            .foregroundColor(MedxTheme.primaryPink)
                            .tracking(0.8)
                    }

                    Spacer()

                    Text("\(remaining.weeks) weeks left")
                        .font(MedxFont.mono(11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.04))
                        .clipShape(Capsule())
                }

                // Countdown Cards Grid (4 responsive columns)
                HStack(spacing: 8) {
                    CountdownUnitCard(
                        value: remaining.days,
                        unit: "DAYS",
                        isPrimary: true
                    )

                    CountdownUnitCard(
                        value: remaining.hours,
                        unit: "HRS",
                        isPrimary: false
                    )

                    CountdownUnitCard(
                        value: remaining.minutes,
                        unit: "MINS",
                        isPrimary: false
                    )

                    CountdownUnitCard(
                        value: remaining.seconds,
                        unit: "SECS",
                        isPrimary: false
                    )
                }
            }
            .padding(16)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))

                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [MedxTheme.primaryPink.opacity(0.05), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(MedxTheme.primaryPink.opacity(0.12), lineWidth: 0.8)
            )
            .shadow(
                color: MedxTheme.Shadow.subtle.color,
                radius: MedxTheme.Shadow.subtle.radius,
                y: MedxTheme.Shadow.subtle.y
            )
        }
    }

    private func computeRemaining(at date: Date) -> TimeRemaining {
        let diff = targetDate.timeIntervalSince(date)
        if diff <= 0 { return .zero }
        let totalDays = Int(diff / 86400)
        let hours = Int((diff.truncatingRemainder(dividingBy: 86400)) / 3600)
        let minutes = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)
        let seconds = Int(diff.truncatingRemainder(dividingBy: 60))
        let weeks = totalDays / 7
        return TimeRemaining(days: totalDays, hours: hours, minutes: minutes, seconds: seconds, weeks: weeks)
    }
}

private struct TimeRemaining: Equatable {
    var days: Int
    var hours: Int
    var minutes: Int
    var seconds: Int
    var weeks: Int

    static let zero = TimeRemaining(days: 0, hours: 0, minutes: 0, seconds: 0, weeks: 0)
}

private struct CountdownUnitCard: View {
    let value: Int
    let unit: String
    let isPrimary: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text(isPrimary ? "\(value)" : String(format: "%02d", value))
                .font(isPrimary ? MedxFont.mono(24, weight: .bold) : MedxFont.mono(20, weight: .bold))
                .foregroundColor(isPrimary ? .primary : .secondary)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(unit)
                .font(MedxFont.mono(9, weight: .bold))
                .foregroundColor(isPrimary ? MedxTheme.primaryPink : .secondary.opacity(0.7))
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isPrimary ? MedxTheme.primaryPink.opacity(0.08) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isPrimary ? MedxTheme.primaryPink.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }
}
