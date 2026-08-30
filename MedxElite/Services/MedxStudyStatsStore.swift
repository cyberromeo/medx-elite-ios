import Foundation
import Combine
import ActivityKit

// MARK: - Spaced revision

/// One module the spaced schedule says is due for another pass.
public struct MedxRevisionDue: Identifiable, Hashable, Sendable {
    public var id: String { moduleId }
    public let moduleId: String
    public let name: String
    public let subject: String
    public let sittings: Int
    public let lastAttempt: Date
    public let dueDate: Date

    public var overdueDays: Int {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: dueDate)
        let to = calendar.startOfDay(for: Date())
        return max(calendar.dateComponents([.day], from: from, to: to).day ?? 0, 0)
    }
}

// MARK: - Study stats

/// Turns the attempt history into the handful of numbers the rest of the app, the widgets
/// and the reminders all read: what was answered today, how long the streak is, and which
/// modules the spaced schedule wants back.
///
/// Everything is derived once in `ingest(attempts:)` rather than inside a `body` — these
/// loops walk every response of every sitting.
@MainActor
public final class MedxStudyStatsStore: ObservableObject {
    public static let shared = MedxStudyStatsStore()

    @Published public private(set) var answeredToday = 0
    @Published public private(set) var correctToday = 0
    @Published public private(set) var streakDays = 0
    @Published public private(set) var due: [MedxRevisionDue] = []
    /// Seven buckets, oldest first, ending on today. Drives the Home sparkline.
    @Published public private(set) var weeklyAnswered: [Int] = Array(repeating: 0, count: 7)
    @Published public private(set) var hasIngested = false

    @Published public var dailyGoal: Int {
        didSet {
            guard dailyGoal != oldValue else { return }
            UserDefaults.standard.set(dailyGoal, forKey: Self.goalKey)
            publishSnapshot()
        }
    }

    @Published public var examName: String {
        didSet {
            guard examName != oldValue else { return }
            UserDefaults.standard.set(examName, forKey: Self.examNameKey)
            publishSnapshot()
        }
    }

    @Published public var examDate: Date {
        didSet {
            guard examDate != oldValue else { return }
            UserDefaults.standard.set(examDate.timeIntervalSince1970, forKey: Self.examDateKey)
            publishSnapshot()
        }
    }

    private static let goalKey = "medx.goal.daily"
    private static let examNameKey = "medx.exam.name"
    private static let examDateKey = "medx.exam.date"

    /// Attempt count → days until the module comes back. A fifth pass parks it for six weeks.
    private static let revisionIntervals = [1, 3, 7, 21, 45]

    private init() {
        let storedGoal = UserDefaults.standard.integer(forKey: Self.goalKey)
        dailyGoal = storedGoal > 0 ? storedGoal : 50
        examName = UserDefaults.standard.string(forKey: Self.examNameKey) ?? "FMGE"
        let storedDate = UserDefaults.standard.double(forKey: Self.examDateKey)
        examDate = storedDate > 0
            ? Date(timeIntervalSince1970: storedDate)
            : MedxStudySnapshot.defaultExamDate
    }

    // MARK: - Derived reads

    public var dueCount: Int { due.count }

    public var goalFraction: Double {
        min(Double(answeredToday) / Double(max(dailyGoal, 1)), 1)
    }

    public var isGoalMet: Bool { answeredToday >= dailyGoal }

    public var remainingToGoal: Int { max(dailyGoal - answeredToday, 0) }

    public var daysToExam: Int { snapshot.daysRemaining() }

    public var snapshot: MedxStudySnapshot {
        MedxStudySnapshot(
            examName: examName,
            examDate: examDate,
            dailyGoal: dailyGoal,
            answeredToday: answeredToday,
            streakDays: streakDays,
            dueRevisions: due.count,
            accentHex: MedxAccent.current.hex
        )
    }

    // MARK: - Ingest

    public func ingest(attempts: [SittingAttempt]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var answered = 0
        var correct = 0
        var buckets = Array(repeating: 0, count: 7)
        var activeDays: Set<Date> = []
        // moduleId -> newest attempt plus how many sittings it has had
        var byModule: [String: (sittings: Int, last: Date, name: String, subject: String)] = [:]

        for attempt in attempts {
            guard let finished = attempt.finishedDate else { continue }
            let day = calendar.startOfDay(for: finished)
            activeDays.insert(day)

            if day == today {
                answered += attempt.attempted
                correct += attempt.score
            }

            if let offset = calendar.dateComponents([.day], from: day, to: today).day,
               offset >= 0, offset < 7 {
                buckets[6 - offset] += attempt.attempted
            }

            guard attempt.kind == "qbank", !attempt.sourceId.isEmpty else { continue }
            let existing = byModule[attempt.sourceId]
            byModule[attempt.sourceId] = (
                sittings: (existing?.sittings ?? 0) + 1,
                last: max(existing?.last ?? .distantPast, finished),
                name: attempt.name,
                subject: attempt.subject ?? existing?.subject ?? ""
            )
        }

        answeredToday = answered
        correctToday = correct
        weeklyAnswered = buckets
        streakDays = Self.streak(from: activeDays, today: today, calendar: calendar)
        due = Self.dueModules(from: byModule, calendar: calendar)
        hasIngested = true

        publishSnapshot()
    }

