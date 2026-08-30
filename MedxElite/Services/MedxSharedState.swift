import Foundation
import WidgetKit
import ActivityKit

// MARK: - App Group
//
// This file is the *only* source compiled into both the app and the `MedxWidgets`
// extension, so it deliberately imports nothing app-specific: no SwiftUI, no UIKit, no
// project theme. Everything the widgets and Live Activities need travels through
// `MedxStudySnapshot` and the two `ActivityAttributes` types below.

public enum MedxAppGroup {
    /// What `Config/*.entitlements` declare.
    public static let preferredIdentifier = "group.quest.srihari.medxelite"

    /// The group this *build* can actually reach, resolved once.
    ///
    /// Not just the constant above, for two reasons. A sideloader (AltStore / SideStore)
    /// re-signs with the user's own team and can rewrite the group identifier, so the
    /// compile-time name may not be the one in the profile. And a free provisioning profile
    /// has no app-group entitlement at all, in which case there is no group to use.
    public static let resolvedIdentifier: String? = resolve()

    public static var isShared: Bool { resolvedIdentifier != nil }

    /// The shared container when one is reachable, and the app's own defaults when it is not.
    /// Swift Playgrounds grants no entitlements, so falling back keeps the app itself working
    /// there — only the widgets lose their live numbers.
    public static var defaults: UserDefaults {
        guard let resolvedIdentifier, let suite = UserDefaults(suiteName: resolvedIdentifier) else {
            return .standard
        }
        return suite
    }

    private static func resolve() -> String? {
        for candidate in [preferredIdentifier] + provisionedGroups() where isReachable(candidate) {
            return candidate
        }
        return nil
    }

    /// The honest test. `UserDefaults(suiteName:)` hands back a usable-looking object even for
    /// a suite the sandbox will never share, so asking it proves nothing; only a container URL
    /// does.
    private static func isReachable(_ group: String) -> Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil
    }

    /// App groups listed in the embedded provisioning profile, which is the authority on what
    /// this signature actually granted.
    private static func provisionedGroups() -> [String] {
        var groups: [String] = []
        for url in profileURLs() {
            guard let data = try? Data(contentsOf: url),
                  let plist = embeddedPlist(in: data),
                  let entitlements = plist["Entitlements"] as? [String: Any],
                  let listed = entitlements["com.apple.security.application-groups"] as? [String]
            else { continue }
            for group in listed where !groups.contains(group) {
                groups.append(group)
            }
        }
        return groups
    }

    private static func profileURLs() -> [URL] {
        var urls: [URL] = []
        if let own = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") {
            urls.append(own)
        }
        // An extension lives at `<App>.app/PlugIns/<Name>.appex`, so the containing app's
        // profile is two directories up — worth checking, because an appex is not always
        // signed with a profile of its own.
        let host = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("embedded.mobileprovision")
        if FileManager.default.fileExists(atPath: host.path) {
            urls.append(host)
        }
        return urls
    }

    /// A `.mobileprovision` is a CMS blob with an XML plist buried in it.
    private static func embeddedPlist(in data: Data) -> [String: Any]? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), options: .backwards),
              start.lowerBound < end.upperBound
        else { return nil }

        let slice = Data(data[start.lowerBound..<end.upperBound])
        return try? PropertyListSerialization.propertyList(
            from: slice,
            options: [],
            format: nil
        ) as? [String: Any]
    }
}

// MARK: - Snapshot

/// Everything the home-screen and Lock Screen widgets render, written by the app after
/// each sitting and on every background transition.
public struct MedxStudySnapshot: Codable, Hashable, Sendable {
    public var examName: String
    public var examDate: Date
    public var dailyGoal: Int
    public var answeredToday: Int
    public var streakDays: Int
    public var dueRevisions: Int
    /// The accent the student picked, so the widget matches the app without importing it.
    public var accentHex: String
    public var updatedAt: Date

    public init(
        examName: String,
        examDate: Date,
        dailyGoal: Int,
        answeredToday: Int,
        streakDays: Int,
        dueRevisions: Int,
        accentHex: String,
        updatedAt: Date = Date()
    ) {
        self.examName = examName
        self.examDate = examDate
        self.dailyGoal = max(dailyGoal, 1)
        self.answeredToday = max(answeredToday, 0)
        self.streakDays = max(streakDays, 0)
        self.dueRevisions = max(dueRevisions, 0)
        self.accentHex = accentHex
        self.updatedAt = updatedAt
    }

    /// Shown in the widget gallery and whenever nothing has been written yet.
    public static var placeholder: MedxStudySnapshot {
        MedxStudySnapshot(
            examName: "FMGE",
            examDate: MedxStudySnapshot.defaultExamDate,
            dailyGoal: 50,
            answeredToday: 32,
            streakDays: 6,
            dueRevisions: 4,
            accentHex: "#0A84FF"
        )
    }

