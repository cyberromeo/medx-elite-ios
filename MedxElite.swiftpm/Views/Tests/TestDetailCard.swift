import SwiftUI

/// One batch paper, as a row: what it is, what happened last time, and the mode picker on a
/// tap. Kept under the name it had as a card — `BatchPapersView` is its only caller.
public struct TestDetailCard: View {
    public let test: BatchTest
    public let attempts: [SittingAttempt]
    public var onStart: (SittingMode) -> Void

    @State private var showStartSheet = false
    /// The pick made inside the mode sheet, started once the sheet has gone — see
    /// `StartSessionSheet` for why not sooner.
    @State private var pendingMode: SittingMode?

    public init(test: BatchTest, attempts: [SittingAttempt], onStart: @escaping (SittingMode) -> Void) {
        self.test = test
        self.attempts = attempts
        self.onStart = onStart
    }

    private var testAttempts: [SittingAttempt] {
        attempts.filter { $0.sourceId == test.testId }
    }

    private var bestAttempt: SittingAttempt? {
        testAttempts.max { $0.score < $1.score }
    }

    private var metaLine: String {
        var parts: [String] = []
        if !test.subject.isEmpty { parts.append(test.subject) }
        parts.append("\(test.questionCount) questions")
        if test.officialTimeMins > 0 { parts.append("\(test.officialTimeMins) min") }
        return parts.joined(separator: " · ")
    }

    private var historyLine: String? {
        guard let best = bestAttempt else { return nil }
        let sittings = testAttempts.count == 1 ? "1 sitting" : "\(testAttempts.count) sittings"
        let detail = test.gradable
            ? "best \(best.score) of \(best.total)"
            : "best \(best.attempted) of \(best.total) answered"
        return "\(sittings) · \(detail)"
    }

    private var priorLine: String? {
        guard let prior = test.priorAttempt, prior.status == "COMPLETED" else { return nil }
        var text = "On Arise: \(prior.correct ?? 0) of \(prior.questionCount ?? 0)"
        if let rank = prior.testRank { text += " · rank \(rank)" }
        return text
    }

    private var examDetail: String {
        let minutes = test.officialTimeMins > 0 ? test.officialTimeMins : test.questionCount
        return test.gradable
            ? "One \(minutes)-minute clock, the paper's official time. Answers after you submit."
            : "One \(minutes)-minute clock. Not scored: the source withheld this paper's key."
    }

    private var revisionDetail: String? {
        test.gradable ? nil : "60 seconds a question. With no key, nothing is marked right or wrong."
    }

    public var body: some View {
        Button {
            HapticManager.light()
            showStartSheet = true
        } label: {
            HStack(spacing: MedxSpace.m) {
                MedxSymbolTile(
                    test.gradable ? "checkmark.seal.fill" : "doc.text.fill",
                    hue: test.gradable ? MedxFeature.batchPapers.color : MedxOutcome.pending,
                    size: 36
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(test.name)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(metaLine)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let historyLine {
                        Text(historyLine)
                            .font(.footnote)
                            .foregroundStyle(MedxOutcome.correct)
                    } else if let priorLine {
                        Text(priorLine)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: MedxSpace.s)

                if !testAttempts.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(MedxOutcome.correct)
                        .accessibilityLabel("Already attempted")
                }

                MedxRowChevron()
            }
            .padding(.vertical, 2)
            .foregroundStyle(Color.primary)
        }
        .contextMenu {
            Button {
                HapticManager.medium()
                onStart(.revision)
            } label: {
                Label("Revision mode", systemImage: "bolt")
            }
            Button {
                HapticManager.medium()
                onStart(.exam)
            } label: {
                Label("Exam mode", systemImage: "timer")
            }
        }
        .sheet(isPresented: $showStartSheet, onDismiss: startPending) {
            StartSessionSheet(
                title: test.name,
                subtitle: test.subject,
                questionCount: test.questionCount,
                examDetail: examDetail,
                revisionDetail: revisionDetail
            ) { mode in
                pendingMode = mode
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(test.name)
        .accessibilityValue(metaLine)
        .accessibilityHint("Opens the mode picker")
    }

    private func startPending() {
        guard let mode = pendingMode else { return }
        pendingMode = nil
        onStart(mode)
    }
}