    /// Consecutive days of study. Today not being logged yet does not break the streak —
    /// it is counted from yesterday until midnight, which is exactly what the
    /// streak-protection reminder is warning about.
    private static func streak(from activeDays: Set<Date>, today: Date, calendar: Calendar) -> Int {
        guard !activeDays.isEmpty else { return 0 }

        var cursor = today
        if !activeDays.contains(cursor) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  activeDays.contains(yesterday) else { return 0 }
            cursor = yesterday
        }

        var count = 0
        while activeDays.contains(cursor) {
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    private static func dueModules(
        from byModule: [String: (sittings: Int, last: Date, name: String, subject: String)],
        calendar: Calendar
    ) -> [MedxRevisionDue] {
        let now = Date()
        var result: [MedxRevisionDue] = []

        for (moduleId, info) in byModule {
            let step = min(max(info.sittings, 1), revisionIntervals.count) - 1
            guard let dueDate = calendar.date(
                byAdding: .day,
                value: revisionIntervals[step],
                to: info.last
            ) else { continue }
            guard dueDate <= now else { continue }
            result.append(
                MedxRevisionDue(
                    moduleId: moduleId,
                    name: info.name,
                    subject: info.subject,
                    sittings: info.sittings,
                    lastAttempt: info.last,
                    dueDate: dueDate
                )
            )
        }

        // Longest overdue first: that is the one worth opening.
        return result.sorted { $0.dueDate < $1.dueDate }
    }

    // MARK: - Publish

    /// Pushes the current numbers to the widgets and re-arms the reminders. Safe to call
    /// often — both sides are cheap and idempotent.
    public func publishSnapshot() {
        let current = snapshot
        MedxSharedStore.save(current)
        MedxNotificationManager.shared.reschedule(with: current)
    }
}

// MARK: - Live Activities

/// Starts, updates and ends the two Live Activities. Every entry point is a no-op when the
/// student has Live Activities switched off, and every failure is swallowed: a refused
/// activity must never take a sitting or a download down with it.
@MainActor
public final class MedxLiveActivityController {
    public static let shared = MedxLiveActivityController()

    private var exam: Activity<MedxExamActivityAttributes>?
    private var downloads: [String: Activity<MedxDownloadActivityAttributes>] = [:]

    /// The system tolerates only a few concurrent activities, and a batch download would
    /// otherwise try to open one per class.
    private static let maxDownloadActivities = 2

    private init() {}

    public var isAvailable: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    // MARK: Exam sitting

