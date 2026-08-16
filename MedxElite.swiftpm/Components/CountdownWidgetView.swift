import SwiftUI

public struct CountdownWidgetView: View {
    public let targetDate: Date

    public init(targetDate: Date = Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 9)) ?? Date()) {
        self.targetDate = targetDate
    }

    public var body: some View {
        TimelineView(.periodic(from: Date(), by: 1.0)) { context in
            let remaining = computeRemaining(at: context.date)

            VStack(alignment: .leading, spacing: 14) {
                // Header
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(MedxTheme.primaryPink)
                            .frame(width: 8, height: 8)
                            .shadow(color: MedxTheme.primaryPink.opacity(0.5), radius: 4)

                        Text("FMGE · 9 JANUARY 2027")
                            .font(MedxFont.condensed(12, weight: .bold))
                            .foregroundColor(MedxTheme.primaryPink)
                            .tracking(1.2)
                    }
                    Spacer()
                    Text("\(remaining.weeks) weeks left")
                        .font(MedxFont.label(13))
                        .foregroundColor(.secondary)
                }

                // Main countdown
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(remaining.days)")
                        .font(MedxFont.hero(48))
                        .monospacedDigit()
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.primary, .primary.opacity(0.75)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .contentTransition(.numericText())
                        .animation(.snappy, value: remaining.days)

                    Text("days to go")
                        .font(MedxFont.headline(16))
                        .foregroundColor(.secondary)
                        .padding(.bottom, 6)

                    Spacer()

                    // Live clock pills
                    HStack(spacing: 4) {
                        ClockPill(value: remaining.hours, unit: "h")
                        Text(":").font(.system(size: 14, weight: .bold)).foregroundColor(Color(uiColor: .quaternaryLabel))
                        ClockPill(value: remaining.minutes, unit: "m")
                        Text(":").font(.system(size: 14, weight: .bold)).foregroundColor(Color(uiColor: .quaternaryLabel))
                        ClockPill(value: remaining.seconds, unit: "s")
                    }
                    .padding(.bottom, 6)
                }
            }
            .padding(20)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))

                    // Subtle gradient accent
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [MedxTheme.primaryPink.opacity(0.04), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
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

private struct ClockPill: View {
    let value: Int
    let unit: String

    var body: some View {
        HStack(spacing: 2) {
            Text(String(format: "%02d", value))
                .font(MedxFont.mono(14, weight: .bold))
                .foregroundColor(.primary)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)

            Text(unit)
                .font(MedxFont.label(11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }
}
