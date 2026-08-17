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

                        Text("FMGE · 9 JAN 2027")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MedxTheme.primaryPink)
                    }

                    Spacer()

                    Text("\(remaining.weeks) weeks left")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
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
            .padding(18)
            .liquidGlassCard(cornerRadius: 22, glowColor: MedxTheme.primaryPink)
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
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(isPrimary ? MedxTheme.primaryPink : .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isPrimary ? MedxTheme.primaryPink.opacity(0.10) : Color(uiColor: .tertiarySystemFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isPrimary ? MedxTheme.primaryPink.opacity(0.36) : Color(uiColor: .separator).opacity(0.4),
                    lineWidth: 0.7
                )
        )
    }
}
