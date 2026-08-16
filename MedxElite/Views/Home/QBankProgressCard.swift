import SwiftUI

public struct QBankProgressCard: View {
    public let attempts: [SittingAttempt]
    public let totalQuestions: Int
    public var onOpenQBank: () -> Void

    public init(attempts: [SittingAttempt], totalQuestions: Int = 17890, onOpenQBank: @escaping () -> Void) {
        self.attempts = attempts
        self.totalQuestions = totalQuestions
        self.onOpenQBank = onOpenQBank
    }

    private var stats: (unique: Int, answered: Int, correct: Int, sittings: Int) {
        var seen = Set<Int>()
        var answered = 0
        var correct = 0
        var qbSittings = 0

        for a in attempts where a.kind == "qbank" {
            qbSittings += 1
            for r in a.responses {
                if r.chosenId != nil {
                    answered += 1
                    if r.correct { correct += 1 }
                    seen.insert(r.questionId)
                }
            }
        }
        return (unique: seen.count, answered: answered, correct: correct, sittings: qbSittings)
    }

    public var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Question Bank")
                    .font(MedxFont.headline(16))

                Spacer()

                Button(action: {
                    HapticManager.light()
                    onOpenQBank()
                }) {
                    HStack(spacing: 4) {
                        Text("Open")
                            .font(MedxFont.headline(14))
                        Image(systemName: "arrow.right")
                            .font(.caption)
                    }
                    .foregroundColor(MedxTheme.primaryBlue)
                }
            }

            let percentage = totalQuestions > 0 ? Double(stats.unique) / Double(totalQuestions) : 0.0
            let accuracy = stats.answered > 0 ? Int(round(Double(stats.correct) / Double(stats.answered) * 100.0)) : 0

            HStack(spacing: 20) {
                ProgressRingView(
                    progress: percentage,
                    strokeWidth: 9,
                    size: 96,
                    gradient: LinearGradient(
                        colors: [MedxTheme.primaryBlue, MedxTheme.cyanAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    centerContent: AnyView(
                        VStack(spacing: 0) {
                            Text("\(Int(percentage * 100))%")
                                .font(MedxFont.mono(18, weight: .heavy))
                            Text("coverage")
                                .font(MedxFont.label(9))
                                .foregroundColor(.secondary)
                        }
                    )
                )

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text("\(stats.unique.formatted())")
                                .font(MedxFont.mono(20, weight: .bold))
                            Text("/ \(totalQuestions.formatted())")
                                .font(MedxFont.caption(13))
                                .foregroundColor(.secondary)
                        }
                        Text("questions attempted")
                            .font(MedxFont.caption(12))
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(accuracy)%")
                                .font(MedxFont.mono(16, weight: .bold))
                                .foregroundColor(MedxTheme.successGreen)
                            Text("accuracy")
                                .font(MedxFont.label(11))
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(stats.sittings)")
                                .font(MedxFont.mono(16, weight: .bold))
                                .foregroundColor(MedxTheme.primaryBlue)
                            Text("sittings")
                                .font(MedxFont.label(11))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()
            }
        }
        .padding(20)
        .liquidGlassCard(cornerRadius: 24, glowColor: MedxTheme.primaryBlue)
    }
}
