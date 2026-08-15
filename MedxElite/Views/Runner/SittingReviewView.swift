import SwiftUI

public enum ReviewFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case wrong = "Wrong"
    case skipped = "Skipped"

    public var id: String { rawValue }
}

public struct SittingReviewView: View {
    public let name: String
    public let subject: String?
    public let questions: [Question]
    public let responses: [Int: QuestionResponse]
    public let gradable: Bool
    public var onDone: () -> Void

    @State private var filter: ReviewFilter = .all

    public init(
        name: String,
        subject: String?,
        questions: [Question],
        responses: [Int: QuestionResponse],
        gradable: Bool,
        onDone: @escaping () -> Void
    ) {
        self.name = name
        self.subject = subject
        self.questions = questions
        self.responses = responses
        self.gradable = gradable
        self.onDone = onDone
    }

    private var totalCount: Int { questions.count }
    private var scoreCount: Int { responses.values.filter { $0.correct }.count }
    private var attemptedCount: Int { responses.values.filter { $0.chosenId != nil }.count }
    private var wrongCount: Int { attemptedCount - scoreCount }
    private var skippedCount: Int { totalCount - attemptedCount }

    private var filteredQuestions: [Question] {
        questions.filter { q in
            let r = responses[q.id]
            switch filter {
            case .all: return true
            case .wrong: return r?.chosenId != nil && r?.correct == false
            case .skipped: return r == nil || r?.chosenId == nil
            }
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Score Summary Card
                        VStack(spacing: 16) {
                            if gradable {
                                let pct = totalCount > 0 ? Int(round(Double(scoreCount) / Double(totalCount) * 100.0)) : 0

                                HStack(spacing: 24) {
                                    ProgressRingView(
                                        progress: Double(scoreCount) / Double(max(totalCount, 1)),
                                        strokeWidth: 10,
                                        size: 100,
                                        gradient: LinearGradient(
                                            colors: [MedxTheme.successGreen, MedxTheme.cyanAccent],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        centerContent: AnyView(
                                            VStack(spacing: 0) {
                                                Text("\(pct)%")
                                                    .font(MedxFont.monospacedDigits(22, weight: .heavy))
                                                Text("score")
                                                    .font(MedxFont.rounded(10, weight: .bold))
                                                    .foregroundColor(.secondary)
                                            }
                                        )
                                    )

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("\(scoreCount) / \(totalCount)")
                                            .font(MedxFont.monospacedDigits(26, weight: .black))

                                        HStack(spacing: 12) {
                                            Label("\(scoreCount) correct", systemImage: "checkmark.circle.fill")
                                                .font(MedxFont.rounded(12, weight: .bold))
                                                .foregroundColor(MedxTheme.successGreen)

                                            Label("\(wrongCount) wrong", systemImage: "xmark.circle.fill")
                                                .font(MedxFont.rounded(12, weight: .bold))
                                                .foregroundColor(MedxTheme.destructiveRed)
                                        }

                                        if skippedCount > 0 {
                                            Text("\(skippedCount) unattempted")
                                                .font(MedxFont.rounded(12, weight: .medium))
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Practice Complete")
                                        .font(MedxFont.rounded(22, weight: .bold))
                                    Text("This paper has no official answer key and is not graded. You completed \(attemptedCount) of \(totalCount) questions.")
                                        .font(MedxFont.rounded(14, weight: .regular))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(20)
                        .liquidGlassCard(cornerRadius: 24, glowColor: MedxTheme.successGreen)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)

                        // Segmented Filter Picker
                        Picker("Filter", selection: $filter) {
                            Text("All (\(totalCount))").tag(ReviewFilter.all)
                            Text("Wrong (\(wrongCount))").tag(ReviewFilter.wrong)
                            Text("Skipped (\(skippedCount))").tag(ReviewFilter.skipped)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)

                        // Question Review List
                        LazyVStack(spacing: 16) {
                            ForEach(Array(filteredQuestions.enumerated()), id: \.element.id) { idx, q in
                                let r = responses[q.id]
                                let originalIndex = (questions.firstIndex(where: { $0.id == q.id }) ?? 0) + 1

                                QuestionReviewCard(
                                    questionNumber: originalIndex,
                                    question: q,
                                    response: r
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        HapticManager.medium()
                        onDone()
                    }
                    .font(MedxFont.rounded(16, weight: .bold))
                }
            }
        }
    }
}

private struct QuestionReviewCard: View {
    let questionNumber: Int
    let question: Question
    let response: QuestionResponse?
    @State private var isExplanationExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header status
            HStack {
                Text("Question \(questionNumber)")
                    .font(MedxFont.rounded(15, weight: .bold))

                Spacer()

                if let r = response, r.chosenId != nil {
                    if r.correct {
                        Label("Correct", systemImage: "checkmark.circle.fill")
                            .font(MedxFont.rounded(12, weight: .bold))
                            .foregroundColor(MedxTheme.successGreen)
                    } else {
                        Label("Incorrect", systemImage: "xmark.circle.fill")
                            .font(MedxFont.rounded(12, weight: .bold))
                            .foregroundColor(MedxTheme.destructiveRed)
                    }
                } else {
                    Label("Unattempted", systemImage: "minus.circle.fill")
                        .font(MedxFont.rounded(12, weight: .bold))
                        .foregroundColor(MedxTheme.warningOrange)
                }
            }

            // Question text
            HTMLRichTextView(html: question.displayText, font: MedxFont.rounded(15, weight: .medium))

            // Images if any
            if let imgs = question.images, !imgs.isEmpty {
                ForEach(imgs, id: \.self) { imgUrl in
                    CachedAsyncImage(url: URL(string: imgUrl))
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            // Options Static List
            VStack(spacing: 8) {
                ForEach(question.options) { opt in
                    let isChosen = response?.chosenId == opt.id
                    let isCorrect = opt.correct == true || question.correctIds.contains(opt.id)

                    HStack(spacing: 12) {
                        Text(opt.label)
                            .font(MedxFont.rounded(13, weight: .bold))
                            .foregroundColor(isCorrect || isChosen ? .white : .primary)
                            .frame(width: 28, height: 28)
                            .background(isCorrect ? MedxTheme.successGreen : (isChosen ? MedxTheme.destructiveRed : Color.primary.opacity(0.08)))
                            .clipShape(Circle())

                        HTMLRichTextView(html: opt.text, font: MedxFont.rounded(14, weight: .regular))

                        Spacer()

                        if isCorrect {
                            Image(systemName: "checkmark")
                                .font(.headline)
                                .foregroundColor(MedxTheme.successGreen)
                        } else if isChosen {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .foregroundColor(MedxTheme.destructiveRed)
                        }
                    }
                    .padding(12)
                    .background(isCorrect ? MedxTheme.successGreen.opacity(0.1) : (isChosen ? MedxTheme.destructiveRed.opacity(0.1) : Color.primary.opacity(0.02)))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            // Explanation
            if let expl = question.explanation, !expl.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation(.spring()) {
                            isExplanationExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Text("Explanation")
                                .font(MedxFont.rounded(14, weight: .bold))
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: isExplanationExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if isExplanationExpanded {
                        HTMLRichTextView(html: expl, font: MedxFont.rounded(14, weight: .regular), textColor: .secondary)
                            .padding(.top, 2)
                    }
                }
                .padding(14)
                .background(Color.primary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(18)
        .liquidGlassCard(cornerRadius: 20)
    }
}
