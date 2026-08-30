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
        MedxDuelLiveActivity()
    }
}

// MARK: - Shared plumbing
//
// `Color(medxHex:)`, the ring, the pace bar, the versus bar and the timer text all live in
// `MedxElite/Services/MedxActivityChrome.swift`, which is compiled into this target as well as the
// app — the same arrangement as `MedxSharedState.swift`. That is what keeps the three activities
// looking like one family rather than three separate attempts at the same idea.

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
    static let faceoff = URL(string: "medxelite://faceoff")!
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
            let state = context.state
            let total = max(
                state.sectionTotal > 0 ? state.sectionTotal : context.attributes.totalQuestions,
                1
            )
            let done = Double(state.answered) / Double(total)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        MedxActivityRing(fraction: done, tint: accent, lineWidth: 4) {
                            Text("\(state.answered)")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .minimumScaleFactor(0.5)
                        }
                        .frame(width: 34, height: 34)

                        MedxActivityTimer(endDate: state.endDate)
                            .font(.callout.weight(.semibold).monospacedDigit())
                            .foregroundStyle(accent)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    // Exam mode keeps the running score off the Lock Screen — the key has not been
                    // shown yet, so a right/wrong tally there would be a spoiler.
                    if state.revealsAnswers {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(state.correct) right")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.green)
                            Text("\(state.wrong) wrong")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("\(state.answered)/\(total)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(accent)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.sectionLabel ?? context.attributes.sittingName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    MedxPaceBar(
                        done: done,
                        elapsed: MedxExamPace.elapsedFraction(state: state, total: total),
                        tint: accent
                    )
                }
            } compactLeading: {
                MedxActivityRing(fraction: done, tint: accent, lineWidth: 3)
                    .frame(width: 18, height: 18)
            } compactTrailing: {
                MedxActivityTimer(endDate: state.endDate)
                    .monospacedDigit()
                    .frame(width: 44)
            } minimal: {
                MedxActivityRing(fraction: done, tint: accent, lineWidth: 3)
                    .frame(width: 18, height: 18)
            }
            .keylineTint(accent)
            .widgetURL(MedxWidgetLink.home)
        }
    }
}

/// How far through the block's clock the sitting is.
///
/// The activity is only pushed when a *count* changes, so it never learns how long the block was —
/// only when it ends. One minute a question is the app's rule everywhere, so the block's length is
/// derived from its question count and the elapsed share falls out of that.
enum MedxExamPace {
    static func elapsedFraction(
        state: MedxExamActivityAttributes.ContentState,
        total: Int
    ) -> Double {
        let budget = Double(total) * 60
        guard budget > 0 else { return 0 }
        let left = max(0, state.endDate.timeIntervalSinceNow)
        return min(max(1 - (left / budget), 0), 1)
    }
}

struct MedxExamLockScreenView: View {
    let context: ActivityViewContext<MedxExamActivityAttributes>

    private var accent: Color { Color(medxHex: context.attributes.accentHex) }

    private var total: Int {
        max(
            context.state.sectionTotal > 0 ? context.state.sectionTotal : context.attributes.totalQuestions,
            1
        )
    }

    private var done: Double { Double(context.state.answered) / Double(total) }

