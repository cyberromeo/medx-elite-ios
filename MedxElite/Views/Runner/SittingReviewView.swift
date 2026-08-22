import SwiftUI

public struct SittingReviewView: View {
    public let sourceId: String
    public let name: String
    public let subject: String
    public let questions: [Question]
    public let responses: [Int: QuestionResponse]
    public let gradable: Bool
    public let elapsedSeconds: Int
    public var onDone: () -> Void

    @State private var filter: ReviewFilter = .all

    public enum ReviewFilter {
        case all, wrong, skipped
    }

    public init(
        sourceId: String,
        name: String,
        subject: String,
        questions: [Question],
        responses: [Int: QuestionResponse],
        gradable: Bool = true,
        elapsedSeconds: Int = 0,
        onDone: @escaping () -> Void
    ) {
        self.sourceId = sourceId
        self.name = name
        self.subject = subject
        self.questions = questions
        self.responses = responses
        self.gradable = gradable
        self.elapsedSeconds = elapsedSeconds
        self.onDone = onDone
    }

    private var totalCount: Int { questions.count }
    private var scoreCount: Int { responses.values.filter { $0.correct }.count }
    private var attemptedCount: Int { responses.values.filter { $0.chosenId != nil }.count }
    private var wrongCount: Int { responses.values.filter { $0.chosenId != nil && !$0.correct }.count }
    private var skippedCount: Int { totalCount - attemptedCount }

