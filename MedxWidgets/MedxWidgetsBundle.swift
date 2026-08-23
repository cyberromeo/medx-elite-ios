import WidgetKit
import SwiftUI
import ActivityKit

// MARK: - Bundle
//
// This target exists only in MedxElite.xcodeproj — Swift Playgrounds cannot build app
// extensions, so the `.swiftpm` copy of the app simply has no widgets. The only file shared
// with the app is `MedxElite/Services/MedxSharedState.swift`, which is why nothing here
// imports the app's theme or models: everything arrives in `MedxStudySnapshot`.

@main
struct MedxWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MedxExamCountdownWidget()
        MedxDailyGoalWidget()
        MedxExamSittingLiveActivity()
        MedxDownloadLiveActivity()
    }
}

// MARK: - Shared plumbing

extension Color {
    /// The student's chosen accent, travelling as a hex string in the snapshot because an
    /// extension cannot resolve the app's dynamic `UIColor` tokens.
    init(medxHex: String) {
        let components = medxHex.medxRGBComponents
        self.init(
            .sRGB,
            red: components.red,
            green: components.green,
            blue: components.blue,
            opacity: 1
        )
    }
}

struct MedxSnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: MedxStudySnapshot
    /// False when there is no shared container to read — a build signed without an app-group
    /// entitlement (common when sideloading with a free account), or simply before the app has
    /// run once. The countdown is still correct; the personal figures are not, and the views
    /// say so rather than showing a zero as if it were today's real score.
    let isLive: Bool
}