    public static var defaultExamDate: Date {
        Calendar.current.date(from: DateComponents(year: 2027, month: 1, day: 9)) ?? Date()
    }

    /// What the widgets show when there is no shared container to read — a sideloaded build
    /// signed without an app-group entitlement, or simply before the app has run once.
    ///
    /// The countdown stays real, because it needs nothing but a date. The personal figures are
    /// zeroed rather than invented: a widget claiming a six-day streak that does not exist is
    /// worse than one admitting it has nothing to show.
    public static var unlinked: MedxStudySnapshot {
        MedxStudySnapshot(
            examName: "FMGE",
            examDate: MedxStudySnapshot.defaultExamDate,
            dailyGoal: 50,
            answeredToday: 0,
            streakDays: 0,
            dueRevisions: 0,
            accentHex: "#0A84FF"
        )
    }

    /// Whole days left, counted on calendar day boundaries rather than by dividing an
    /// interval — otherwise the widget and the in-app countdown disagree near midnight.
    public func daysRemaining(from now: Date = Date()) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: examDate)
        let days = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        return max(days, 0)
    }

    public func weeksRemaining(from now: Date = Date()) -> Int {
        daysRemaining(from: now) / 7
    }

    public var goalFraction: Double {
        min(Double(answeredToday) / Double(max(dailyGoal, 1)), 1)
    }

    public var isGoalMet: Bool {
        answeredToday >= dailyGoal
    }

    public var remainingToGoal: Int {
        max(dailyGoal - answeredToday, 0)
    }
}

// MARK: - Shared store

public enum MedxSharedStore {
    private static let snapshotKey = "medx.shared.snapshot"

    public static func save(_ snapshot: MedxStudySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        MedxAppGroup.defaults.set(data, forKey: snapshotKey)
        reloadWidgets()
    }

    public static func load() -> MedxStudySnapshot? {
        guard let data = MedxAppGroup.defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(MedxStudySnapshot.self, from: data)
    }

    /// Real data if it has been written, otherwise honest defaults.
    ///
    /// Deliberately **not** `.placeholder`: that carries demo figures for the widget gallery,
    /// and handing them to the reminders or to Siri would mean a fresh install announcing a
    /// six-day streak it does not have.
    public static func loadOrDefault() -> MedxStudySnapshot {
        load() ?? .unlinked
    }

    /// What a widget should render, and whether the numbers in it are real.
    public static func loadForWidget() -> (snapshot: MedxStudySnapshot, isLive: Bool) {
        guard MedxAppGroup.isShared, let stored = load() else {
            return (.unlinked, false)
        }
        return (stored, true)
    }

    /// One line for Settings, so "why is my widget empty" is answerable without a debugger.
    public static var containerDescription: String {
        guard let group = MedxAppGroup.resolvedIdentifier else {
            return "No shared container — widgets show the countdown only"
        }
        return group
    }

    public static func reloadWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Live Activity attributes

/// Exam-mode sitting on the Lock Screen and in the Dynamic Island.
///
/// `endDate` is carried in the state so the widget can hand the countdown to
/// `Text(timerInterval:)` and let the system tick it — the app then only has to push an
/// update when a *count* changes, not once a second.
///
/// The section fields are what a Marrow grand paper needs: it is sat as three 50-question
/// blocks with a clock each, so `endDate` is the end of the *block*, and the activity has to be
/// able to say which one is open. An unsectioned paper carries `sectionCount == 1` and a nil
/// label, which is how the views know not to draw the chip.
public struct MedxExamActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var answered: Int
        /// Only meaningful in revision mode, where the key is shown as you go. Exam mode keeps
        /// them at zero rather than leaking a running score onto the Lock Screen.
        public var correct: Int
        public var wrong: Int
        public var currentNumber: Int
        public var endDate: Date
        public var sectionLabel: String?
        public var sectionIndex: Int
        public var sectionCount: Int
        /// Questions in the open block, which is what the ring fills against.
        public var sectionTotal: Int
        public var revealsAnswers: Bool

        public init(
            answered: Int,
            correct: Int = 0,
            wrong: Int = 0,
            currentNumber: Int,
            endDate: Date,
            sectionLabel: String? = nil,
            sectionIndex: Int = 0,
            sectionCount: Int = 1,
            sectionTotal: Int = 0,
            revealsAnswers: Bool = false
        ) {
            self.answered = max(answered, 0)
            self.correct = max(correct, 0)
            self.wrong = max(wrong, 0)
            self.currentNumber = max(currentNumber, 1)
            self.endDate = endDate
            self.sectionLabel = sectionLabel
            self.sectionIndex = max(sectionIndex, 0)
            self.sectionCount = max(sectionCount, 1)
            self.sectionTotal = max(sectionTotal, 0)
            self.revealsAnswers = revealsAnswers
        }

