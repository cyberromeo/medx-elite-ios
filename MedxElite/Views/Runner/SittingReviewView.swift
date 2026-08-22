import SwiftUI

/// Post-sitting review. A score header, a filter, then one flat card per question with its
/// key and explanation.
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

    public enum ReviewFilter: String, CaseIterable, Identifiable {
        case all, wrong, skipped
        public var id: String { rawValue }
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
            return questions.filter { question in
                guard let response = responses[question.id] else { return false }
                return response.chosenId != nil && !response.correct
            }
        case .skipped:
            return questions.filter { responses[$0.id]?.chosenId == nil }
        }
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    heroCard

                    Picker("Filter", selection: $filter) {
                        Text("All (\(totalCount))").tag(ReviewFilter.all)
                        Text("Wrong (\(wrongCount))").tag(ReviewFilter.wrong)
                        Text("Skipped (\(skippedCount))").tag(ReviewFilter.skipped)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: filter) { _, _ in HapticManager.selection() }

                    if filteredQuestions.isEmpty, filter != .all {
                        emptyFilterState
                            .padding(.top, 24)
                    }

                    ForEach(Array(filteredQuestions.enumerated()), id: \.element.id) { _, question in
                        QuestionReviewCard(
                            questionNumber: (questions.firstIndex { $0.id == question.id } ?? 0) + 1,
                            question: question,
                            response: responses[question.id],
                            sourceId: sourceId,
                            sourceName: name,
                            subject: subject
                        )
                    }
                }
                .padding(.horizontal, MedxSurface.gutter)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .background(MedxSurface.groupedBackground.ignoresSafeArea())
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
                let percent = totalCount > 0
                    ? Int((Double(scoreCount) / Double(totalCount) * 100).rounded())
                    : 0

                HStack(spacing: 20) {
                    ProgressRingView(
                        progress: Double(scoreCount) / Double(max(totalCount, 1)),
                        strokeWidth: 9,
                        size: 92,
                        tint: MedxTheme.successGreen,
                        centerContent: AnyView(
                            VStack(spacing: 0) {
                                Text("\(percent)%")
                                    .font(.title3.weight(.bold).monospacedDigit())
                                Text("score")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        )
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(scoreCount) / \(totalCount)")
                            .font(.title2.weight(.bold).monospacedDigit())
                        Text(subject.isEmpty ? "Sitting complete" : subject)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        if skippedCount > 0 {
                            Text("\(skippedCount) unattempted")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Practice complete")
                        .font(.title3.weight(.semibold))
                    Text("This paper has no official answer key, so it isn't graded. You answered \(attemptedCount) of \(totalCount) questions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
        .padding(18)
        .medxCard(cornerRadius: 20)
    }

    private var emptyFilterState: some View {
        ContentUnavailableView {
            Label(
                filter == .wrong ? "Nothing wrong here" : "Nothing skipped",
                systemImage: filter == .wrong ? "checkmark.seal.fill" : "checkmark.circle.fill"
            )
        } description: {
            Text(filter == .wrong
                 ? "You didn't get any question wrong in this sitting."
                 : "You attempted every question in this sitting.")
        }
        .frame(maxWidth: .infinity)
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

            HTMLRichTextView(html: question.displayText, fontSize: 16, weight: .semibold)

            if let images = question.images, !images.isEmpty {
                ForEach(images, id: \.self) { raw in
                    RunnerFigure(raw: raw)
                }
            }

            optionList

            explanationSection
        }
        .padding(16)
        .medxCard()
        .contextMenu {
            Button {
                toggleBookmark()
            } label: {
                Label(
                    isBookmarked ? "Remove bookmark" : "Bookmark question",
                    systemImage: isBookmarked ? "bookmark.slash" : "bookmark"
                )
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Q\(questionNumber)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(MedxSurface.fieldFill, in: Capsule())

            Label(outcome.title, systemImage: outcome.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(outcome.color)

            Spacer(minLength: 0)

            MedxCircleButton(
                icon: isBookmarked ? "bookmark.fill" : "bookmark",
                tint: isBookmarked ? MedxTheme.warningOrange : nil,
                accessibilityLabel: isBookmarked ? "Remove bookmark" : "Bookmark question",
                accessibilityValue: isBookmarked ? "Saved" : "Not saved"
            ) {
                toggleBookmark()
            }
        }
    }

    private func toggleBookmark() {
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

    private var optionList: some View {
        VStack(spacing: 8) {
            ForEach(question.options) { option in
                let isChosen = response?.chosenId == option.id
                let isCorrect = option.correct == true || question.correctIds.contains(option.id)
                let tint: Color? = isCorrect
                    ? MedxTheme.successGreen
                    : (isChosen ? MedxTheme.destructiveRed : nil)

                HStack(alignment: .top, spacing: 12) {
                    Text(option.label)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(tint == nil ? Color.primary : Color.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(tint ?? MedxSurface.fieldFill))

                    HTMLRichTextView(
                        html: option.text,
                        fontSize: 15,
                        weight: .regular,
                        maxImageHeight: 180,
                        interactive: false
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                    if isCorrect {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(MedxTheme.successGreen)
                    } else if isChosen {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(MedxTheme.destructiveRed)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .medxTile(cornerRadius: 12, accentColor: tint, isSelected: tint != nil)
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
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: isExplanationExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExplanationExpanded {
                    if let explanation = question.explanation, !explanation.isEmpty {
                        HTMLRichTextView(html: explanation, fontSize: 15, weight: .regular, textColor: .secondary)
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
            .background(MedxSurface.tileFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}
