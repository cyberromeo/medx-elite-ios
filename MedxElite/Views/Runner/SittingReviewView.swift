import SwiftUI

/// Post-sitting review: the score, the blocks if there were any, a filter, then one grouped
/// section per question with its key and explanation. The option rows are the runner's own, in
/// their revealed state, so the review and the sitting cannot draw an answer two ways.
public struct SittingReviewView: View {
    public let sourceId: String
    public let name: String
    public let subject: String
    public let questions: [Question]
    public let responses: [Int: QuestionResponse]
    public let gradable: Bool
    public let elapsedSeconds: Int
    /// Per-block scores for a sectioned paper. Empty for everything else.
    public let sections: [MedxAttemptSection]
    /// Kept for the call sites; the review wears the one accent like every other screen.
    public let section: MedxSection
    /// Where each question came from, for a mixed paper (keyed by question id).
    public let questionTags: [Int: String]
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
        sections: [MedxAttemptSection] = [],
        section: MedxSection = .qbank,
        questionTags: [Int: String] = [:],
        onDone: @escaping () -> Void
    ) {
        self.sourceId = sourceId
        self.name = name
        self.subject = subject
        self.questions = questions
        self.responses = responses
        self.gradable = gradable
        self.elapsedSeconds = elapsedSeconds
        self.sections = sections.sorted { $0.index < $1.index }
        self.section = section
        self.questionTags = questionTags
        self.onDone = onDone
    }

    private var totalCount: Int { questions.count }
    private var scoreCount: Int { responses.values.filter { $0.correct }.count }
    private var attemptedCount: Int { responses.values.filter { $0.chosenId != nil }.count }
    private var wrongCount: Int { responses.values.filter { $0.chosenId != nil && !$0.correct }.count }
    private var skippedCount: Int { totalCount - attemptedCount }
    private var percent: Int { MedxFormat.percent(scoreCount, of: totalCount) }

    /// A practice paper without a key is never scored, and never painted red.
    private var verdict: String {
        guard gradable else { return "Not scored" }
        switch percent {
        case 85...: return "Excellent"
        case 70..<85: return "Solid effort"
        case 50..<70: return "Getting there"
        default: return "Keep going"
        }
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
            List {
                heroSection

                if !sections.isEmpty {
                    blocksSection
                }

                Section {
                    Picker("Show", selection: $filter) {
                        Text("All (\(totalCount))").tag(ReviewFilter.all)
                        if gradable {
                            Text("Wrong (\(wrongCount))").tag(ReviewFilter.wrong)
                        }
                        Text("Skipped (\(skippedCount))").tag(ReviewFilter.skipped)
                    }
                    .pickerStyle(.segmented)
                }

                if filteredQuestions.isEmpty, filter != .all {
                    Section {
                        MedxEmptyState(
                            filter == .wrong ? "Nothing wrong" : "Nothing skipped",
                            symbol: "checkmark.seal",
                            message: filter == .wrong ? "Every answered question was right." : "Every question was answered."
                        )
                    }
                }

                ForEach(Array(filteredQuestions.enumerated()), id: \.element.id) { _, question in
                    Section {
                        QuestionReviewCard(
                            questionNumber: (questions.firstIndex { $0.id == question.id } ?? 0) + 1,
                            question: question,
                            response: responses[question.id],
                            gradable: gradable,
                            sourceId: sourceId,
                            sourceName: name,
                            subject: subject,
                            sourceTag: questionTags[question.id]
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        HapticManager.medium()
                        onDone()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: MedxSpace.l) {
                HStack(spacing: MedxSpace.l) {
                    MedxRing(
                        fraction: Double(gradable ? scoreCount : attemptedCount) / Double(max(totalCount, 1)),
                        tint: gradable ? MedxTheme.accent : MedxOutcome.pending
                    ) {
                        VStack(spacing: 0) {
                            MedxFigure(gradable ? "\(percent)%" : "\(attemptedCount)")
                            Text(gradable ? "score" : "attempted")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 96, height: 96)

                    VStack(alignment: .leading, spacing: MedxSpace.xs) {
                        Text(verdict)
                            .font(.title3.weight(.bold))
                        Text(gradable ? "\(scoreCount) of \(totalCount) correct" : "\(attemptedCount) of \(totalCount) attempted")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Label(MedxFormat.duration(elapsedSeconds), systemImage: "clock")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if !subject.isEmpty, subject != name {
                            Text(subject)
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer(minLength: 0)
                }

                MedxStatRow {
                    if gradable {
                        MedxStatTile("\(scoreCount)", label: "correct", symbol: "checkmark.circle.fill", hue: MedxOutcome.correct)
                        MedxStatTile("\(wrongCount)", label: "wrong", symbol: "xmark.circle.fill", hue: MedxOutcome.wrong)
                    } else {
                        MedxStatTile("\(attemptedCount)", label: "attempted", symbol: "circle.fill", hue: MedxTheme.accent)
                    }
                    MedxStatTile("\(skippedCount)", label: "skipped", symbol: "arrow.right.circle.fill", hue: MedxOutcome.pending)
                }
            }
            .padding(.vertical, MedxSpace.xs)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(verdict)
            .accessibilityValue(gradable ? "\(scoreCount) of \(totalCount) correct" : "\(attemptedCount) of \(totalCount) attempted")
        }
    }

    // MARK: - Blocks

    /// Block by block, in the order they were sat: on a 150-question grand paper the interesting
    /// thing is almost always *which* of the three blocks went wrong.
    private var blocksSection: some View {
        Section {
            ForEach(sections) { block in
                LabeledContent {
                    Text(gradable ? "\(block.score) of \(block.total)" : "\(block.attempted) of \(block.total)")
                        .monospacedDigit()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(block.label)
                        Text("\(block.attempted) attempted · \(MedxFormat.clock(block.seconds))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Blocks")
        } footer: {
            Text("Each one was timed on its own and submitted for good.")
        }
    }
}

// MARK: - Review card

private struct QuestionReviewCard: View {
    let questionNumber: Int
    let question: Question
    let response: QuestionResponse?
    let gradable: Bool
    let sourceId: String
    let sourceName: String
    let subject: String
    var sourceTag: String? = nil

    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var authService = AuthService.shared

    private var uid: String? { authService.currentSession?.uid }

    private var isBookmarked: Bool {
        activityStore.isBookmarked(questionId: question.id, sourceId: sourceId, uid: uid)
    }

    /// An ungraded paper has no outcome to report, only whether the question was attempted.
    private var outcome: RunnerOutcome {
        guard gradable else {
            return response?.chosenId == nil ? .unanswered : .correct
        }
        return RunnerOutcome(response: response)
    }

    private var outcomeTitle: String {
        guard gradable else { return response?.chosenId == nil ? "Not answered" : "Attempted" }
        return outcome.title
    }

    private var reference: String {
        question.reference?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MedxSpace.m) {
            header

            HTMLRichTextView(html: question.displayText, fontSize: 16, weight: .semibold)

            if let images = question.images, !images.isEmpty {
                ForEach(images, id: \.self) { raw in
                    RunnerFigure(raw: raw)
                }
            }

            VStack(spacing: MedxSpace.s) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { pair in
                    QuestionOptionButton(
                        option: pair.element,
                        index: pair.offset,
                        isChosen: response?.chosenId == pair.element.id,
                        isCorrect: gradable && question.isCorrect(optionId: pair.element.id),
                        isRevealed: gradable,
                        isLocked: true
                    ) {}
                }
            }

            explanationSection
        }
        .padding(.vertical, MedxSpace.xs)
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
        HStack(spacing: MedxSpace.s) {
            Text("Q\(questionNumber)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())

            Label(outcomeTitle, systemImage: gradable ? outcome.icon : "circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(gradable ? outcome.color : Color.secondary)

            if let sourceTag, !sourceTag.isEmpty {
                MedxSourceTag(sourceTag)
            }

            Spacer(minLength: 0)

            Button {
                toggleBookmark()
            } label: {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(isBookmarked ? MedxOutcome.flagged : Color.secondary)
                    .symbolEffect(.bounce, value: isBookmarked)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark question")
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

    @ViewBuilder
    private var explanationSection: some View {
        if (question.explanation?.isEmpty == false) || !reference.isEmpty {
            VStack(alignment: .leading, spacing: MedxSpace.s) {
                Label("Explanation", systemImage: "lightbulb.fill")
                    .font(.subheadline.weight(.semibold))

                if let explanation = question.explanation, !explanation.isEmpty {
                    HTMLRichTextView(html: explanation, fontSize: 15, weight: .regular, textColor: .secondary)
                }

                if !reference.isEmpty {
                    Label(reference, systemImage: "book.closed")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, MedxSpace.xs)
        }
    }
}
