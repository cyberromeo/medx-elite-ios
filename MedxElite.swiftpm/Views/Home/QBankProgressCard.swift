import SwiftUI

/// Question-bank coverage: how much of the bank has been seen, and how well.
public struct QBankProgressCard: View {
    public let attempts: [SittingAttempt]
    public let totalQuestions: Int
    public var onOpenQBank: () -> Void

    public init(attempts: [SittingAttempt], totalQuestions: Int = 17_890, onOpenQBank: @escaping () -> Void) {
        self.attempts = attempts
        self.totalQuestions = totalQuestions
        self.onOpenQBank = onOpenQBank
    }

    private struct Stats {
        var unique = 0
        var answered = 0
        var correct = 0
        var sittings = 0
    }

    private var stats: Stats {
        var result = Stats()
        var seen = Set<Int>()

        for attempt in attempts where attempt.kind == "qbank" {
            result.sittings += 1
            for response in attempt.responses where response.chosenId != nil {
                result.answered += 1
                if response.correct { result.correct += 1 }
                seen.insert(response.questionId)
            }
        }

        result.unique = seen.count
        return result
    }

    public var body: some View {
        let current = stats
        let coverage = totalQuestions > 0 ? Double(current.unique) / Double(totalQuestions) : 0
        let accuracy = current.answered > 0
            ? Int((Double(current.correct) / Double(current.answered) * 100).rounded())
            : 0

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Question bank")
                    .font(.headline)

                Spacer()

                Button {
                    HapticManager.light()
                    onOpenQBank()
                } label: {
                    HStack(spacing: 3) {
                        Text("Open")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(MedxTheme.accent)
                .accessibilityLabel("Open the question bank")
            }

            // A ring with a percentage inside it next to the same coverage as a figure was the same
            // number three ways. The sheet says it once, and says *how much* of the bank is left in a
            // way a percentage cannot.
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(current.unique.formatted())
                        .font(MedxType.display)
                        .contentTransition(.numericText())
                    Text("of \(totalQuestions.formatted()) attempted")
                        .medxTag()
                    Spacer(minLength: 0)
                }

                MedxAnswerSheet(
                    fraction: coverage,
                    scale: .sheet,
                    label: "\(Int((coverage * 100).rounded())) percent of the bank seen"
                )

                HStack(alignment: .top, spacing: 10) {
                    MedxStat(current.answered > 0 ? "\(accuracy)%" : "—", label: "accuracy",
                             tint: current.answered > 0 ? MedxDS.correct : nil)
                    MedxStat("\(current.sittings)", label: "sittings")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
