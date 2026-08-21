import SwiftUI

public struct SittingReviewView: View {
    public let name: String
    public let subject: String
    public let questions: [Question]
    public let responses: [Int: QuestionResponse]
    public let gradable: Bool
    public var onDone: () -> Void

    @State private var filter: ReviewFilter = .all

    public enum ReviewFilter {
        case all, wrong, skipped
    }

    public init(
        name: String,
        subject: String,
        questions: [Question],
        responses: [Int: QuestionResponse],
        gradable: Bool = true,
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
    private var wrongCount: Int { responses.values.filter { $0.chosenId != nil && !$0.correct }.count }
    private var skippedCount: Int { totalCount - attemptedCount }

    private var filteredQuestions: [Question] {
        switch filter {
        case .all:
            return questions
        case .wrong:
            return questions.filter { q in
                if let r = responses[q.id], r.chosenId != nil, !r.correct { return true }
                return false
            }
        case .skipped:
            return questions.filter { q in
                if let r = responses[q.id], r.chosenId == nil { return true }
                return responses[q.id] == nil
            }
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                ambientBackground

                ScrollView {
                    VStack(spacing: 20) {
                        // Score Summary Hero Card (Liquid Glass)
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
                                                    .font(MedxFont.mono(22, weight: .heavy))
                                                Text("score")
                                                    .font(MedxFont.label(10))
                                                    .foregroundColor(.secondary)
                                            }
                                        )
                                    )

                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("\(scoreCount) / \(totalCount)")
                                            .font(MedxFont.mono(26, weight: .bold))

                                        HStack(spacing: 12) {
                                            Label("\(scoreCount) correct", systemImage: "checkmark.circle.fill")
                                                .font(MedxFont.label(12))
                                                .foregroundColor(MedxTheme.successGreen)

                                            Label("\(wrongCount) wrong", systemImage: "xmark.circle.fill")
                                                .font(MedxFont.label(12))
                                                .foregroundColor(MedxTheme.destructiveRed)
                                        }

                                        if skippedCount > 0 {
                                            Text("\(skippedCount) unattempted")
                                                .font(MedxFont.caption(12))
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Practice Complete")
                                        .font(MedxFont.title(22))
                                    Text("This paper has no official answer key and is not graded. You completed \(attemptedCount) of \(totalCount) questions.")
                                        .font(MedxFont.body(14))
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
                                    response: r,
                                    sourceId: name,
                                    sourceName: name,
                                    subject: subject
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
                    .font(.body.weight(.semibold))
                }
            }
        }
    }

    private var ambientBackground: some View {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
    }
}

private struct QuestionReviewCard: View {
    let questionNumber: Int
    let question: Question
    let response: QuestionResponse?
    let sourceId: String
    let sourceName: String
    let subject: String
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var authService = AuthService.shared
    @State private var isExplanationExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header status
            HStack(spacing: 10) {
                Text("Question \(questionNumber)")
                    .font(MedxFont.headline(15))

                Button {
                    guard let uid = authService.currentSession?.uid else { return }
                    activityStore.toggleBookmark(
                        question: question,
                        sourceId: sourceId,
                        sourceName: sourceName,
                        subject: subject,
                        uid: uid
                    )
                    HapticManager.selection()
                } label: {
                    Image(systemName: activityStore.isBookmarked(questionId: question.id, sourceId: sourceId, uid: authService.currentSession?.uid) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(activityStore.isBookmarked(questionId: question.id, sourceId: sourceId, uid: authService.currentSession?.uid) ? MedxTheme.primaryPurple : .secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(activityStore.isBookmarked(questionId: question.id, sourceId: sourceId, uid: authService.currentSession?.uid) ? "Remove bookmark" : "Bookmark question")

                Spacer()

                if let r = response, r.chosenId != nil {
                    if r.correct {
                        Label("Correct", systemImage: "checkmark.circle.fill")
                            .font(MedxFont.label(12))
                            .foregroundColor(MedxTheme.successGreen)
                    } else {
                        Label("Incorrect", systemImage: "xmark.circle.fill")
                            .font(MedxFont.label(12))
                            .foregroundColor(MedxTheme.destructiveRed)
                    }
                } else {
                    Label("Unattempted", systemImage: "minus.circle.fill")
                        .font(MedxFont.label(12))
                        .foregroundColor(MedxTheme.warningOrange)
                }
            }

            // Question text
            HTMLRichTextView(html: question.displayText, fontSize: 15, weight: .semibold)

            // Images if any
            if let imgs = question.images, !imgs.isEmpty {
                ForEach(imgs, id: \.self) { imgUrl in
                    CachedAsyncImage(url: URL(string: imgUrl))
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            // Options Static List
            VStack(spacing: 8) {
                ForEach(question.options) { opt in
                    let isChosen = response?.chosenId == opt.id
                    let isCorrect = opt.correct == true || question.correctIds.contains(opt.id)

                    HStack(alignment: .center, spacing: 12) {
                        Text(opt.label)
                            .font(MedxFont.mono(13, weight: .bold))
                            .foregroundColor(isCorrect || isChosen ? .white : .primary)
                            .frame(width: 28, height: 28)
                            .background(isCorrect ? MedxTheme.successGreen : (isChosen ? MedxTheme.destructiveRed : Color.primary.opacity(0.08)))
                            .clipShape(Circle())

                        HTMLRichTextView(html: opt.text, fontSize: 14, weight: .regular)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)
                        Spacer(minLength: 0)

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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
                    .background(isCorrect ? MedxTheme.successGreen.opacity(0.1) : (isChosen ? MedxTheme.destructiveRed.opacity(0.1) : Color.primary.opacity(0.02)))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                                .font(MedxFont.headline(14))
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: isExplanationExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if isExplanationExpanded {
                        HTMLRichTextView(html: expl, fontSize: 14, weight: .regular, textColor: .secondary)
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
