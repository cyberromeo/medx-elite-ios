import Foundation
import UserNotifications

/// The three reminders, and nothing else.
///
/// Content depends on live numbers, so every request is rebuilt from scratch on each
/// foreground (`MedxStudyStatsStore.publishSnapshot()` calls `reschedule(with:)`) rather
/// than scheduled once and left to go stale.
@MainActor
public final class MedxNotificationManager: NSObject, ObservableObject {
    public static let shared = MedxNotificationManager()

    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case dailyQuestions = "medx.reminder.daily"
        case streakProtection = "medx.reminder.streak"
        case revisionDue = "medx.reminder.revision"

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .dailyQuestions: return "Daily question reminder"
            case .streakProtection: return "Streak protection"
            case .revisionDue: return "Revision due"
            }
        }

        public var detail: String {
            switch self {
            case .dailyQuestions: return "A nudge at your chosen hour with what is left of today's goal."
            case .streakProtection: return "At 9 pm, only when nothing has been logged yet."
            case .revisionDue: return "At 8 am, only when the spaced schedule has modules waiting."
            }
        }

        public var icon: String {
            switch self {
            case .dailyQuestions: return "bell.badge"
            case .streakProtection: return "flame"
            case .revisionDue: return "arrow.triangle.2.circlepath"
            }
        }

        var storageKey: String { rawValue + ".enabled" }
    }

    @Published public private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published public private(set) var pendingCount = 0

    @Published public var enabled: Set<Kind> {
        didSet {
            guard enabled != oldValue else { return }
            for kind in Kind.allCases {
                UserDefaults.standard.set(enabled.contains(kind), forKey: kind.storageKey)
            }
            reschedule(with: MedxSharedStore.loadOrDefault())
        }
    }

    @Published public var reminderHour: Int {
        didSet {
            guard reminderHour != oldValue else { return }
            UserDefaults.standard.set(reminderHour, forKey: Self.hourKey)
            reschedule(with: MedxSharedStore.loadOrDefault())
        }
    }

    private static let hourKey = "medx.reminder.hour"
    private static let configuredKey = "medx.reminder.configured"
    private let center = UNUserNotificationCenter.current()

    private override init() {
        let defaults = UserDefaults.standard
        let storedHour = defaults.integer(forKey: Self.hourKey)
        reminderHour = (1...23).contains(storedHour) ? storedHour : 19

        if defaults.bool(forKey: Self.configuredKey) {
            enabled = Set(Kind.allCases.filter { defaults.bool(forKey: $0.storageKey) })
        } else {
            // First run: everything on, so the reminders are a feature rather than a
            // setting nobody finds. Authorisation is still asked for separately.
            enabled = Set(Kind.allCases)
            defaults.set(true, forKey: Self.configuredKey)
            for kind in Kind.allCases {
                defaults.set(true, forKey: kind.storageKey)
            }
        }

        super.init()
        center.delegate = self
    }

    // MARK: - Authorisation

    public func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
        let pending = await center.pendingNotificationRequests()
        pendingCount = pending.count
    }

    @discardableResult
    public func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorization()
            if granted {
                reschedule(with: MedxSharedStore.loadOrDefault())
            }
            return granted
        } catch {
            await refreshAuthorization()
            return false
        }
    }

    public var isAuthorized: Bool {
        authorization == .authorized || authorization == .provisional
    }

    // MARK: - Scheduling

    /// Tears down all three requests and re-adds the ones that still apply. Cheap, and it
    /// means the copy on the Lock Screen always reflects the last time the app was open.
    public func reschedule(with snapshot: MedxStudySnapshot) {
        let identifiers = Kind.allCases.map(\.rawValue)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        guard isAuthorized else { return }

        if enabled.contains(.dailyQuestions) {
            add(.dailyQuestions, at: reminderHour, content: dailyContent(snapshot), repeats: true)
        }

        // Only worth firing while the streak is actually at risk.
        if enabled.contains(.streakProtection), !snapshot.isGoalMet, snapshot.streakDays > 0 {
            add(.streakProtection, at: 21, content: streakContent(snapshot), repeats: false)
        }

        if enabled.contains(.revisionDue), snapshot.dueRevisions > 0 {
            add(.revisionDue, at: 8, content: revisionContent(snapshot), repeats: true)
        }

        Task { await refreshAuthorization() }
    }

    public func cancelAll() {
        center.removeAllPendingNotificationRequests()
        pendingCount = 0
    }

    // MARK: - Copy

    private func dailyContent(_ snapshot: MedxStudySnapshot) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Today's questions"
        if snapshot.remainingToGoal > 0 {
            content.body = "\(snapshot.remainingToGoal) to go for your goal of \(snapshot.dailyGoal). "
                + "\(snapshot.daysRemaining()) days to \(snapshot.examName)."
        } else {
            content.body = "Goal of \(snapshot.dailyGoal) already met — anything more is a bonus. "
                + "\(snapshot.daysRemaining()) days to \(snapshot.examName)."
        }
        content.sound = .default
        return content
    }

    private func streakContent(_ snapshot: MedxStudySnapshot) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "\(snapshot.streakDays)-day streak at risk"
        content.body = snapshot.answeredToday > 0
            ? "\(snapshot.remainingToGoal) more questions keeps it alive past midnight."
            : "Nothing logged today. One module is enough to keep the streak."
        content.sound = .default
        return content
    }

    private func revisionContent(_ snapshot: MedxStudySnapshot) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        let count = snapshot.dueRevisions
        content.title = count == 1 ? "1 module due for revision" : "\(count) modules due for revision"
        content.body = "The spaced schedule wants these back today. Tap to start."
        content.sound = .default
        return content
    }

    private func add(
        _ kind: Kind,
        at hour: Int,
        content: UNMutableNotificationContent,
        repeats: Bool
    ) {
        content.categoryIdentifier = kind.rawValue
        content.threadIdentifier = kind.rawValue

        var components = DateComponents()
        components.hour = hour
        components.minute = 0

        let trigger: UNNotificationTrigger
        if repeats {
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        } else {
            // One-shot: if the hour has already gone by today, aim at tomorrow instead of
            // letting the system fire it immediately.
            let calendar = Calendar.current
            var target = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
            if target <= Date() {
                target = calendar.date(byAdding: .day, value: 1, to: target) ?? target
            }
            trigger = UNCalendarNotificationTrigger(
                dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: target),
                repeats: false
            )
        }

        center.add(UNNotificationRequest(identifier: kind.rawValue, content: content, trigger: trigger))
    }

    /// Where a tap on each reminder should land.
    nonisolated static func route(for identifier: String) -> MedxRoute? {
        switch Kind(rawValue: identifier) {
        case .dailyQuestions: return .qbank
        case .streakProtection: return .home
        case .revisionDue: return .todaysRevision
        case nil: return nil
        }
    }
}

// MARK: - Delegate

/// The delegate callbacks arrive on an arbitrary queue, so they are `nonisolated` and hop
/// to the main actor with only a `String` in hand.
extension MedxNotificationManager: UNUserNotificationCenterDelegate {
    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Showing a reminder while the app is already open is noise, but the badge and the
        // list entry are still useful.
        completionHandler([.list, .badge])
    }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        completionHandler()
        guard let route = MedxNotificationManager.route(for: identifier) else { return }
        Task { @MainActor in
            AppState.shared.open(route: route)
        }
    }
}