/// Reads the shared snapshot and lays out entries on the hour.
///
/// The day count only changes at midnight, but hourly entries mean the widget is never more
/// than an hour stale after the app has been closed for days — and they cost nothing, since
/// each one is the same small struct.
struct MedxSnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> MedxSnapshotEntry {
        MedxSnapshotEntry(date: Date(), snapshot: .placeholder, isLive: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (MedxSnapshotEntry) -> Void) {
        if context.isPreview {
            // The gallery should show what the widget looks like when it is working.
            completion(MedxSnapshotEntry(date: Date(), snapshot: .placeholder, isLive: true))
            return
        }
        let (snapshot, isLive) = MedxSharedStore.loadForWidget()
        completion(MedxSnapshotEntry(date: Date(), snapshot: snapshot, isLive: isLive))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MedxSnapshotEntry>) -> Void) {
        let (snapshot, isLive) = MedxSharedStore.loadForWidget()
        let calendar = Calendar.current
        let now = Date()

        var entries = [MedxSnapshotEntry(date: now, snapshot: snapshot, isLive: isLive)]
        for hour in 1...24 {
            guard let date = calendar.date(byAdding: .hour, value: hour, to: now) else { continue }
            entries.append(MedxSnapshotEntry(date: date, snapshot: snapshot, isLive: isLive))
        }

        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Exam countdown

struct MedxExamCountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MedxExamCountdown", provider: MedxSnapshotProvider()) { entry in
            MedxCountdownEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Exam countdown")
        .description("Days left before the exam, on the Home Screen or the Lock Screen.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

struct MedxCountdownEntryView: View {
    let entry: MedxSnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var days: Int { entry.snapshot.daysRemaining(from: entry.date) }
    private var accent: Color { Color(medxHex: entry.snapshot.accentHex) }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("\(days)d to \(entry.snapshot.examName)")
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .systemMedium:
            medium
        default:
            small
        }
    }

    private var circular: some View {
        Gauge(value: fractionElapsed) {
            Image(systemName: "calendar")
        } currentValueLabel: {
            Text("\(days)")
                .font(.system(.body, design: .rounded).weight(.semibold))
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircular)
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.snapshot.examName.uppercased())
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
            Text("\(days) days left")
                .font(.headline)
            Text(entry.isLive
                 ? "\(entry.snapshot.answeredToday)/\(entry.snapshot.dailyGoal) today · \(entry.snapshot.streakDays)d streak"
                 : entry.snapshot.examDate.formatted(.dateTime.day().month(.wide).year()))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(entry.snapshot.examName, systemImage: "calendar.badge.clock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text("\(days)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text(days == 1 ? "day left" : "days left")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            if entry.isLive {
                ProgressView(value: entry.snapshot.goalFraction)
                    .tint(accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(MedxWidgetLink.home)
    }

    private var medium: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label(entry.snapshot.examName, systemImage: "calendar.badge.clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)

                Text("\(days)")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Text("\(entry.snapshot.weeksRemaining(from: entry.date)) weeks · "
                     + entry.snapshot.examDate.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Divider()

            if entry.isLive {
                VStack(alignment: .leading, spacing: 8) {
                    MedxWidgetStat(
                        icon: "target",
                        value: "\(entry.snapshot.answeredToday)/\(entry.snapshot.dailyGoal)",
                        label: "today",
                        tint: accent
                    )
                    MedxWidgetStat(
                        icon: "flame.fill",
                        value: "\(entry.snapshot.streakDays)",
                        label: "day streak",
                        tint: .orange
                    )
                    MedxWidgetStat(
                        icon: "arrow.triangle.2.circlepath",
                        value: "\(entry.snapshot.dueRevisions)",
                        label: "due",
                        tint: .teal
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                MedxWidgetHint()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .widgetURL(MedxWidgetLink.home)
    }

    /// How far through the run-up the student is, for the Lock Screen gauge. A nominal
    /// one-year window, matched to the in-app countdown card.
    private var fractionElapsed: Double {
        let window = 365.0
        let remaining = Double(days)
        return min(max(1 - (remaining / window), 0), 1)
    }
}

// MARK: - Small pieces

/// Deep links the widgets hand back to the app. `MedxEliteApp.onOpenURL` maps them to routes.
enum MedxWidgetLink {
    static let home = URL(string: "medxelite://home")!
    static let revision = URL(string: "medxelite://revision")!
    static let search = URL(string: "medxelite://search")!
    static let downloads = URL(string: "medxelite://downloads")!
}

struct MedxWidgetStat: View {
    let icon: String
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 14)

            Text(value)
                .font(.footnote.weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }
}

/// Shown in place of the personal figures when there is no shared container. Says what is
/// wrong and what to do about it, rather than displaying zeroes that look like a bad day.
struct MedxWidgetHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "arrow.up.forward.app")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("Open MedX Elite")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

            Text("to sync your goal and streak")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Open MedX Elite to sync your goal and streak")
    }
}

// MARK: - Daily goal

struct MedxDailyGoalWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MedxDailyGoal", provider: MedxSnapshotProvider()) { entry in
            MedxDailyGoalEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Daily goal & streak")
        .description("Today's questions against your goal, your streak, and what is due for revision.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct MedxDailyGoalEntryView: View {
    let entry: MedxSnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var accent: Color { Color(medxHex: entry.snapshot.accentHex) }

    var body: some View {
        HStack(spacing: 14) {
            if entry.isLive {
                ring
            } else {
                unlinkedMark
            }

            if family != .systemSmall {
                if entry.isLive {
                    VStack(alignment: .leading, spacing: 8) {
                        MedxWidgetStat(
                            icon: "flame.fill",
                            value: "\(entry.snapshot.streakDays)",
                            label: "day streak",
                            tint: .orange
                        )
                        MedxWidgetStat(
                            icon: "arrow.triangle.2.circlepath",
                            value: "\(entry.snapshot.dueRevisions)",
                            label: "modules due",
                            tint: .teal
                        )
                        MedxWidgetStat(
                            icon: "calendar",
                            value: "\(entry.snapshot.daysRemaining(from: entry.date))",
                            label: "days to \(entry.snapshot.examName)",
                            tint: accent
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MedxWidgetHint()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .widgetURL(entry.snapshot.dueRevisions > 0 ? MedxWidgetLink.revision : MedxWidgetLink.home)
    }

    /// Stands in for the ring when there is nothing real to draw in it.
    private var unlinkedMark: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.18), lineWidth: 9)

            Image(systemName: "arrow.up.forward.app")
                .font(.title3.weight(.semibold))
                .foregroundStyle(accent)
        }
        .frame(width: 78, height: 78)
        .accessibilityHidden(true)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(0.18), lineWidth: 9)

            Circle()
                .trim(from: 0, to: max(entry.snapshot.goalFraction, 0.005))
                .stroke(accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(entry.snapshot.answeredToday)")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                Text("of \(entry.snapshot.dailyGoal)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(6)
        }
        .frame(width: 78, height: 78)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's questions")
        .accessibilityValue("\(entry.snapshot.answeredToday) of \(entry.snapshot.dailyGoal)")
    }
}

// MARK: - Exam sitting Live Activity

struct MedxExamSittingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MedxExamActivityAttributes.self) { context in
            MedxExamLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.4))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let accent = Color(medxHex: context.attributes.accentHex)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(context.state.answered)/\(context.attributes.totalQuestions)", systemImage: "checkmark.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    MedxExamTimerText(endDate: context.state.endDate)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.sittingName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(
                        value: Double(context.state.answered),
                        total: Double(max(context.attributes.totalQuestions, 1))
                    )
                    .tint(accent)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(accent)
            } compactTrailing: {
                MedxExamTimerText(endDate: context.state.endDate)
                    .monospacedDigit()
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(accent)
            }
            .keylineTint(accent)
            .widgetURL(MedxWidgetLink.home)
        }
    }
}

