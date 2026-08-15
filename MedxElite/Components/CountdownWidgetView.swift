import SwiftUI

public struct CountdownWidgetView: View {
    public let targetDate: Date
    @State private var timeRemaining: TimeRemaining = .zero
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(targetDate: Date = Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 9)) ?? Date()) {
        self.targetDate = targetDate
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(MedxTheme.primaryPink)
                        .frame(width: 8, height: 8)
                    Text("FMGE · 9 JANUARY 2027")
                        .font(MedxFont.rounded(12, weight: .bold))
                        .foregroundColor(MedxTheme.primaryPink)
                        .tracking(1.2)
                }
                Spacer()
                Text("\(timeRemaining.weeks) weeks left")
                    .font(MedxFont.rounded(13, weight: .medium))
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(timeRemaining.days)")
                    .font(MedxFont.rounded(48, weight: .heavy))
                    .monospacedDigit()
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.primary, .primary.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                Text("days to go")
                    .font(MedxFont.rounded(16, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 6)

                Spacer()

                // Live clock
                HStack(spacing: 4) {
                    ClockPill(value: timeRemaining.hours, unit: "h")
                    Text(":").font(.headline).foregroundColor(.secondary)
                    ClockPill(value: timeRemaining.minutes, unit: "m")
                    Text(":").font(.headline).foregroundColor(.secondary)
                    ClockPill(value: timeRemaining.seconds, unit: "s")
                }
                .padding(.bottom, 6)
            }
        }
        .padding(20)
        .liquidGlassCard(cornerRadius: 24, glowColor: MedxTheme.primaryPink)
        .onAppear { calculateRemaining() }
        .onReceive(timer) { _ in calculateRemaining() }
    }

    private func calculateRemaining() {
        let diff = targetDate.timeIntervalSince(Date())
        if diff <= 0 {
            timeRemaining = .zero
            return
        }
        let totalDays = Int(diff / 86400)
        let hours = Int((diff.truncatingRemainder(dividingBy: 86400)) / 3600)
        let minutes = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)
        let seconds = Int(diff.truncatingRemainder(dividingBy: 60))
        let weeks = totalDays / 7
        timeRemaining = TimeRemaining(days: totalDays, hours: hours, minutes: minutes, seconds: seconds, weeks: weeks)
    }
}

private struct TimeRemaining {
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
                .font(MedxFont.monospacedDigits(14, weight: .bold))
                .foregroundColor(.primary)
            Text(unit)
                .font(MedxFont.rounded(11, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
