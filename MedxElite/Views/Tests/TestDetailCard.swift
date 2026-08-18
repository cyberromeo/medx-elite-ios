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
                        .font(MedxFont.headline(17))
                        .foregroundColor(.primary)

                    Text("\(test.subject) · \(test.questionCount) questions · \(test.officialTimeMins) mins")
                        .font(MedxFont.caption(13))
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
                        .font(MedxFont.label(11))
                        .foregroundColor(MedxTheme.primaryBlue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(MedxTheme.primaryBlue.opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(test.gradable ? "Answer Key" : "Practice Only")
                    .font(MedxFont.label(11))
                    .foregroundColor(test.gradable ? MedxTheme.successGreen : MedxTheme.warningOrange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((test.gradable ? MedxTheme.successGreen : MedxTheme.warningOrange).opacity(0.12))
                    .clipShape(Capsule())
            }

            if !test.gradable {
                Text("The source app withheld the official answer key for this test, so it can be answered for practice but isn't scored.")
                    .font(MedxFont.caption(12))
                    .foregroundColor(.secondary)
            }

            if let prior = test.priorAttempt, prior.status == "COMPLETED" {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                    Text("On Arise: \(prior.correct ?? 0)/\(prior.questionCount ?? 0)\(prior.testRank != nil ? " · rank \(prior.testRank!)" : "")")
                        .font(MedxFont.label(12))
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
                                .font(MedxFont.mono(11, weight: .bold))
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
                if #available(iOS 26.0, *) {
                    Button {
                        HapticManager.light()
                        showStartSheet = true
                    } label: {
                        Text(testAttempts.isEmpty ? "Begin Test" : "Reattempt")
                            .font(.body.weight(.semibold))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(MedxTheme.primaryBlue)
                } else {
                    Button {
                        HapticManager.light()
                        showStartSheet = true
                    } label: {
                        Text(testAttempts.isEmpty ? "Begin Test" : "Reattempt")
                            .font(.body.weight(.semibold))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MedxTheme.primaryBlue)
                }
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