/// `Text(timerInterval:)` lets the system tick the clock, so the app only pushes an update
/// when the answered count changes — not once a second. The range is clamped because a
/// finished sitting can leave `endDate` in the past, and an inverted range traps.
struct MedxExamTimerText: View {
    let endDate: Date

    var body: some View {
        let now = Date()
        let end = max(endDate, now.addingTimeInterval(1))
        return Text(timerInterval: now...end, countsDown: true)
    }
}

struct MedxExamLockScreenView: View {
    let context: ActivityViewContext<MedxExamActivityAttributes>

    private var accent: Color { Color(medxHex: context.attributes.accentHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.sittingName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(context.attributes.subject.isEmpty ? "Exam mode" : context.attributes.subject)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                MedxExamTimerText(endDate: context.state.endDate)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(accent)
            }

            ProgressView(
                value: Double(context.state.answered),
                total: Double(max(context.attributes.totalQuestions, 1))
            )
            .tint(accent)

            HStack {
                Text("Question \(context.state.currentNumber) of \(context.attributes.totalQuestions)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(context.state.answered) answered")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(accent)
            }
        }
        .padding(16)
    }
}

// MARK: - Download Live Activity

struct MedxDownloadLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MedxDownloadActivityAttributes.self) { context in
            MedxDownloadLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.4))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let accent = Color(medxHex: context.attributes.accentHex)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.isFinished ? "checkmark.circle.fill" : "arrow.down.circle")
                        .foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(context.state.fraction * 100))%")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.fraction)
                        .tint(accent)
                }
            } compactLeading: {
                Image(systemName: "arrow.down")
                    .foregroundStyle(accent)
            } compactTrailing: {
                Text("\(Int(context.state.fraction * 100))%")
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "arrow.down")
                    .foregroundStyle(accent)
            }
            .keylineTint(accent)
            .widgetURL(MedxWidgetLink.downloads)
        }
    }
}

struct MedxDownloadLockScreenView: View {
    let context: ActivityViewContext<MedxDownloadActivityAttributes>

    private var accent: Color { Color(medxHex: context.attributes.accentHex) }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: context.state.isFinished ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                .font(.title2)
                .foregroundStyle(context.state.isFinished ? Color.green : accent)

            VStack(alignment: .leading, spacing: 6) {
                Text(context.attributes.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                ProgressView(value: context.state.fraction)
                    .tint(accent)

                HStack {
                    Text(context.state.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text("\(Int(context.state.fraction * 100))%")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(accent)
                }
            }
        }
        .padding(16)
    }
}
