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
        VStack(alignment: .leading, spacing: 12) {
            header
            chips

            if let prior = test.priorAttempt, prior.status == "COMPLETED" {
                priorAttemptLine(prior)
            }

            if let bestAttempt {
                historyLine(best: bestAttempt)
            }

            if !test.gradable {
                Text("Not scored — the source app withheld this paper's answer key, so it can be answered for practice only.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            startButton
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medxCard()
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
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(test.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(metaLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if !testAttempts.isEmpty {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(MedxTheme.successGreen)
                    .accessibilityLabel("Already attempted")
            }
        }
    }

    private var chips: some View {
        HStack(spacing: 6) {
            if let mode = test.mode, !mode.isEmpty {
                MedxChip(mode.capitalized, tint: MedxTheme.primaryBlue)
            }
            MedxChip(
                test.gradable ? "Answer key" : "No key",
                icon: test.gradable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                tint: test.gradable ? MedxTheme.successGreen : MedxTheme.warningOrange
            )
            if let batch = test.batch, !batch.isEmpty {
                MedxChip(batch, tint: MedxTheme.indigoAccent)
            }
            Spacer(minLength: 0)
        }
    }

    private func priorAttemptLine(_ prior: PriorAttemptInfo) -> some View {
        var text = "On Arise: \(prior.correct ?? 0)/\(prior.questionCount ?? 0)"
        if let rank = prior.testRank { text += " · rank \(rank)" }

        return Label(text, systemImage: "clock.arrow.circlepath")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func historyLine(best: SittingAttempt) -> some View {
        let detail = test.gradable
            ? "Best \(bestScore)/\(best.total) (\(best.totalPercentage)%)"
            : "Best \(best.attempted)/\(best.total) answered"

        return Label(
            "\(testAttempts.count) sitting\(testAttempts.count == 1 ? "" : "s") · \(detail)",
            systemImage: "chart.bar.fill"
        )
        .font(.caption)
        .foregroundStyle(MedxTheme.successGreen)
    }

    private var startButton: some View {
        Button {
            HapticManager.light()
            showStartSheet = true
        } label: {
            Text(testAttempts.isEmpty ? "Begin Test" : "Reattempt")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(test.gradable ? Color.accentColor : MedxTheme.warningOrange)
        .padding(.top, 2)
    }
}
