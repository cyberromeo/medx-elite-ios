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
        // One second is the smallest unit shown, so that is the tick rate. `TimelineView`
        // keeps the redraw scoped to this card instead of the whole Home screen.
        TimelineView(.periodic(from: Date(), by: 1.0)) { context in
            let remaining = TimeRemaining(until: targetDate, from: context.date)

            VStack(alignment: .leading, spacing: 14) {
                header

                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(remaining.days)")
                        .font(.system(size: 72, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(remaining.days == 1 ? "day" : "days")
                            .font(.title3.weight(.bold))
                        Text("to go")
                            .font(.subheadline.weight(.semibold))
                            .opacity(0.78)
                    }

                    Spacer(minLength: 8)

                    clock(remaining: remaining)
                }
                .animation(.snappy, value: remaining.days)

                progress(remaining: remaining)
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { MedxHeroBackground(colors: [MedxSection.home.fill, MedxSection.home.partner]) }
            .contentShape(RoundedRectangle(cornerRadius: MedxHeroBackground.radius, style: .continuous))
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

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "graduationcap.fill")
                .font(.footnote.weight(.bold))

            Text(title)
                .font(.footnote.weight(.heavy))
                .textCase(.uppercase)
                .tracking(0.8)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(targetDate.formatted(.dateTime.day().month(.abbreviated).year()))
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.2), in: Capsule())
        }
    }

    private func clock(remaining: TimeRemaining) -> some View {
        HStack(spacing: 3) {
            unit(String(format: "%02d", remaining.hours), label: "hr")
            Text(":").font(.subheadline.weight(.bold)).opacity(0.6)
            unit(String(format: "%02d", remaining.minutes), label: "min")
            Text(":").font(.subheadline.weight(.bold)).opacity(0.6)
            unit(String(format: "%02d", remaining.seconds), label: "sec")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .fixedSize()
    }

    private func unit(_ value: String, label: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit())
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .textCase(.uppercase)
                .opacity(0.75)
        }
    }

    private func progress(remaining: TimeRemaining) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.24))
                    Capsule()
                        .fill(Color.white)
                        .frame(width: max(8, geo.size.width * remaining.elapsedFraction))
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(remaining.weeks) weeks left")
                Spacer(minLength: 8)
                Text("\(Int((remaining.elapsedFraction * 100).rounded()))% of the run-up done")
            }
            .font(.caption.weight(.semibold).monospacedDigit())
            .opacity(0.85)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Hero surface

/// The one coloured surface on a browse screen: a hero card washed in a section's two hues, lit
/// from the top-left. It is opaque content, not glass — nothing samples through it — and it is
/// used once per screen at most, so it reads as the headline rather than as decoration.
public struct MedxHeroBackground: View {
    public static let radius: CGFloat = 28

    private let colors: [Color]
    @Environment(\.colorScheme) private var scheme

    public init(colors: [Color]) {
        self.colors = colors
    }

    public var body: some View {
        // One flat fill of the accent (the first colour handed in), no washes, glows or shadow:
        // the countdown is the one solid surface on Home and it should read as the accent, not as
        // a purple-to-blue sunset.
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        shape
            .fill(colors.first ?? MedxTheme.accent)
            .overlay {
                // A slightly darker floor keeps white text legible on a light accent.
                shape.fill(Color.black.opacity(scheme == .dark ? 0.18 : 0.08))
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