        public var isSectioned: Bool { sectionCount > 1 }
    }

    public var sittingName: String
    public var subject: String
    public var totalQuestions: Int
    public var accentHex: String

    public init(sittingName: String, subject: String, totalQuestions: Int, accentHex: String) {
        self.sittingName = sittingName
        self.subject = subject
        self.totalQuestions = totalQuestions
        self.accentHex = accentHex
    }
}

/// Offline download progress on the Lock Screen and in the Dynamic Island.
public struct MedxDownloadActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var completedSegments: Int
        public var totalSegments: Int
        public var fraction: Double
        public var statusText: String
        public var isFinished: Bool
        /// Drives which of the two buttons the activity shows. The intents that back them run in
        /// the app, so this is the extension's only knowledge of what state the download is in.
        public var isPaused: Bool
        /// Seconds left, when enough segments have landed to estimate one. `nil` early on rather
        /// than a wild guess — an ETA that swings from 2 minutes to 40 is worse than none.
        public var secondsRemaining: Int?

        public init(
            completedSegments: Int,
            totalSegments: Int,
            fraction: Double,
            statusText: String,
            isFinished: Bool,
            isPaused: Bool = false,
            secondsRemaining: Int? = nil
        ) {
            self.completedSegments = completedSegments
            self.totalSegments = totalSegments
            self.fraction = min(max(fraction, 0), 1)
            self.statusText = statusText
            self.isFinished = isFinished
            self.isPaused = isPaused
            self.secondsRemaining = secondsRemaining
        }
    }

    public var title: String
    public var subject: String
    public var accentHex: String
    /// `RecordedVideo.id`, so the activity's buttons can name the download they act on.
    public var videoId: String

    public init(title: String, subject: String, accentHex: String, videoId: String) {
        self.title = title
        self.subject = subject
        self.accentHex = accentHex
        self.videoId = videoId
    }
}

// MARK: - Faceoff Live Activity

/// A live duel on the Lock Screen and in the Dynamic Island.
///
/// The point of this one is the *score*: mid-duel you want to know whether you are ahead without
/// unlocking, and the compact island reading `12–9` with the round clock beside it is the whole
/// feature. Both duel colours travel as hex, because the versus bar is two-toned and an extension
/// cannot resolve the app's palette.
public struct MedxDuelActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var qIndex: Int
        public var myPoints: Int
        public var theirPoints: Int
        /// `MedxDuelPhase.rawValue`. Carried as a string so the extension does not need the enum.
        public var phase: String
        /// End of the *round's* minute, handed over so the system ticks it.
        public var roundEndDate: Date

        public init(qIndex: Int, myPoints: Int, theirPoints: Int, phase: String, roundEndDate: Date) {
            self.qIndex = max(qIndex, 0)
            self.myPoints = max(myPoints, 0)
            self.theirPoints = max(theirPoints, 0)
            self.phase = phase
            self.roundEndDate = roundEndDate
        }

        /// My share of the points on the board. Level pegging — including 0–0 before the first
        /// question — splits down the middle rather than collapsing to one side.
        public var myShare: Double {
            let total = myPoints + theirPoints
            return total > 0 ? Double(myPoints) / Double(total) : 0.5
        }

        public var isArming: Bool { phase == "arming" }
        public var isRevealed: Bool { phase == "reveal" }
    }

    public var myName: String
    public var theirName: String
    public var myHex: String
    public var theirHex: String
    public var totalQuestions: Int
    public var sourceName: String

    public init(
        myName: String,
        theirName: String,
        myHex: String,
        theirHex: String,
        totalQuestions: Int,
        sourceName: String
    ) {
        self.myName = myName
        self.theirName = theirName
        self.myHex = myHex
        self.theirHex = theirHex
        self.totalQuestions = totalQuestions
        self.sourceName = sourceName
    }
}

// MARK: - Hex colour parsing
// Kept here as plain numbers rather than a `Color`, so the widget target does not have to
// import the app's theme just to tint a ring.
public extension String {
    /// `#RRGGBB` (or `RRGGBB`) → unit red/green/blue. Falls back to system blue.
    var medxRGBComponents: (red: Double, green: Double, blue: Double) {
        let hex = trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        guard hex.count == 6, Scanner(string: hex).scanHexInt64(&value) else {
            return (0.039, 0.518, 1.0)
        }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }
}
