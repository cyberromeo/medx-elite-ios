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
                    HStack(spacing: 8) {
                        filterChip(.all, label: "All", count: totalCount, tint: MedxTheme.accent)
                        filterChip(.wrong, label: "Wrong", count: wrongCount, tint: MedxDS.wrong)
                        filterChip(.skipped, label: "Skipped", count: skippedCount, tint: .gray)
                    }
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
            // iPad: the review reads as a column, not a landscape-wide form.
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
            .medxPage()
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

    private func filterChip(_ value: ReviewFilter, label: String, count: Int, tint: Color) -> some View {
        let isOn = filter == value
        return Button {
            guard !isOn else { return }
            HapticManager.selection()
            withAnimation(.snappy(duration: 0.25)) { filter = value }
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .font(.subheadline.weight(.bold))
                Text("\(count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule(style: .continuous).fill(isOn ? Color.white.opacity(0.25) : tint.opacity(0.15)))
            }
            .foregroundStyle(isOn ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(Capsule(style: .continuous).fill(isOn ? tint : MedxDS.raised))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(label), \(count)")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Hero

    /// The whole sitting as one grid, and this is the screen the answer sheet was designed for: it is the
    /// only place in the app with real per-question outcomes to draw, and "which third of the paper went
    /// wrong" is legible from it in a way no percentage is.
    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 18) {
                    scoreRing
                        .frame(width: 112, height: 112)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(verdict)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                        Text(gradable
                             ? "\(scoreCount) of \(totalCount) correct"
                             : "\(attemptedCount) of \(totalCount) attempted")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                        Label(formattedElapsed, systemImage: "clock")
                            .font(.footnote.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                        if !subject.isEmpty {
                            Text(subject)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    if gradable {
                        statTile(value: scoreCount, label: "Correct", icon: "checkmark", tint: MedxDS.correct)
                        statTile(value: wrongCount, label: "Wrong", icon: "xmark", tint: MedxDS.wrong)
                    } else {
                        statTile(value: attemptedCount, label: "Attempted", icon: "pencil", tint: MedxTheme.accent)
                    }
                    statTile(value: skippedCount, label: "Skipped", icon: "arrow.uturn.right", tint: .gray)
                }

                MedxAnswerSheet(cells: reviewCells, scale: .sheet, label: sheetSummary)

                if !gradable {
                    Text("This paper has no official answer key, so nothing here is scored — only what you attempted is recorded.")
                        .font(MedxType.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [ringTint.opacity(0.16), MedxDS.row],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(ringTint.opacity(0.3), lineWidth: 1)
                    }
            }
            .medxPlainRow()
        }
    }

    private var scorePercent: Int {
        guard totalCount > 0 else { return 0 }
        return Int((Double(gradable ? scoreCount : attemptedCount) / Double(totalCount) * 100).rounded())
    }

    private var ringTint: Color {
        guard gradable else { return MedxTheme.accent }
        switch scorePercent {
        case 75...: return MedxDS.correct
        case 50..<75: return MedxTheme.accent
        default: return MedxDS.warn
        }
    }

    private var verdict: String {
        guard gradable else { return "Sitting saved" }
        switch scorePercent {
        case 85...: return "Outstanding"
        case 70..<85: return "Great work"
        case 50..<70: return "Solid effort"
        default: return "Keep going"
        }
    }

    @State private var ringProgress: Double = 0

    private var scoreRing: some View {
        let target = totalCount > 0 ? Double(gradable ? scoreCount : attemptedCount) / Double(totalCount) : 0
        return ZStack {
            Circle()
                .stroke(ringTint.opacity(0.18), lineWidth: 11)
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(
                    AngularGradient(
                        colors: [ringTint.opacity(0.65), ringTint, ringTint],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(scorePercent)%")
                    .font(MedxType.figure(28, weight: .bold))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(gradable ? "score" : "done")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.15)) {
                ringProgress = target
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Score \(scorePercent) percent")
    }

    private func statTile(value: Int, label: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(tint))
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)")
                    .font(MedxType.figure(17, weight: .bold))
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tint.opacity(0.12)))
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
