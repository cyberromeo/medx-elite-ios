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
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Open the question bank")
            }

            HStack(spacing: 20) {
                ProgressRingView(
                    progress: coverage,
                    strokeWidth: 8,
                    size: 88,
                    tint: .accentColor,
                    centerContent: AnyView(
                        VStack(spacing: 0) {
                            Text("\(Int((coverage * 100).rounded()))%")
                                .font(.headline.weight(.bold).monospacedDigit())
                            Text("seen")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    )
                )

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(current.unique.formatted())
                                .font(.title3.weight(.semibold).monospacedDigit())
                            Text("of \(totalQuestions.formatted())")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text("questions attempted")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 18) {
                        figure(value: current.answered > 0 ? "\(accuracy)%" : "—", label: "accuracy")
                        figure(value: "\(current.sittings)", label: "sittings")
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medxCard(cornerRadius: 20)
    }

    private func figure(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }
}
