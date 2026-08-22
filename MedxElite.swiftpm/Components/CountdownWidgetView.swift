import SwiftUI

/// Countdown to the exam. The days figure is the headline; hours/minutes/seconds are
/// secondary and monospaced so they do not jitter the layout every tick.
public struct CountdownWidgetView: View {
    public let targetDate: Date
    public let title: String

    public init(
        targetDate: Date = Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 9)) ?? Date(),
        title: String = "FMGE"
    ) {
        self.targetDate = targetDate
        self.title = title
    }

    public var body: some View {
        // One second is the smallest unit shown, so that is the tick rate. `TimelineView`
        // keeps the redraw scoped to this card instead of the whole Home screen.
        TimelineView(.periodic(from: Date(), by: 1.0)) { context in
            let remaining = TimeRemaining(until: targetDate, from: context.date)

            VStack(alignment: .leading, spacing: 14) {
                header(remaining: remaining)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(remaining.days)")
                        .font(MedxFont.display(44))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(.primary)

                    Text(remaining.days == 1 ? "day" : "days")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    clock(remaining: remaining)
                }
                .animation(.snappy, value: remaining.days)

                ProgressView(value: remaining.elapsedFraction)
                    .tint(MedxTheme.primaryPink)
                    .accessibilityHidden(true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .medxCard(cornerRadius: 20)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title) countdown")
            .accessibilityValue("\(remaining.days) days, \(remaining.hours) hours remaining")
        }
    }

    private func header(remaining: TimeRemaining) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(MedxTheme.primaryPink)
                .frame(width: 7, height: 7)

            Text("\(title) · \(targetDate.formatted(.dateTime.day().month(.abbreviated).year()))")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(MedxTheme.primaryPink)

            Spacer(minLength: 8)

            Text("\(remaining.weeks) weeks left")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func clock(remaining: TimeRemaining) -> some View {
        HStack(spacing: 4) {
            unit(String(format: "%02d", remaining.hours), label: "hr")
            Text(":")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
            unit(String(format: "%02d", remaining.minutes), label: "min")
            Text(":")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
            unit(String(format: "%02d", remaining.seconds), label: "sec")
        }
    }

    private func unit(_ value: String, label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TimeRemaining: Equatable {
    var days = 0
    var hours = 0
    var minutes = 0
    var seconds = 0
    var weeks = 0
    /// How far through a nominal one-year run-up the student is, for the progress bar.
    var elapsedFraction: Double = 1

    init(until target: Date, from now: Date) {
        let diff = target.timeIntervalSince(now)
        guard diff > 0 else { return }

        days = Int(diff / 86_400)
        hours = Int(diff.truncatingRemainder(dividingBy: 86_400) / 3_600)
        minutes = Int(diff.truncatingRemainder(dividingBy: 3_600) / 60)
        seconds = Int(diff.truncatingRemainder(dividingBy: 60))
        weeks = days / 7

        let window: Double = 365 * 86_400
        elapsedFraction = min(max(1 - (diff / window), 0), 1)
    }
}
