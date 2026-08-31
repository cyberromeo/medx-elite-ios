import SwiftUI

/// One batch-test row. Flat card, one primary action, and the history collapsed into a
/// single line instead of a scrolling strip of pills.
public struct TestDetailCard: View {
    public let test: BatchTest
    public let attempts: [SittingAttempt]
    public var onStart: (SittingMode) -> Void

    @State private var showStartSheet = false

    public init(test: BatchTest, attempts: [SittingAttempt], onStart: @escaping (SittingMode) -> Void) {
        self.test = test
        self.attempts = attempts
        self.onStart = onStart
    }

    private var testAttempts: [SittingAttempt] {
        attempts
            .filter { $0.sourceId == test.testId }
            .sorted { ($0.finishedAt ?? "") < ($1.finishedAt ?? "") }
    }

    private var bestScore: Int {
        testAttempts.reduce(0) { max($0, $1.score) }
    }

    private var bestAttempt: SittingAttempt? {
        testAttempts.max { $0.score < $1.score }
    }

    private var metaLine: String {
        var parts: [String] = []
        if !test.subject.isEmpty { parts.append(test.subject) }
        parts.append("\(test.questionCount) questions")
        parts.append("\(test.officialTimeMins) min")
        return parts.joined(separator: " · ")
    }

    public var body: some View {
        Button {
            HapticManager.light()
            showStartSheet = true
        } label: {
            MedxRow(
                lead: "\(test.questionCount)",
                title: test.name,
                tag: test.gradable ? test.subject : "no key",
                detail: detailLine
            ) {
                if let bestAttempt {
                    MedxAnswerSheet(
                        fraction: Double(test.gradable ? bestScore : bestAttempt.attempted)
                            / Double(max(bestAttempt.total, 1)),
                        label: detailLine
                    )
                } else {
                    MedxChevron()
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                HapticManager.light()
                showStartSheet = true
            } label: {
                Label(testAttempts.isEmpty ? "Begin test" : "Reattempt", systemImage: "play.circle")
            }
            Button {
                HapticManager.medium()
                onStart(.revision)
            } label: {
                Label("Start in Revision mode", systemImage: "bolt")
            }
            Button {
                HapticManager.medium()
                onStart(.exam)
            } label: {
                Label("Start in Exam mode", systemImage: "timer")
            }
        }
        .sheet(isPresented: $showStartSheet) {
            StartSessionSheet(
                title: test.name,
                subtitle: test.subject,
                questionCount: test.questionCount
            ) { mode in
                onStart(mode)
            }
        }
        .accessibilityLabel(test.name)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Opens the mode picker")
    }

    // MARK: - Lines
    //
    // Four stacked lines, three chips and a full-width button became one row and its strip. Everything
    // that is gone was either said twice — the question count was in `metaLine` *and* in the history
    // line — or was a chip restating a field the row already carries. The button went because the row
    // itself opens the mode picker, which is what the button did.

    private var detailLine: String {
        guard let best = bestAttempt else {
            return "\(test.officialTimeMins) min · not attempted"
        }
        let score = test.gradable
            ? "best \(bestScore)/\(best.total)"
            : "best \(best.attempted)/\(best.total) answered"
        let sittings = "\(testAttempts.count) sitting\(testAttempts.count == 1 ? "" : "s")"
        return "\(score) · \(sittings)"
    }

    private var accessibilityValue: String {
        var parts = [metaLine]
        if !test.gradable {
            parts.append("no official answer key, practice only")
        }
        if let prior = test.priorAttempt, prior.status == "COMPLETED" {
            parts.append("on Arise \(prior.correct ?? 0) of \(prior.questionCount ?? 0)")
        }
        parts.append(detailLine)
        return parts.joined(separator: ", ")
    }
}