    public func startExam(
        name: String,
        subject: String,
        totalQuestions: Int,
        state: MedxExamActivityAttributes.ContentState
    ) {
        guard isAvailable, exam == nil else { return }

        let attributes = MedxExamActivityAttributes(
            sittingName: name,
            subject: subject,
            totalQuestions: totalQuestions,
            accentHex: MedxAccent.current.hex
        )

        do {
            exam = try Activity<MedxExamActivityAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: state.endDate),
                pushType: nil
            )
        } catch {
            print("[LiveActivity] exam request refused: \(error)")
            exam = nil
        }
    }

    /// The stale date is the *block's* end, not the paper's, so an activity left behind by a
    /// submitted section greys out instead of counting down something that has ended.
    public func updateExam(state: MedxExamActivityAttributes.ContentState) {
        guard let activity = exam else { return }
        Task { await activity.update(ActivityContent(state: state, staleDate: state.endDate)) }
    }

    public func endExam(state: MedxExamActivityAttributes.ContentState) {
        guard let activity = exam else { return }
        exam = nil
        var final = state
        final.endDate = Date()
        Task {
            await activity.end(
                ActivityContent(state: final, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }

    // MARK: Downloads

    public func startDownload(id: String, title: String, subject: String, totalSegments: Int) {
        guard isAvailable,
              downloads[id] == nil,
              downloads.count < Self.maxDownloadActivities else { return }

        let attributes = MedxDownloadActivityAttributes(
            title: title,
            subject: subject,
            accentHex: MedxAccent.current.hex,
            videoId: id
        )
        let state = MedxDownloadActivityAttributes.ContentState(
            completedSegments: 0,
            totalSegments: totalSegments,
            fraction: 0,
            statusText: "Preparing…",
            isFinished: false
        )

        do {
            downloads[id] = try Activity<MedxDownloadActivityAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            downloadStartedAt[id] = Date()
        } catch {
            print("[LiveActivity] download request refused: \(error)")
            downloads[id] = nil
        }
    }

    /// When each download's activity began, so the ETA is measured rather than guessed.
    private var downloadStartedAt: [String: Date] = [:]

    public func updateDownload(
        id: String,
        completed: Int,
        total: Int,
        statusText: String,
        isPaused: Bool = false
    ) {
        guard let activity = downloads[id] else { return }
        let fraction = total > 0 ? Double(completed) / Double(total) : 0
        let state = MedxDownloadActivityAttributes.ContentState(
            completedSegments: completed,
            totalSegments: total,
            fraction: fraction,
            statusText: statusText,
            isFinished: false,
            isPaused: isPaused,
            secondsRemaining: estimateRemaining(id: id, fraction: fraction, isPaused: isPaused)
        )
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// Linear extrapolation from how long the first slice actually took.
    ///
    /// Withheld until a tenth of the way through: before that the sample is one or two segments and
    /// the estimate swings between two minutes and forty, which is worse than showing nothing. A
    /// paused download has no rate, so it has no estimate either.
    private func estimateRemaining(id: String, fraction: Double, isPaused: Bool) -> Int? {
        guard !isPaused, fraction >= 0.1, fraction < 1, let started = downloadStartedAt[id] else {
            return nil
        }
        let elapsed = Date().timeIntervalSince(started)
        guard elapsed > 3 else { return nil }
        return Int((elapsed / fraction) - elapsed)
    }

    public func endDownload(id: String, completed: Int, total: Int, statusText: String, finished: Bool) {
        guard let activity = downloads.removeValue(forKey: id) else { return }
        downloadStartedAt.removeValue(forKey: id)
        let state = MedxDownloadActivityAttributes.ContentState(
            completedSegments: completed,
            totalSegments: total,
            fraction: finished ? 1 : (total > 0 ? Double(completed) / Double(total) : 0),
            statusText: statusText,
            isFinished: finished
        )
        Task {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                // A finished download is worth a glance; a cancelled one is not.
                dismissalPolicy: finished ? .after(Date().addingTimeInterval(8)) : .immediate
            )
        }
    }

    // MARK: Faceoff

    private var duel: Activity<MedxDuelActivityAttributes>?

    /// Started lazily on the first update rather than by the lobby, because the attributes need
    /// both players' names and those are only settled once the guest has actually joined.
    public func updateDuel(
        mine: Profile?,
        theirs: Profile?,
        total: Int,
        state: MedxDuelActivityAttributes.ContentState
    ) {
        guard isAvailable else { return }

        if let activity = duel {
            Task { await activity.update(ActivityContent(state: state, staleDate: state.roundEndDate)) }
            return
        }

        let attributes = MedxDuelActivityAttributes(
            myName: mine?.displayName ?? "You",
            theirName: theirs?.displayName ?? "Them",
            myHex: mine.map { Self.duelHex(for: $0) } ?? "#FF4D8D",
            theirHex: theirs.map { Self.duelHex(for: $0) } ?? "#23C3F5",
            totalQuestions: max(total, 1),
            sourceName: "Faceoff"
        )

        do {
            duel = try Activity<MedxDuelActivityAttributes>.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: state.roundEndDate),
                pushType: nil
            )
        } catch {
            print("[LiveActivity] duel request refused: \(error)")
            duel = nil
        }
    }

    public func endDuel() {
        guard let activity = duel else { return }
        duel = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// The duel colours as hex, since the extension cannot resolve the app's palette. Kept here
    /// rather than on `Profile` because `MedxSharedState` deliberately imports no SwiftUI.
    private static func duelHex(for profile: Profile) -> String {
        profile.id == Profile.graveyard.id ? "#FF4D8D" : "#23C3F5"
    }

    /// Called when the app is signed out or torn down, so nothing is left on the Lock Screen.
    public func endAll() {
        endExam(
            state: MedxExamActivityAttributes.ContentState(
                answered: 0,
                currentNumber: 1,
                endDate: Date()
            )
        )
        endDuel()
        for id in Array(downloads.keys) {
            endDownload(id: id, completed: 0, total: 0, statusText: "Stopped", finished: false)
        }
    }
}