    var body: some View {
        HStack(spacing: 14) {
            // The ring carries the clock in its middle: one glance, two readings, and the timer is
            // still `Text(timerInterval:)` so the *system* ticks it — the app pushes only when a
            // count changes, never once a second.
            MedxActivityRing(fraction: done, tint: accent, lineWidth: 6) {
                MedxActivityTimer(endDate: context.state.endDate)
                    .font(.system(.footnote, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .frame(width: 62, height: 62)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(context.attributes.sittingName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    if let label = context.state.sectionLabel, context.state.isSectioned {
                        Text("\(label) of \(context.state.sectionCount)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accent.opacity(0.22), in: Capsule())
                    }
                }

                MedxPaceBar(
                    done: done,
                    elapsed: MedxExamPace.elapsedFraction(state: context.state, total: total),
                    tint: accent
                )

                HStack(spacing: 8) {
                    Text("\(context.state.answered)/\(total) answered")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(accent)

                    if context.state.revealsAnswers {
                        Text("· \(context.state.correct) right")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.green)
                    }

                    Spacer(minLength: 0)

                    Text("Q\(context.state.currentNumber)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(context.attributes.sittingName)
        .accessibilityValue("\(context.state.answered) of \(total) answered")
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
            let state = context.state

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    MedxActivityRing(fraction: state.fraction, tint: accent, lineWidth: 4) {
                        Text("\(Int(state.fraction * 100))")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .minimumScaleFactor(0.5)
                    }
                    .frame(width: 34, height: 34)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(MedxDownloadCopy.eta(state))
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
                    MedxDownloadControls(context: context, accent: accent)
                }
            } compactLeading: {
                MedxActivityRing(fraction: state.fraction, tint: accent, lineWidth: 3)
                    .frame(width: 18, height: 18)
            } compactTrailing: {
                Text("\(Int(state.fraction * 100))%")
                    .monospacedDigit()
            } minimal: {
                MedxActivityRing(fraction: state.fraction, tint: accent, lineWidth: 3)
                    .frame(width: 18, height: 18)
            }
            .keylineTint(accent)
            .widgetURL(MedxWidgetLink.downloads)
        }
    }
}

/// The two lines the download activity has to get right.
enum MedxDownloadCopy {
    /// Segments, not bytes. The downloader works segment by segment and never learns a total size,
    /// so "412 of 980" is a number it can actually stand behind.
    static func segments(_ state: MedxDownloadActivityAttributes.ContentState) -> String {
        guard state.totalSegments > 0 else { return state.statusText }
        return "\(state.completedSegments.formatted()) of \(state.totalSegments.formatted()) segments"
    }

    /// Withheld until there is enough of a sample to mean anything — see `estimateRemaining`.
    static func eta(_ state: MedxDownloadActivityAttributes.ContentState) -> String {
        if state.isFinished { return "Done" }
        if state.isPaused { return "Paused" }
        guard let seconds = state.secondsRemaining, seconds > 0 else {
            return "\(Int(state.fraction * 100))%"
        }
        if seconds < 60 { return "\(seconds)s left" }
        return "\(seconds / 60)m left"
    }
}

/// Pause / Resume and Cancel, on the Lock Screen.
///
/// The real upgrade over a bar and a percentage: a download that has picked the wrong moment can be
/// stopped without unlocking the phone and finding the screen it started from. The intents run in
/// the app's process — see `MedxSharedIntents.swift` for why they go through a notification rather
/// than reaching into the downloader directly.
struct MedxDownloadControls: View {
    let context: ActivityViewContext<MedxDownloadActivityAttributes>
    let accent: Color

    var body: some View {
        HStack(spacing: 8) {
            MedxPaceBar(done: context.state.fraction, elapsed: context.state.fraction, tint: accent)

            if !context.state.isFinished {
                if context.state.isPaused {
                    Button(intent: MedxResumeDownloadIntent(videoId: context.attributes.videoId)) {
                        Image(systemName: "play.fill")
                    }
                    .tint(accent)
                } else {
                    Button(intent: MedxPauseDownloadIntent(videoId: context.attributes.videoId)) {
                        Image(systemName: "pause.fill")
                    }
                    .tint(accent)
                }

                Button(intent: MedxCancelDownloadIntent(videoId: context.attributes.videoId)) {
                    Image(systemName: "xmark")
                }
                .tint(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .font(.caption.weight(.bold))
    }
}

struct MedxDownloadLockScreenView: View {
    let context: ActivityViewContext<MedxDownloadActivityAttributes>

    private var accent: Color { Color(medxHex: context.attributes.accentHex) }

    var body: some View {
        HStack(spacing: 14) {
            MedxActivityRing(
                fraction: context.state.fraction,
                tint: context.state.isFinished ? .green : accent,
                lineWidth: 6
            ) {
                if context.state.isFinished {
                    Image(systemName: "checkmark")
                        .font(.footnote.weight(.black))
                        .foregroundStyle(.green)
                } else {
                    Text("\(Int(context.state.fraction * 100))")
                        .font(.system(.footnote, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 6) {
                Text(context.attributes.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(MedxDownloadCopy.segments(context.state))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(MedxDownloadCopy.eta(context.state))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(context.state.isPaused ? .secondary : accent)

                    Spacer(minLength: 0)

                    if !context.state.isFinished {
                        if context.state.isPaused {
                            Button(intent: MedxResumeDownloadIntent(videoId: context.attributes.videoId)) {
                                Label("Resume", systemImage: "play.fill")
                            }
                            .tint(accent)
                        } else {
                            Button(intent: MedxPauseDownloadIntent(videoId: context.attributes.videoId)) {
                                Label("Pause", systemImage: "pause.fill")
                            }
                            .tint(accent)
                        }

                        Button(intent: MedxCancelDownloadIntent(videoId: context.attributes.videoId)) {
                            Image(systemName: "xmark")
                        }
                        .tint(.secondary)
                        .accessibilityLabel("Cancel download")
                    }
                }
                .buttonStyle(.bordered)
                .font(.caption.weight(.bold))
                .labelStyle(.titleAndIcon)
            }
        }
        .padding(16)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Faceoff Live Activity

/// A live duel on the Lock Screen and in the Dynamic Island.
///
/// The compact island is the point of this one: `12–9` and the round clock, which means the score is
/// readable mid-duel without unlocking. Pushed on reveal and on advance only — the round clock is
/// handed over as an end date, so the system ticks it.
struct MedxDuelLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MedxDuelActivityAttributes.self) { context in
            MedxDuelLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.45))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let mine = Color(medxHex: context.attributes.myHex)
            let theirs = Color(medxHex: context.attributes.theirHex)
            let state = context.state

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    MedxDuelSide(
                        name: context.attributes.myName,
                        points: state.myPoints,
                        hue: mine,
                        alignment: .leading
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    MedxDuelSide(
                        name: context.attributes.theirName,
                        points: state.theirPoints,
                        hue: theirs,
                        alignment: .trailing
                    )
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        if state.isArming {
                            Text("Starting")
                                .font(.caption2.weight(.bold))
                        } else {
                            MedxActivityTimer(endDate: state.roundEndDate)
                                .font(.callout.weight(.bold).monospacedDigit())
                        }
                        Text("Q\(state.qIndex + 1)/\(context.attributes.totalQuestions)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    MedxActivityVersusBar(share: state.myShare, mine: mine, theirs: theirs)
                }
            } compactLeading: {
                Text("\(state.myPoints)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(mine)
            } compactTrailing: {
                Text("\(state.theirPoints)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(theirs)
            } minimal: {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(state.myPoints >= state.theirPoints ? mine : theirs)
            }
            .keylineTint(state.myPoints >= state.theirPoints ? mine : theirs)
            .widgetURL(MedxWidgetLink.faceoff)
        }
    }
}

struct MedxDuelSide: View {
    let name: String
    let points: Int
    let hue: Color
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            Text("\(points)")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(hue)
            Text(name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct MedxDuelLockScreenView: View {
    let context: ActivityViewContext<MedxDuelActivityAttributes>

    private var mine: Color { Color(medxHex: context.attributes.myHex) }
    private var theirs: Color { Color(medxHex: context.attributes.theirHex) }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center) {
                MedxDuelSide(
                    name: context.attributes.myName,
                    points: context.state.myPoints,
                    hue: mine,
                    alignment: .leading
                )

                Spacer(minLength: 8)

                VStack(spacing: 1) {
                    if context.state.isArming {
                        Text("Starting")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.secondary)
                    } else {
                        MedxActivityTimer(endDate: context.state.roundEndDate)
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .monospacedDigit()
                    }
                    Text("Question \(context.state.qIndex + 1) of \(context.attributes.totalQuestions)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                MedxDuelSide(
                    name: context.attributes.theirName,
                    points: context.state.theirPoints,
                    hue: theirs,
                    alignment: .trailing
                )
            }

            MedxActivityVersusBar(share: context.state.myShare, mine: mine, theirs: theirs)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Faceoff")
        .accessibilityValue("\(context.attributes.myName) \(context.state.myPoints), "
                            + "\(context.attributes.theirName) \(context.state.theirPoints)")
    }
}
