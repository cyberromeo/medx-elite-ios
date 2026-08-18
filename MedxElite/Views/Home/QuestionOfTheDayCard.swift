import SwiftUI

public struct QuestionOfTheDayCard: View {
    @State private var qod: QODData?
    @State private var isLoading = true
    @State private var pickedAnswerId: Int?
    @State private var showExplanation = true

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundColor(MedxTheme.primaryPurple)
                    Text("Question of the Day")
                        .font(MedxFont.headline(17))
                }

                Spacer()

                if let subj = qod?.subject, !subj.isEmpty {
                    Text(subj)
                        .font(MedxFont.label(12))
                        .foregroundColor(MedxTheme.primaryPurple)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(MedxTheme.primaryPurple.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(20)
                    Spacer()
                }
            } else if let data = qod {
                // Question Text
                if let qHtml = data.question {
                    HTMLRichTextView(html: qHtml, fontSize: 16, weight: .semibold)
                }

                // Options List
                let answers = data.answers ?? []
                let correctId = data.correctChoiceId
                let isAnswered = pickedAnswerId != nil

                VStack(spacing: 10) {
                    ForEach(Array(answers.enumerated()), id: \.element.id) { index, ans in
                        let isChosen = ans.answerId == pickedAnswerId
                        let isCorrect = ans.answerId == correctId
                        let letter = String(UnicodeScalar(65 + index)!)

                        Button {
                            if !isAnswered {
                                HapticManager.selection()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                    pickedAnswerId = ans.answerId
                                }
                                if isCorrect {
                                    HapticManager.success()
                                } else {
                                    HapticManager.error()
                                }
                            }
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                Text(letter)
                                    .font(MedxFont.mono(14, weight: .bold))
                                    .foregroundColor(optionLetterColor(isAnswered: isAnswered, isCorrect: isCorrect, isChosen: isChosen))
                                    .frame(width: 28, height: 28)
                                    .background(optionLetterBackground(isAnswered: isAnswered, isCorrect: isCorrect, isChosen: isChosen))
                                    .clipShape(Circle())

                                if let ansText = ans.answer {
                                    HTMLRichTextView(html: ansText, fontSize: 15, weight: .regular)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .layoutPriority(1)
                                }

                                Spacer(minLength: 0)

                                if isAnswered {
                                    if isCorrect {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(MedxTheme.successGreen)
                                    } else if isChosen {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(MedxTheme.destructiveRed)
                                    }
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
                            .background(optionRowBackground(isAnswered: isAnswered, isCorrect: isCorrect, isChosen: isChosen))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(optionBorderColor(isAnswered: isAnswered, isCorrect: isCorrect, isChosen: isChosen), lineWidth: 1.5)
                            )
                            .medxNavigationGlass(
                                cornerRadius: 14,
                                tint: isCorrect && isAnswered ? MedxTheme.successGreen : (isChosen ? MedxTheme.destructiveRed : nil),
                                interactive: true
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isAnswered)
                    }
                }

                // Explanation Accordion
                if isAnswered, let expl = data.ansExplanation, !expl.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Button {
                            HapticManager.selection()
                            withAnimation(.spring()) {
                                showExplanation.toggle()
                            }
                        } label: {
                            HStack {
                                Label("Explanation", systemImage: "text.book.closed")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: showExplanation ? "chevron.up" : "chevron.down")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(showExplanation ? "Hide explanation" : "Show explanation")
                        .accessibilityHint("Reveals the answer explanation")

                        if showExplanation {
                            HTMLRichTextView(html: expl, fontSize: 14, weight: .regular, textColor: .secondary)
                                .padding(.top, 4)
                        }
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            } else {
                Text("Couldn't load today's question.")
                    .font(MedxFont.body(14))
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .liquidGlassCard(cornerRadius: 24, glowColor: MedxTheme.primaryPurple)
        .task {
            do {
                self.qod = try await QODService.shared.fetchQuestionOfTheDay()
                self.isLoading = false
            } catch {
                self.isLoading = false
            }
        }
    }

    private func optionLetterColor(isAnswered: Bool, isCorrect: Bool, isChosen: Bool) -> Color {
        if !isAnswered { return .primary }
        if isCorrect { return .white }
        if isChosen { return .white }
        return .secondary
    }

    private func optionLetterBackground(isAnswered: Bool, isCorrect: Bool, isChosen: Bool) -> Color {
        if !isAnswered { return Color.primary.opacity(0.08) }
        if isCorrect { return MedxTheme.successGreen }
        if isChosen { return MedxTheme.destructiveRed }
        return Color.primary.opacity(0.04)
    }

    private func optionRowBackground(isAnswered: Bool, isCorrect: Bool, isChosen: Bool) -> Color {
        if !isAnswered { return Color.primary.opacity(0.03) }
        if isCorrect { return MedxTheme.successGreen.opacity(0.12) }
        if isChosen { return MedxTheme.destructiveRed.opacity(0.12) }
        return Color.primary.opacity(0.02)
    }

    private func optionBorderColor(isAnswered: Bool, isCorrect: Bool, isChosen: Bool) -> Color {
        if !isAnswered { return Color.primary.opacity(0.06) }
        if isCorrect { return MedxTheme.successGreen.opacity(0.5) }
        if isChosen { return MedxTheme.destructiveRed.opacity(0.5) }
        return Color.clear
    }
}
