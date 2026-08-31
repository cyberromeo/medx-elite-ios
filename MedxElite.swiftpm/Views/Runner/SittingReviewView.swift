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
    /// Per-block scores for a sectioned paper. Empty for everything else, which is what keeps
    /// the breakdown off every ordinary sitting's review.
    public let sections: [MedxAttemptSection]
    /// The palette the paper was opened wearing — see `RunnerPayload.section`.
    public let section: MedxSection
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
        self.onDone = onDone
    }

    private var totalCount: Int { questions.count }
    private var scoreCount: Int { responses.values.filter { $0.correct }.count }
    private var attemptedCount: Int { responses.values.filter { $0.chosenId != nil }.count }
    private var wrongCount: Int { responses.values.filter { $0.chosenId != nil && !$0.correct }.count }
    private var skippedCount: Int { totalCount - attemptedCount }

    // MARK: - Section breakdown

    /// Block by block, in the order they were sat. Worth its own section rather than folding into the
    /// hero: on a 150-question grand paper the interesting thing is almost always *which* of the three
    /// blocks went wrong, and that is invisible in a single total.
    private var sectionBreakdown: some View {
        Section {
            ForEach(sections) { block in
                MedxRow(
                    lead: gradable ? "\(block.score)" : "\(block.attempted)",
                    title: block.label,
                    detail: blockLine(block)
                ) {
                    MedxAnswerSheet(
                        fraction: Double(gradable ? block.score : block.attempted) / Double(max(block.total, 1)),
                        label: gradable
                            ? "\(block.score) of \(block.total) correct"
                            : "\(block.attempted) of \(block.total) attempted"
                    )
                }
                .medxListRow()
            }
        } header: {
            MedxHeader("Blocks", count: sections.count)
        } footer: {
            Text("Each one was timed on its own and submitted for good.")
        }
    }

    private func blockLine(_ block: MedxAttemptSection) -> String {
        let minutes = block.seconds / 60
        let seconds = block.seconds % 60
        let clock = String(format: "%d:%02d", minutes, seconds)
        return "\(block.attempted) of \(block.total) attempted · \(clock)"
    }

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
            List {
                heroSection

                if !sections.isEmpty {
                    sectionBreakdown
                }

                Section {
                    Picker("Filter", selection: $filter) {
                        Text("All \(totalCount)").tag(ReviewFilter.all)
                        Text("Wrong \(wrongCount)").tag(ReviewFilter.wrong)
                        Text("Skipped \(skippedCount)").tag(ReviewFilter.skipped)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .medxPlainRow()

                    if filteredQuestions.isEmpty, filter != .all {
                        emptyFilterState
                            .medxPlainRow()
                    }
                }

                ForEach(Array(filteredQuestions.enumerated()), id: \.element.id) { _, question in
                    Section {
                        QuestionReviewCard(
                            questionNumber: (questions.firstIndex { $0.id == question.id } ?? 0) + 1,
                            question: question,
                            response: responses[question.id],
                            sourceId: sourceId,
                            sourceName: name,
                            subject: subject
                        )
                        .medxListRow()
                    }
                }
            }
            .medxList()
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        HapticManager.medium()
                        onDone()
                    }
                    .font(MedxType.title)
                }
            }
        }
    }

    // MARK: - Hero

    /// The whole sitting as one grid, and this is the screen the answer sheet was designed for: it is the
    /// only place in the app with real per-question outcomes to draw, and "which third of the paper went
    /// wrong" is legible from it in a way no percentage is.
    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(gradable ? "\(scoreCount)" : "\(attemptedCount)")
                        .font(MedxType.hero)
                        .contentTransition(.numericText())
                    Text("/ \(totalCount)")
                        .font(MedxType.display)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }

                Text(heroCaption)
                    .medxTag()

                MedxAnswerSheet(cells: reviewCells, scale: .sheet, label: sheetSummary)

                HStack(alignment: .top, spacing: 10) {
                    if gradable {
                        MedxStat("\(scoreCount)", label: "correct", tint: MedxDS.correct)
                        MedxStat("\(wrongCount)", label: "wrong", tint: wrongCount > 0 ? MedxDS.wrong : nil)
                    } else {
                        MedxStat("\(attemptedCount)", label: "attempted")
                    }
                    if skippedCount > 0 {
                        MedxStat("\(skippedCount)", label: "skipped")
                    }
                    MedxStat(formattedElapsed, label: "time taken")
                }

                if !gradable {
                    Text("This paper has no official answer key, so nothing here is scored — only what you attempted is recorded.")
                        .font(MedxType.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .medxPlainRow()
        }
    }

    /// One cell per question, in paper order, from the real response.
    private var reviewCells: [MedxSheetCell] {
        questions.map { question in
            guard let response = responses[question.id] else { return .pending }
            if response.timedOut == true { return .missed }
            guard response.chosenId != nil else { return .pending }
            guard gradable else { return .answered }
            return response.correct ? .correct : .wrong
        }
    }

    private var heroCaption: String {
        let percent = totalCount > 0
            ? Int((Double(gradable ? scoreCount : attemptedCount) / Double(totalCount) * 100).rounded())
            : 0
        let lead = subject.isEmpty ? "sitting complete" : subject
        return gradable ? "\(percent)% · \(lead)" : lead
    }

    private var sheetSummary: String {
        gradable
            ? "\(scoreCount) correct, \(wrongCount) wrong, \(skippedCount) not attempted"
            : "\(attemptedCount) of \(totalCount) attempted"
    }

    private var emptyFilterState: some View {
        ContentUnavailableView {
            Label(
                filter == .wrong ? "Nothing wrong here" : "Nothing skipped",
                systemImage: filter == .wrong ? "checkmark.circle" : "target"
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
        .padding(.vertical, 4)
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
                .background(Capsule(style: .continuous).fill(MedxDS.sunken))

            Label(outcome.title, systemImage: outcome.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(outcome.color)

            Spacer(minLength: 0)

            Button {
                toggleBookmark()
            } label: {
                Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(isBookmarked ? MedxDS.warn : Color.secondary)
                    .symbolEffect(.bounce, value: isBookmarked)
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(MedxPressStyle())
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

    private var optionList: some View {
        VStack(spacing: 8) {
            ForEach(Array(question.options.enumerated()), id: \.offset) { pair in
                let option = pair.element
                let isChosen = response?.chosenId == option.id
                let isCorrect = option.correct == true || question.correctIds.contains(option.id)
                let tint: Color? = isCorrect
                    ? MedxDS.correct
                    : (isChosen ? MedxDS.wrong : nil)

                HStack(alignment: .top, spacing: 12) {
                    Text(MedxOptionLetter.of(option, at: pair.offset))
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(tint == nil ? Color.primary : Color.white)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(tint ?? MedxDS.sunken))

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
                            .foregroundStyle(MedxDS.correct)
                    } else if isChosen {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(MedxDS.wrong)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .medxOptionSurface(state: tint, emphasized: tint != nil)
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
                            .font(MedxType.title)
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
                            .font(MedxType.body)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
            .background(MedxDS.shape(MedxDS.control).fill(MedxDS.sunken))
        }
    }
}