    private var formattedElapsed: String {
        let seconds = max(elapsedSeconds, 0)
        if seconds >= 3600 {
            return String(format: "%dh %02dm", seconds / 3600, (seconds % 3600) / 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

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
                        heroCard
                            .padding(.horizontal, 20)
                            .padding(.top, 10)

                        Picker("Filter", selection: $filter) {
                            Text("All (\(totalCount))").tag(ReviewFilter.all)
                            Text("Wrong (\(wrongCount))").tag(ReviewFilter.wrong)
                            Text("Skipped (\(skippedCount))").tag(ReviewFilter.skipped)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)

                        if filteredQuestions.isEmpty, filter != .all {
                            emptyFilterState
                                .padding(.horizontal, 20)
                                .padding(.top, 24)
                        }

                        LazyVStack(spacing: 16) {
                            ForEach(Array(filteredQuestions.enumerated()), id: \.element.id) { _, q in
                                let originalIndex = (questions.firstIndex(where: { $0.id == q.id }) ?? 0) + 1

                                QuestionReviewCard(
                                    questionNumber: originalIndex,
                                    question: q,
                                    response: responses[q.id],
                                    sourceId: sourceId,
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

    // MARK: - Hero

    private var heroCard: some View {
        VStack(spacing: 16) {
            if gradable {
                let pct = totalCount > 0 ? Int(round(Double(scoreCount) / Double(totalCount) * 100.0)) : 0

                HStack(spacing: 20) {
                    ProgressRingView(
                        progress: Double(scoreCount) / Double(max(totalCount, 1)),
                        strokeWidth: 10,
                        size: 96,
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
                                    .foregroundStyle(.secondary)
                            }
                        )
                    )

                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(scoreCount) / \(totalCount)")
                            .font(MedxFont.mono(26, weight: .bold))
                        Text(subject.isEmpty ? "Sitting complete" : subject)
                            .font(MedxFont.caption(12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        if skippedCount > 0 {
                            Text("\(skippedCount) unattempted")
                                .font(MedxFont.caption(12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Practice Complete")
                        .font(MedxFont.title(22))
                    Text("This paper has no official answer key and is not graded. You completed \(attemptedCount) of \(totalCount) questions.")
                        .font(MedxFont.body(14))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            MedxMetricsRow {
                if gradable {
                    MedxMetric(icon: "checkmark.circle.fill", value: "\(scoreCount)", label: "correct", color: MedxTheme.successGreen)
                    MedxMetric(icon: "xmark.circle.fill", value: "\(wrongCount)", label: "wrong", color: MedxTheme.destructiveRed)
                } else {
                    MedxMetric(icon: "checkmark.circle.fill", value: "\(attemptedCount)", label: "attempted", color: MedxTheme.primaryPurple)
                }
                MedxMetric(icon: "clock.fill", value: formattedElapsed, label: "time taken", color: MedxTheme.primaryBlue)
            }
        }
        .padding(20)
        .liquidGlassCard(cornerRadius: 24, glowColor: MedxTheme.successGreen)
    }

    private var emptyFilterState: some View {
        VStack(spacing: 8) {
            Image(systemName: filter == .wrong ? "checkmark.seal.fill" : "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(MedxTheme.successGreen)
            Text(filter == .wrong ? "Nothing wrong here" : "Nothing skipped")
                .font(.headline)
            Text(filter == .wrong
                 ? "You didn't get any question wrong in this sitting."
                 : "You attempted every question in this sitting.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var ambientBackground: some View {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
    }
}

// MARK: - Review card

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

    private var uid: String? { authService.currentSession?.uid }

    private var isBookmarked: Bool {
        activityStore.isBookmarked(questionId: question.id, sourceId: sourceId, uid: uid)
    }

    private var outcome: RunnerOutcome { RunnerOutcome(response: response) }

    private var reference: String {
        question.reference?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            HTMLRichTextView(html: question.displayText, fontSize: 15, weight: .semibold)

            if let images = question.images, !images.isEmpty {
                ForEach(images, id: \.self) { imageUrl in
                    CachedAsyncImage(url: URL(string: imageUrl))
                        .frame(maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }

            optionList

            explanationSection
        }
        .padding(18)
        .liquidGlassCard(cornerRadius: 20)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Q\(questionNumber)")
                .font(MedxFont.mono(12, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())

            RunnerCircleButton(
                icon: isBookmarked ? "bookmark.fill" : "bookmark",
                tint: isBookmarked ? MedxTheme.warningOrange : nil,
                accessibilityLabel: isBookmarked ? "Remove bookmark" : "Bookmark question",
                accessibilityValue: isBookmarked ? "Saved" : "Not saved"
            ) {
                guard let uid else { return }
                activityStore.toggleBookmark(
                    question: question,
                    sourceId: sourceId,
                    sourceName: sourceName,
                    subject: subject,
                    uid: uid
                )
                HapticManager.selection()
            }

            Spacer(minLength: 0)

            Label(outcome.title, systemImage: outcome.icon)
                .font(MedxFont.label(12))
                .foregroundStyle(outcome.color)
                .labelStyle(.titleAndIcon)
        }
    }

    private var optionList: some View {
        VStack(spacing: 8) {
            ForEach(question.options) { option in
                let isChosen = response?.chosenId == option.id
                let isCorrect = option.correct == true || question.correctIds.contains(option.id)
                let tint: Color? = isCorrect
                    ? MedxTheme.successGreen
                    : (isChosen ? MedxTheme.destructiveRed : nil)

                HStack(alignment: .center, spacing: 12) {
                    Text(option.label)
                        .font(MedxFont.mono(13, weight: .bold))
                        .foregroundStyle(tint == nil ? Color.primary : Color.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(tint ?? Color(uiColor: .tertiarySystemFill)))

                    HTMLRichTextView(html: option.text, fontSize: 14, weight: .regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)

                    Spacer(minLength: 0)

                    if isCorrect {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(MedxTheme.successGreen)
                    } else if isChosen {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(MedxTheme.destructiveRed)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .background(
                    (tint ?? Color.primary).opacity(tint == nil ? 0.03 : 0.10),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
        }
    }

    @ViewBuilder
    private var explanationSection: some View {
        if (question.explanation?.isEmpty == false) || !reference.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isExplanationExpanded.toggle()
                    }
                } label: {
                    HStack {
                        Text("Explanation")
                            .font(MedxFont.headline(14))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: isExplanationExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExplanationExpanded {
                    if let explanation = question.explanation, !explanation.isEmpty {
                        HTMLRichTextView(html: explanation, fontSize: 14, weight: .regular, textColor: .secondary)
                            .padding(.top, 2)
                    }

                    if !reference.isEmpty {
                        Label(reference, systemImage: "book.closed")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
