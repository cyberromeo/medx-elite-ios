import SwiftUI

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
        attempts.filter { $0.sourceId == test.testId }
            .sorted { ($0.finishedAt ?? "") < ($1.finishedAt ?? "") }
    }

    private var bestScore: Int {
        testAttempts.reduce(0) { max($0, $1.score) }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(test.name)
                        .font(MedxFont.rounded(17, weight: .bold))
                        .foregroundColor(.primary)

                    Text("\(test.subject) · \(test.questionCount) questions · \(test.officialTimeMins) mins")
                        .font(MedxFont.rounded(13, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !testAttempts.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(MedxTheme.successGreen)
                }
            }

            // Tags
            HStack(spacing: 8) {
                if let mode = test.mode {
                    Text(mode)
                        .font(MedxFont.rounded(11, weight: .bold))
                        .foregroundColor(MedxTheme.primaryBlue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(MedxTheme.primaryBlue.opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(test.gradable ? "Answer Key" : "Practice Only")
                    .font(MedxFont.rounded(11, weight: .bold))
                    .foregroundColor(test.gradable ? MedxTheme.successGreen : MedxTheme.warningOrange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((test.gradable ? MedxTheme.successGreen : MedxTheme.warningOrange).opacity(0.12))
                    .clipShape(Capsule())
            }

            if !test.gradable {
                Text("The source app withheld the official answer key for this test, so it can be answered for practice but isn't scored.")
                    .font(MedxFont.rounded(12, weight: .regular))
                    .foregroundColor(.secondary)
            }

            if let prior = test.priorAttempt, prior.status == "COMPLETED" {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                    Text("On Arise: \(prior.correct ?? 0)/\(prior.questionCount ?? 0)\(prior.testRank != nil ? " · rank \(prior.testRank!)" : "")")
                        .font(MedxFont.rounded(12, weight: .medium))
                }
                .foregroundColor(.secondary)
            }

            // Attempt History Chips
            if !testAttempts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(testAttempts.enumerated()), id: \.offset) { idx, a in
                            let isBest = a.score == bestScore && test.gradable
                            Text("attempt#\(idx + 1) \(test.gradable ? "\(a.score)/\(a.total)" : "\(a.attempted)/\(a.total) answered")")
                                .font(MedxFont.monospacedDigits(11, weight: .bold))
                                .foregroundColor(isBest ? MedxTheme.successGreen : .secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(isBest ? MedxTheme.successGreen.opacity(0.15) : Color.primary.opacity(0.06))
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            // Action Button
            HStack {
                Spacer()
                Button {
                    HapticManager.light()
                    showStartSheet = true
                } label: {
                    Text(testAttempts.isEmpty ? "Begin Test" : "Reattempt")
                        .font(MedxFont.rounded(14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(MedxTheme.primaryBlue)
                        .clipShape(Capsule())
                }
                .buttonStyle(BouncyButtonStyle())
            }
        }
        .padding(18)
        .liquidGlassCard(cornerRadius: 20)
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
}
