import AppIntents
import Foundation

// MARK: - Intents
//
// Three Siri / Shortcuts entry points. Each one hands a `MedxRoute` to `AppState` and lets
// the UI decide what that means, so there is no second copy of the navigation rules here.
// `perform()` hops to the main actor explicitly rather than being annotated, which keeps the
// witness to the protocol requirement plain.

public struct MedxStartRevisionIntent: AppIntent {
    public static var title: LocalizedStringResource { "Start today's revision" }

    public static var description: IntentDescription {
        IntentDescription(
            "Builds a sitting from the modules your spaced-revision schedule says are due today."
        )
    }

    public static var openAppWhenRun: Bool { true }

    public init() {}

    public func perform() async throws -> some IntentResult {
        await MainActor.run {
            AppState.shared.open(route: .todaysRevision)
        }
        return .result()
    }
}

public struct MedxSearchQuestionsIntent: AppIntent {
    public static var title: LocalizedStringResource { "Search questions" }

    public static var description: IntentDescription {
        IntentDescription("Opens question search across the whole bank.")
    }

    public static var openAppWhenRun: Bool { true }

    /// Optional on purpose: with no text Siri simply opens search rather than interrogating
    /// the student for a term before the app is even on screen.
    @Parameter(title: "Search text")
    public var query: String?

    public init() {}

    public func perform() async throws -> some IntentResult {
        let seed = query
        await MainActor.run {
            AppState.shared.open(route: .search(seed))
        }
        return .result()
    }
}

/// Answers out loud without launching the app — it only needs the shared snapshot, which
/// the app keeps up to date for the widgets anyway.
public struct MedxExamCountdownIntent: AppIntent {
    public static var title: LocalizedStringResource { "Exam countdown" }

    public static var description: IntentDescription {
        IntentDescription("Tells you how long is left before the exam, and today's progress.")
    }

    public static var openAppWhenRun: Bool { false }

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = MedxSharedStore.loadOrDefault()
        let days = snapshot.daysRemaining()

        let lead: String
        switch days {
        case 0: lead = "\(snapshot.examName) is today."
        case 1: lead = "1 day until \(snapshot.examName)."
        default: lead = "\(days) days until \(snapshot.examName)."
        }

        let progress = snapshot.isGoalMet
            ? "Today's goal of \(snapshot.dailyGoal) is done."
            : "\(snapshot.remainingToGoal) questions left of today's goal."

        return .result(dialog: IntentDialog("\(lead) \(progress)"))
    }
}

// MARK: - Donated shortcuts

public struct MedxShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MedxStartRevisionIntent(),
            phrases: [
                "Start today's revision in \(.applicationName)",
                "Start my revision in \(.applicationName)",
                "Revise with \(.applicationName)"
            ],
            shortTitle: "Today's revision",
            systemImageName: "arrow.triangle.2.circlepath"
        )

        AppShortcut(
            intent: MedxExamCountdownIntent(),
            phrases: [
                "How long until my exam in \(.applicationName)",
                "\(.applicationName) exam countdown"
            ],
            shortTitle: "Exam countdown",
            systemImageName: "calendar.badge.clock"
        )

        AppShortcut(
            intent: MedxSearchQuestionsIntent(),
            phrases: [
                "Search questions in \(.applicationName)",
                "Find a question in \(.applicationName)"
            ],
            shortTitle: "Search questions",
            systemImageName: "magnifyingglass"
        )
    }
}
