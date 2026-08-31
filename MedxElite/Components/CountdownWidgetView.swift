import SwiftUI

/// Countdown to the exam. The days figure is the headline; hours/minutes/seconds are
/// secondary and monospaced so they do not jitter the layout every tick.
///
/// The date and name come from `MedxStudyStatsStore`, which is also what the widgets read —
/// so editing the exam here (long press) moves the Home Screen and Lock Screen with it.
public struct CountdownWidgetView: View {
    @ObservedObject private var stats = MedxStudyStatsStore.shared
    @ObservedObject private var medxTheme = MedxAccentThemeStore.shared
    @State private var showExamEditor = false

    public init() {}

    private var targetDate: Date { stats.examDate }
    private var title: String { stats.examName }

    public var body: some View {
        // **One tick a minute, not one a second.**
        //
        // The headline is a number of days. A 1 Hz schedule redrew this card 86,400 times a day so that
        // a seconds digit — which nobody reads on a countdown measured in months — could advance, and
        // it did it on the screen the app opens on. `.periodic` at 60s keeps the hours-and-minutes
        // readout honest to within a minute, which is as precise as a readout in that unit can be.
        TimelineView(.periodic(from: Date(), by: 60.0)) { context in
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
            .medxCard(cornerRadius: MedxDS.card)
            .contentShape(MedxDS.shape(MedxDS.card))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title) countdown")
            .accessibilityValue("\(remaining.days) days, \(remaining.hours) hours remaining")
            .accessibilityHint("Long press to change the exam date")
        }
        // Long press rather than a visible button: the card is a readout, and the date is
        // set once a year.
        .onLongPressGesture(minimumDuration: 0.4) {
            HapticManager.medium()
            showExamEditor = true
        }
        .accessibilityAction(named: "Change exam date") {
            showExamEditor = true
        }
        .sheet(isPresented: $showExamEditor) {
            MedxExamDateSheet()
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

    /// Hours and minutes. **No seconds** — the card ticks once a minute now, so a seconds digit would
    /// sit frozen on a stale value between ticks, which is worse than not showing one. A countdown
    /// measured in months does not have a seconds hand.
    private func clock(remaining: TimeRemaining) -> some View {
        HStack(spacing: 4) {
            unit(String(format: "%02d", remaining.hours), label: "hr")
            Text(":")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
            unit(String(format: "%02d", remaining.minutes), label: "min")
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

// MARK: - Exam editor

/// Name and date of the exam being counted down to. Writing them republishes the shared
/// snapshot, so the widgets follow immediately.
struct MedxExamDateSheet: View {
    @ObservedObject private var stats = MedxStudyStatsStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Exam") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.characters)
                        .frame(minHeight: 44)

                    DatePicker(
                        "Date",
                        selection: $date,
                        in: Date()...,
                        displayedComponents: .date
                    )
                }

                Section {
                    HStack {
                        Label("Days remaining", systemImage: "calendar")
                        Spacer()
                        Text("\(daysBetween)")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    .frame(minHeight: 44)
                } footer: {
                    Text("The Home Screen and Lock Screen widgets use this too.")
                }
            }
            .scrollContentBackground(.hidden)
            .medxPage(.home)
            .navigationTitle("Exam countdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .font(.body.weight(.semibold))
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = stats.examName
                date = stats.examDate
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var daysBetween: Int {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: Date())
        let to = calendar.startOfDay(for: date)
        return max(calendar.dateComponents([.day], from: from, to: to).day ?? 0, 0)
    }

    private func save() {
        HapticManager.success()
        stats.examName = name.trimmingCharacters(in: .whitespaces)
        stats.examDate = date
        dismiss()
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
