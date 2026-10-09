import SwiftUI
import UIKit

// MARK: - Sitting runner

/// The question runner, rebuilt on native chrome.
///
/// It used to stack Liquid Glass on the header, the footer, the question card, every
/// answer option and the explanation — five translucent layers over a blurred background,
/// which is both illegible and expensive. Now the only material in the view is the
/// navigation bar and the bottom action bar, exactly like Mail or Notes; content sits on
/// flat grouped surfaces.
public struct QuizRunnerView: View {
    public let payload: RunnerPayload
    public var onFinishedSession: () -> Void

    @State private var questions: [Question] = []
    @State private var currentIndex = 0
    @State private var furthestIndex = 0
    @State private var responses: [Int: QuestionResponse] = [:]
    @State private var revealedQuestions: [Int: Bool] = [:]
    @State private var statuses: [RunnerQuestionStatus] = []
    @State private var remainingSeconds = 0
    @State private var completedSeconds = 0
    /// One-shot guards so the halfway and final-fifth haptics each fire once per armed clock.
    @State private var firedHaptic50 = false
    @State private var firedHaptic20 = false
    @State private var loadState: RunnerLoadState = .loading
    /// A load in flight, so two overlapping `.task` runs cannot both reset the sitting.
    @State private var isLoadingSitting = false
    @State private var isFinished = false
    @State private var showExitAlert = false
    @State private var showNavigator = false
    @State private var showSubmitConfirm = false
    /// A saved, unfinished sitting of this same paper, offered back when it is opened again.
    @State private var resumeOffer: MedxSittingSnapshot?
    @State private var ticksSinceSave = 0
    @Environment(\.scenePhase) private var scenePhase
    @State private var startedAt = Date()
    /// The blocks this paper is sat in. Always at least one element once loaded — an
    /// unsectioned paper is a single block over the whole thing, which is what lets every
    /// navigation guard, the clock and the navigator read `activeSection` without first
    /// asking whether sections exist.
    @State private var sections: [MedxRunnerSection] = []
    @State private var sectionIndex = 0
    /// Blocks already submitted, scored at the moment their own clock was still meaningful.
    @State private var sectionLog: [MedxAttemptSection] = []
    @State private var sectionStartedAt = Date()
    /// Raised between blocks, so a submitted section is acknowledged rather than the paper
    /// silently jumping thirty questions forward.
    @State private var handover: MedxSectionHandover?
    /// What the Lock Screen was last told, so a navigation tap does not push an identical
    /// Live Activity update.
    @State private var lastPushedAnswered = -1
    @State private var lastPushedNumber = -1

    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var authService = AuthService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let topAnchor = "runner.top"

    public init(payload: RunnerPayload, onFinishedSession: @escaping () -> Void) {
        self.payload = payload
        self.onFinishedSession = onFinishedSession
    }

    public var body: some View {
        Group {
            if isFinished {
                SittingReviewView(
                    sourceId: payload.id,
                    name: payload.name,
                    subject: payload.subject,
                    questions: questions,
                    responses: responses,
                    gradable: payload.gradable,
                    elapsedSeconds: completedSeconds,
                    sections: sectionLog,
                    section: payload.section,
                    questionTags: reviewTags
                ) {
                    onFinishedSession()
                    dismiss()
                }
            } else {
                NavigationStack {
                    runnerScreen
                }
            }
        }
        .onReceive(timer) { _ in
            tick()
        }
        .task {
            await loadSittingQuestions()
        }
        .onDisappear {
            // Belt and braces: `finishSitting` already ends it, but leaving by any other
            // route must not strand a timer on the Lock Screen.
            MedxLiveActivityController.shared.endExam(state: examActivityState)
        }
    }

    private var runnerScreen: some View {
        content
            // The page's own wash, turned down: a question stem is the densest text in the app
            // and wants the calmest thing behind it that still gives the glass something to bend.
            .medxPage()
            .navigationTitle(payload.name)
            .navigationBarTitleDisplayMode(.inline)
            // `RunnerHUD` *is* the chrome now. Two bands of furniture across the top of a phone
            // — a navigation bar and then a floating panel — is one too many, and the HUD
            // carries everything the toolbar did: close, counter, clock, bookmark.
            .toolbar(.hidden, for: .navigationBar)
            .alert("Leave sitting?", isPresented: $showExitAlert) {
                Button("Keep Going", role: .cancel) {}
                Button("Save and Leave") {
                    persistSnapshot()
                    dismiss()
                }
                Button("Discard", role: .destructive) {
                    MedxSittingSnapshot.clear(kind: payload.kind, id: payload.id)
                    dismiss()
                }
            } message: {
                Text("Save and Leave keeps your answers and the clock where they are, so opening this paper again picks up at question \(currentIndex + 1).")
            }
            .alert(
                "Pick up where you left off?",
                isPresented: Binding(get: { resumeOffer != nil }, set: { if !$0 { resumeOffer = nil } })
            ) {
                // The cancel role, so the alert offers exactly two choices and Resume is the default.
                Button("Resume", role: .cancel) {
                    if let snapshot = resumeOffer { applySnapshot(snapshot) }
                    resumeOffer = nil
                }
                Button("Start Over", role: .destructive) {
                    MedxSittingSnapshot.clear(kind: payload.kind, id: payload.id)
                    resumeOffer = nil
                }
            } message: {
                if let snapshot = resumeOffer {
                    Text(snapshot.summary(total: questions.count))
                }
            }
            .sheet(isPresented: $showSubmitConfirm) {
                RunnerSubmitSheet(
                    answered: sectionAnsweredCount,
                    unanswered: questionsInSection.count - sectionAnsweredCount,
                    flagged: questionsInSection.filter { isBookmarked($0) }.count,
                    clock: payload.mode == .exam ? RunnerSubmitSheet.clock(remainingSeconds) : nil,
                    title: isSectioned && !isFinalSection ? "Submit \(activeSection.label)?" : "Submit paper?",
                    detail: isSectioned && !isFinalSection
                        ? "A submitted block cannot be reopened. The next block's clock starts when you open it."
                        : "Your answers are scored and saved to your history.",
                    onReviewUnanswered: firstUnansweredInSection.map { index -> () -> Void in
                        return {
                            showSubmitConfirm = false
                            jump(to: index)
                        }
                    },
                    onSubmit: {
                        showSubmitConfirm = false
                        submitSection()
                    }
                )
                .presentationDetents([.height(430)])
                .presentationDragIndicator(.visible)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { persistSnapshot() }
            }
            .sheet(isPresented: $showNavigator) {
                QuestionNavigatorSheet(
                    range: navigatorRange,
                    currentIndex: currentIndex,
                    furthestIndex: furthestIndex,
                    statuses: statuses,
                    lockAhead: payload.mode == .revision,
                    sectionLabel: isSectioned ? activeSection.label : nil,
                    section: payload.section
                ) { index in
                    showNavigator = false
                    jump(to: index)
                }
            }
            .fullScreenCover(item: $handover) { summary in
                MedxSectionHandoverSheet(summary: summary) {
                    beginActiveSection()
                }
            }
    }

    /// What the navigator may offer, clamped to the questions that exist.
    private var navigatorRange: Range<Int> {
        let lower = min(activeSection.start, questions.count)
        let upper = min(activeSection.end, questions.count)
        return lower < upper ? lower..<upper : 0..<0
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            loadingState
        case .unavailable(let message):
            unavailableState(message: message)
        case .ready:
            if let question = currentQuestion {
                activeRunner(question: question)
            } else {
                unavailableState(message: "This sitting has no questions to show.")
            }
        }
    }

    // MARK: - Derived state

    /// The per-question source tags keyed by question id, for the review.
    private var reviewTags: [Int: String] {
        guard let tags = payload.questionTags else { return [:] }
        var out: [Int: String] = [:]
        for (question, tag) in zip(questions, tags) { out[question.id] = tag }
        return out
    }

    private var currentQuestion: Question? {
        questions.indices.contains(currentIndex) ? questions[currentIndex] : nil
    }

    private var uid: String? { authService.currentSession?.uid }

    private var answeredCount: Int {
        responses.values.reduce(into: 0) { total, response in
            if response.chosenId != nil { total += 1 }
        }
    }

    /// The block being sat. Falls back to the whole paper before `loadSittingQuestions` has
    /// resolved the sections, so nothing reading this has to unwrap.
    private var activeSection: MedxRunnerSection {
        guard sections.indices.contains(sectionIndex) else {
            return MedxRunnerSection(
                label: "Section 1",
                start: 0,
                count: max(questions.count, 1),
                minutes: max(questions.count, 1)
            )
        }
        return sections[sectionIndex]
    }

    /// One block over the whole paper is not a sectioned sitting — it is every other paper in
    /// the app. Only a genuine split changes the chrome, the guards and the submit button.
    private var isSectioned: Bool { sections.count > 1 }

    private var isFinalSection: Bool { sectionIndex >= sections.count - 1 }

    /// How many of *this block's* questions have an answer — what the section handover reports.
    private var questionsInSection: [Question] {
        let range = activeSection
        guard range.start < questions.count else { return [] }
        return Array(questions[range.start..<min(range.end, questions.count)])
    }

    /// In revision mode the per-question clock stops once the answer is revealed.
    private var isTimerPaused: Bool {
        guard payload.mode == .revision, let question = currentQuestion else { return false }
        return responses[question.id] != nil
    }

    /// The last question *of this block*. In a sectioned paper that is where the Next button
    /// becomes Submit — there is no way back into a submitted block, so it cannot simply run
    /// on into the next fifty questions.
    private var isLastQuestion: Bool {
        currentIndex >= activeSection.end - 1
    }

    /// Exam mode never blocks navigation; revision requires the answer to be revealed first.
    /// Answered (an option picked, not just timed out) in the block on screen.
    private var sectionAnsweredCount: Int {
        questionsInSection.reduce(0) { $0 + (responses[$1.id]?.chosenId != nil ? 1 : 0) }
    }

    /// The first question in this block with no option picked, for the submit sheet's way back.
    private var firstUnansweredInSection: Int? {
        let range = activeSection.start..<min(activeSection.end, questions.count)
        return range.first { responses[questions[$0].id]?.chosenId == nil }
    }

    // MARK: - Leave and resume

    /// Demo screenshot runs never write a sitting: one screen's answers would otherwise be
    /// offered back on the next screen's launch.
    private var persistsSittings: Bool {
        #if DEBUG
        return !MedxDemoMode.isOn
        #else
        return true
        #endif
    }

    /// Saves where the sitting is, so leaving (on purpose, or because iOS closed the app) can
    /// be picked up later. Keyed to this paper and fingerprinted by its question ids, so a
    /// paper that has since been re-uploaded with different questions never inherits answers.
    private func persistSnapshot() {
        guard persistsSittings, loadState == .ready, !isFinished, !questions.isEmpty else { return }
        guard !responses.isEmpty || currentIndex > 0 else { return }
        MedxSittingSnapshot(
            fingerprint: MedxSittingSnapshot.fingerprint(questions),
            mode: payload.mode.rawValue,
            currentIndex: currentIndex,
            furthestIndex: furthestIndex,
            responses: Array(responses.values),
            revealed: revealedQuestions.compactMap { $0.value ? $0.key : nil },
            remainingSeconds: remainingSeconds,
            sectionIndex: sectionIndex,
            sectionLog: sectionLog,
            elapsedSeconds: Int(Date().timeIntervalSince(startedAt)),
            savedAt: Date()
        )
        .save(kind: payload.kind, id: payload.id)
    }

    private func applySnapshot(_ snapshot: MedxSittingSnapshot) {
        var restored: [Int: QuestionResponse] = [:]
        let known = Set(questions.map(\.id))
        for response in snapshot.responses where known.contains(response.questionId) {
            restored[response.questionId] = response
        }
        responses = restored
        revealedQuestions = Dictionary(
            snapshot.revealed.filter { known.contains($0) }.map { ($0, true) },
            uniquingKeysWith: { first, _ in first }
        )
        sectionIndex = min(max(snapshot.sectionIndex, 0), max(sections.count - 1, 0))
        sectionLog = snapshot.sectionLog
        let range = activeSection.start..<max(activeSection.end, activeSection.start + 1)
        currentIndex = min(max(snapshot.currentIndex, range.lowerBound), range.upperBound - 1)
        furthestIndex = max(snapshot.furthestIndex, currentIndex)
        remainingSeconds = max(snapshot.remainingSeconds, 1)
        startedAt = Date().addingTimeInterval(-Double(max(snapshot.elapsedSeconds, 0)))
        let spent = payload.mode == .exam ? max(activeSection.seconds - remainingSeconds, 0) : 0
        sectionStartedAt = Date().addingTimeInterval(-Double(spent))
        armTimeHaptics()
        refreshStatuses()
        HapticManager.success()
    }

    private func canAdvance(isRevealed: Bool) -> Bool {
        payload.mode == .exam || isRevealed
    }

    private func status(for question: Question) -> RunnerQuestionStatus {
        guard let response = responses[question.id] else { return .unanswered }
        if response.timedOut == true { return .timedOut }
        guard response.chosenId != nil else { return .unanswered }
        if revealedQuestions[question.id] == true {
            return response.correct ? .correct : .wrong
        }
        return .answered
    }

    /// Recomputed on change instead of inside `body`: the progress track and the navigator
    /// both read it, and it walks every question in the sitting.
    private func refreshStatuses() {
        statuses = questions.map { status(for: $0) }
        refreshLiveActivity()
    }

    /// Exam mode mirrors the sitting onto the Lock Screen and the Dynamic Island. The clock
    /// itself is handed over as an end date so the system ticks it — only the counts, the
    /// question number and the block need pushing, and only when they actually change.
    private func refreshLiveActivity() {
        guard payload.mode == .exam, loadState == .ready, !isFinished else { return }
        let answered = answeredCount
        let number = currentIndex + 1
        guard answered != lastPushedAnswered || number != lastPushedNumber else { return }
        lastPushedAnswered = answered
        lastPushedNumber = number

        MedxLiveActivityController.shared.updateExam(state: examActivityState)
    }

    /// One place builds the activity's state, so the start, every update and the end cannot
    /// disagree about what the numbers mean.
    private var examActivityState: MedxExamActivityAttributes.ContentState {
        let scored = responses.values.filter { $0.chosenId != nil }
        return MedxExamActivityAttributes.ContentState(
            answered: answeredCount,
            correct: payload.gradable ? scored.filter(\.correct).count : 0,
            wrong: payload.gradable ? scored.filter { !$0.correct }.count : 0,
            currentNumber: currentIndex + 1,
            endDate: examEndDate,
            sectionLabel: isSectioned ? activeSection.label : nil,
            sectionIndex: sectionIndex,
            sectionCount: sections.count,
            sectionTotal: activeSection.count,
            revealsAnswers: payload.mode == .revision
        )
    }

    /// The end of the *block's* clock, not the paper's. A stranded activity from a submitted
    /// section then goes stale on its own rather than counting down something that has ended.
    private var examEndDate: Date {
        Date().addingTimeInterval(TimeInterval(max(remainingSeconds, 0)))
    }

    private func isBookmarked(_ question: Question) -> Bool {
        activityStore.isBookmarked(questionId: question.id, sourceId: payload.id, uid: uid)
    }

    // MARK: - Chrome

    /// The floating HUD: everything the navigation bar and the hairline progress strip used to
    /// hold, in one pane of glass over the question.
    private func hud(showsTrack: Bool) -> some View {
        RunnerHUD(
            number: currentIndex + 1,
            total: questions.count,
            blockLabel: isSectioned ? "Block \(sectionIndex + 1)/\(sections.count)" : nil,
            remainingSeconds: remainingSeconds,
            capacitySeconds: capacitySeconds,
            isPaused: isTimerPaused,
            isBookmarked: isCurrentBookmarked,
            showsInlineCounter: sizeClass == .regular,
            isPad: sizeClass == .regular,
            title: payload.name,
            modeLabel: payload.mode == .exam ? "Exam" : "Revision",
            // iPad landscape lists the questions in the sidebar, so the strip would be a copy.
            trackCells: showsTrack ? hudTrackCells : [],
            trackCurrent: currentIndex - navigatorRange.lowerBound,
            trackStart: navigatorRange.lowerBound,
            trackMarked: hudMarkedPills,
            onJump: { offset in
                let target = navigatorRange.lowerBound + offset
                // Revision reveals as it goes, so it never jumps past the furthest question seen.
                if payload.mode == .revision, target > furthestIndex {
                    HapticManager.warning()
                    return
                }
                jump(to: target)
            },
            onClose: {
                HapticManager.light()
                if loadState == .ready, !responses.isEmpty {
                    showExitAlert = true
                } else {
                    dismiss()
                }
            },
            onNavigator: {
                guard loadState == .ready else { return }
                HapticManager.light()
                showNavigator = true
            },
            onBookmark: {
                guard let question = currentQuestion else { return }
                toggleBookmark(question)
            }
        )
    }

    /// Bookmarked questions in the block, as offsets into `hudTrackCells`.
    private var hudMarkedPills: Set<Int> {
        let range = navigatorRange
        guard !range.isEmpty, range.upperBound <= questions.count else { return [] }
        return Set(range.filter { isBookmarked(questions[$0]) }.map { $0 - range.lowerBound })
    }

    /// The block on screen as answer-sheet cells, for the HUD's progress track.
    private var hudTrackCells: [MedxSheetCell] {
        let range = navigatorRange
        guard !range.isEmpty, range.upperBound <= statuses.count else { return [] }
        return statuses[range].map(\.sheetCell)
    }

    /// What the clock was wound to, so the bar can draw a fraction rather than a bare number.
    /// The block's own duration in exam mode; the fixed sixty seconds a revision question gets
    /// otherwise.
    private var capacitySeconds: Int {
        payload.mode == .exam ? max(activeSection.seconds, 1) : 60
    }

    private var isCurrentBookmarked: Bool {
        guard let question = currentQuestion else { return false }
        return isBookmarked(question)
    }

    // MARK: - Active runner

    private func activeRunner(question: Question) -> some View {
        // iPad in landscape gets three panes: the navigator as a sidebar, the question as a
        // readable column, and in revision the explanation beside it. Everything else (iPhone,
        // iPad portrait) is the single column with the navigator in the HUD's pill strip.
        GeometryReader { geo in
            runnerLayout(
                question: question,
                wide: sizeClass == .regular && geo.size.width > geo.size.height
            )
        }
    }

    private func runnerLayout(question: Question, wide: Bool) -> some View {
        let response = responses[question.id]
        let isRevealed = payload.mode == .revision && revealedQuestions[question.id] == true
        let isLocked = payload.mode == .revision && response != nil
        let explanationBeside = wide && payload.mode == .revision

        return HStack(alignment: .top, spacing: 0) {
            if wide {
                RunnerSidebarNavigator(
                    range: navigatorRange,
                    currentIndex: currentIndex,
                    furthestIndex: furthestIndex,
                    statuses: statuses,
                    marked: Set(navigatorRange.filter { $0 < questions.count && isBookmarked(questions[$0]) }),
                    lockAhead: payload.mode == .revision,
                    sectionLabel: isSectioned ? activeSection.label : nil,
                    submitLabel: isSectioned && !isFinalSection ? "Submit block" : "Submit",
                    onSelect: { index in
                        if payload.mode == .revision, index > furthestIndex {
                            HapticManager.warning()
                            return
                        }
                        jump(to: index)
                    },
                    onSubmit: {
                        HapticManager.medium()
                        showSubmitConfirm = true
                    }
                )
                .frame(width: 290)
                .padding(.leading, 20)
                .padding(.vertical, 12)
            }

            questionColumn(
                question: question,
                response: response,
                isRevealed: isRevealed,
                isLocked: isLocked,
                inlineExplanation: !explanationBeside
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                runnerActionBar(question: question, isRevealed: isRevealed)
            }

            if explanationBeside {
                RunnerExplanationPanel(question: question, response: response, isRevealed: isRevealed)
                    .frame(width: 360)
                    .padding(.trailing, 20)
                    .padding(.vertical, 12)
            }
        }
        // The faint dot grid from the mockup, behind the question and under both bars.
        .background {
            // Flat near-black with the faint dot grid: no coloured glow behind the HUD.
            RunnerDotField()
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            hud(showsTrack: !wide)
        }
        .animation(reduceMotion ? nil : MedxDS.settle, value: isRevealed)
    }

    private func questionColumn(
        question: Question,
        response: QuestionResponse?,
        isRevealed: Bool,
        isLocked: Bool,
        inlineExplanation: Bool
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Color.clear
                        .frame(height: 1)
                        .id(topAnchor)

                    RunnerQuestionCard(
                        question: question,
                        showsUngradedNotice: !payload.gradable,
                        number: currentIndex + 1,
                        sourceTag: payload.questionTags.flatMap { tags in
                            tags.indices.contains(currentIndex) ? tags[currentIndex] : nil
                        }
                    )
                    // Double-tap the stem to bookmark, the way Photos favourites a picture.
                    // The HUD button stays the discoverable route; VoiceOver gets the same thing
                    // as a custom action rather than a gesture it cannot perform.
                    .onTapGesture(count: 2) {
                        toggleBookmark(question)
                    }
                    .accessibilityAction(named: isBookmarked(question) ? "Remove bookmark" : "Bookmark question") {
                        toggleBookmark(question)
                    }

                    answerSection(
                        question: question,
                        response: response,
                        isRevealed: isRevealed,
                        isLocked: isLocked
                    )

                    if isRevealed, inlineExplanation {
                        RunnerExplanationCard(question: question, response: response)
                            .id("medx.explanation")
                            // Fades up into the space the layout opens below the options.
                            .transition(
                                .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
                            )
                    }
                }
                .padding(.horizontal, MedxDS.gutter)
                .padding(.top, 12)
                .padding(.bottom, 24)
                // iPad: a readable column rather than lines the width of a landscape screen.
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .medxScrollEdge()
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(horizontalQuestionGesture)
            .onChange(of: currentIndex) { _, _ in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    proxy.scrollTo(topAnchor, anchor: .top)
                }
            }
            #if DEBUG
            // Screenshot runs only: `-medxScroll 1` brings the revealed explanation into view.
            .onChange(of: isRevealed) { _, revealed in
                guard revealed, UserDefaults.standard.integer(forKey: "medxScroll") > 0 else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    proxy.scrollTo("medx.explanation", anchor: .top)
                }
            }
            #endif
        }
    }

    // MARK: - Answers

    /// Just the options.
    ///
    /// There used to be a line of prose above them — "Choose the best answer.", then "Tap
    /// another option to change your answer." — on every question of every sitting. Four
    /// lettered rows under a stem do not need to be introduced, and re-reading the same
    /// sentence forty times is what makes a screen feel cluttered rather than calm.
    private func answerSection(
        question: Question,
        response: QuestionResponse?,
        isRevealed: Bool,
        isLocked: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Keyed on position, not on `option.id`: a backend that hands out duplicate option ids
            // would otherwise make `ForEach` draw one row several times, which is exactly what the
            // Marrow papers did.
            ForEach(Array(question.options.enumerated()), id: \.offset) { pair in
                QuestionOptionButton(
                    option: pair.element,
                    index: pair.offset,
                    isChosen: response?.chosenId == pair.element.id,
                    isCorrect: pair.element.correct == true || question.correctIds.contains(pair.element.id),
                    isRevealed: isRevealed,
                    isLocked: isLocked
                ) {
                    handlePickOption(question: question, chosenId: pair.element.id)
                }
            }
        }
    }

    // MARK: - Bottom action bar

    private func runnerActionBar(question: Question, isRevealed: Bool) -> some View {
        RunnerActionBar(
            number: currentIndex + 1,
            total: questions.count,
            isLastQuestion: isLastQuestion,
            canGoBack: currentIndex > activeSection.start,
            canAdvance: canAdvance(isRevealed: isRevealed),
            // The HUD's inline counter is the iPad's; the centre one here is the phone's.
            showsCounter: sizeClass != .regular,
            isPad: sizeClass == .regular,
            onBack: {
                goBack()
            },
            onNavigator: {
                guard loadState == .ready else { return }
                HapticManager.light()
                showNavigator = true
            },
            onAdvance: {
                advance()
            }
        )
    }

    /// Swipe left / right between questions. `simultaneousGesture` so the vertical scroll
    /// keeps working, and the thresholds require a clearly horizontal flick.
    private var horizontalQuestionGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = abs(value.translation.height)
                guard abs(horizontal) > 64, abs(horizontal) > vertical * 1.4 else { return }

                if horizontal < 0 {
                    guard let question = currentQuestion else { return }
                    let isRevealed = payload.mode == .revision && revealedQuestions[question.id] == true
                    guard canAdvance(isRevealed: isRevealed), !isLastQuestion else {
                        HapticManager.warning()
                        return
                    }
                    nextQuestion()
                } else if currentIndex > 0 {
                    goBack()
                }
            }
    }

    // MARK: - Loading & unavailable

    private var loadingState: some View {
        VStack(spacing: 14) {
            MedxSticker(payload.section.sticker, size: 54, tilt: -8)

            ProgressView()
                .controlSize(.large)
            Text("Preparing your sitting")
                .font(.headline)
            Text(payload.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unavailableState(message: String) -> some View {
        ContentUnavailableView {
            Label {
                Text("Sitting Unavailable")
            } icon: {
                MedxSticker("ghost", size: 44)
            }
        } description: {
            Text(message)
        } actions: {
            VStack(spacing: 10) {
                Button {
                    HapticManager.light()
                    loadState = .loading
                    Task { await loadSittingQuestions() }
                } label: {
                    Text("Try Again")
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 150, minHeight: 44)
                }
                .medxFilledButton()
                .buttonBorderShape(.capsule)

                Button("Close") { dismiss() }
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    // MARK: - Actions

    private func toggleBookmark(_ question: Question) {
        guard uid != nil else { return }
        activityStore.toggleBookmark(question: question, payload: payload, uid: uid)
        HapticManager.selection()
    }

    private func handlePickOption(question: Question, chosenId: Int) {
        // Revision locks once the key has been shown; there is no un-seeing it.
        if payload.mode == .revision, responses[question.id] != nil { return }

        // Exam mode: tapping the chosen option again clears the answer.
        if payload.mode == .exam, responses[question.id]?.chosenId == chosenId {
            responses.removeValue(forKey: question.id)
            refreshStatuses()
            HapticManager.light()
            return
        }

        let isCorrect = question.correctIds.contains(chosenId)
        responses[question.id] = QuestionResponse(
            questionId: question.id,
            chosenId: chosenId,
            correct: isCorrect
        )

        if payload.mode == .revision {
            revealedQuestions[question.id] = true
            if isCorrect { HapticManager.success() } else { HapticManager.error() }
        } else {
            HapticManager.selection()
        }
        refreshStatuses()
        persistSnapshot()
    }

    private func handleTimeout() {
        if payload.mode == .exam {
            // A spent block closes that block, not the paper. Only the last one ends the
            // sitting, which `submitSection` handles.
            submitSection()
        } else if let question = currentQuestion, responses[question.id] == nil {
            responses[question.id] = QuestionResponse(
                questionId: question.id,
                chosenId: nil,
                correct: false,
                timedOut: true
            )
            revealedQuestions[question.id] = true
            refreshStatuses()
            HapticManager.warning()
        }
    }

    private func tick() {
        // The handover between blocks holds the clock: the next section's minutes start when
        // it is actually opened, not while its summary is being read.
        guard loadState == .ready, !isFinished, handover == nil, resumeOffer == nil, !isTimerPaused else { return }
        ticksSinceSave += 1
        if ticksSinceSave >= 15 {
            ticksSinceSave = 0
            persistSnapshot()
        }
        if remainingSeconds > 0 {
            remainingSeconds -= 1
            fireTimeHaptics()
        } else {
            handleTimeout()
        }
    }

    /// A small button-tap haptic as the clock passes the halfway mark, and again entering the
    /// final fifth — the two thresholds the reference calls out, both kept light (the tick you
    /// feel holding an iOS button). Guarded so each fires once per armed clock.
    private func fireTimeHaptics() {
        let capacity = capacitySeconds
        guard capacity > 0 else { return }
        let fraction = Double(remainingSeconds) / Double(capacity)
        if !firedHaptic50, fraction <= 0.5 {
            firedHaptic50 = true
            HapticManager.light()
        }
        if !firedHaptic20, fraction <= 0.2 {
            firedHaptic20 = true
            HapticManager.light()
        }
    }

    /// Re-arm the halfway / final-fifth haptics for a freshly wound clock.
    private func armTimeHaptics() {
        firedHaptic50 = false
        firedHaptic20 = false
    }

    private func goBack() {
        guard currentIndex > activeSection.start else { return }
        HapticManager.light()
        currentIndex -= 1
        resetTimerForCurrentQuestion()
        refreshStatuses()
    }

    /// The Next button. The last question asks first: what is still open and what was flagged,
    /// with a way back to the first unanswered one, instead of ending the paper on one tap.
    private func advance() {
        HapticManager.medium()
        if isLastQuestion { showSubmitConfirm = true } else { nextQuestion() }
    }

    private func nextQuestion() {
        guard currentIndex + 1 < activeSection.end else { return }
        currentIndex += 1
        furthestIndex = max(furthestIndex, currentIndex)
        resetTimerForCurrentQuestion()
        refreshStatuses()
    }

    private func jump(to index: Int) {
        // The navigator only offers this block's questions, but a stale sheet must not be able
        // to jump into a submitted one.
        guard questions.indices.contains(index),
              index >= activeSection.start,
              index < activeSection.end,
              index != currentIndex
        else { return }
        HapticManager.light()
        currentIndex = index
        furthestIndex = max(furthestIndex, index)
        resetTimerForCurrentQuestion()
        refreshStatuses()
    }

    /// Revision runs a 60s clock per question; re-arm it only when the question is still open.
    private func resetTimerForCurrentQuestion() {
        guard payload.mode == .revision else { return }
        if let question = currentQuestion, responses[question.id] != nil { return }
        remainingSeconds = 60
        armTimeHaptics()
    }

    private func finishSitting() {
        MedxSittingSnapshot.clear(kind: payload.kind, id: payload.id)
        // The block that was still open when the paper ended is scored too, so a paper
        // submitted early does not lose the section it was in.
        logSection()
        completedSeconds = Int(Date().timeIntervalSince(startedAt))
        isFinished = true
        HapticManager.success()
        MedxLiveActivityController.shared.endExam(state: examActivityState)
        saveSittingAttempt()
    }

    /// Close the block being sat, or open the next one.
    ///
    /// A sectioned paper is scored per block *as it is submitted*, because that is the only
    /// moment the block's own clock is still meaningful. There is no way back into a submitted
    /// block — that is what makes it a section rather than a bookmark.
    private func submitSection() {
        guard isSectioned, !isFinished else {
            finishSitting()
            return
        }
        logSection()

        guard !isFinalSection else {
            MedxSittingSnapshot.clear(kind: payload.kind, id: payload.id)
            completedSeconds = Int(Date().timeIntervalSince(startedAt))
            isFinished = true
            HapticManager.success()
            MedxLiveActivityController.shared.endExam(state: examActivityState)
            saveSittingAttempt()
            return
        }

        let closed = activeSection
        let closedRow = sectionLog.last
        sectionIndex += 1
        currentIndex = activeSection.start
        furthestIndex = max(furthestIndex, currentIndex)
        refreshStatuses()
        HapticManager.success()

        handover = MedxSectionHandover(
            closedLabel: closed.label,
            score: closedRow?.score ?? 0,
            attempted: closedRow?.attempted ?? 0,
            total: closed.count,
            gradable: payload.gradable,
            nextLabel: activeSection.label,
            nextCount: activeSection.count,
            nextMinutes: activeSection.minutes,
            remainingSections: sections.count - sectionIndex
        )
    }

    /// Starts the block's clock, which is deliberately *not* running while the handover is on
    /// screen: a summary you are still reading must not be spending the next block's minutes.
    private func beginActiveSection() {
        handover = nil
        sectionStartedAt = Date()
        remainingSeconds = activeSection.seconds
        armTimeHaptics()
        lastPushedAnswered = -1
        refreshStatuses()
    }

    /// One row per submitted block, in the exact shape the PWA writes.
    ///
    /// Skipped entirely for an unsectioned paper rather than filing a one-row breakdown of
    /// itself, and guarded on the index so submitting twice cannot double-count.
    private func logSection() {
        guard isSectioned else { return }
        guard !sectionLog.contains(where: { $0.index == sectionIndex }) else { return }

        let slice = questionsInSection
        let rows = slice.compactMap { responses[$0.id] }
        sectionLog.append(
            MedxAttemptSection(
                index: sectionIndex,
                label: activeSection.label,
                total: slice.count,
                score: rows.filter(\.correct).count,
                attempted: rows.filter { $0.chosenId != nil }.count,
                seconds: Int(Date().timeIntervalSince(sectionStartedAt))
            )
        )
    }

    private func saveSittingAttempt() {
        guard let session = authService.currentSession else { return }
        let score = responses.values.filter { $0.correct }.count
        let attempted = responses.values.filter { $0.chosenId != nil }.count

        let attempt = SittingAttempt(
            id: nil,
            uid: session.uid,
            profile: authService.currentProfile?.handle,
            kind: payload.kind,
            sourceId: payload.id,
            name: payload.name,
            subject: payload.subject,
            mode: payload.mode.rawValue,
            gradable: payload.gradable,
            total: questions.count,
            score: score,
            attempted: attempted,
            durationSeconds: completedSeconds,
            finishedAt: ISO8601DateFormatter().string(from: Date()),
            responses: Array(responses.values),
            sections: sectionLog.isEmpty ? nil : sectionLog.sorted { $0.index < $1.index }
        )

        Task {
            do {
                let token = try await AuthService.shared.getValidIdToken()
                try await FirestoreService.shared.saveAttempt(attempt, idToken: token)
            } catch {
                // Kept locally; the activity log still reflects the sitting.
            }
        }
    }

    private func loadSittingQuestions() async {
        // Once a paper is on screen it is never loaded again under the student. `.task` runs
        // again whenever the runner re-appears (a full-screen figure closing over it, the cover
        // being re-presented), and every run reset the sitting to question 1 with no answers:
        // Next moved on, then the paper snapped back. Only "Try Again" after a failure reloads.
        guard loadState != .ready || questions.isEmpty else { return }
        guard !isLoadingSitting else { return }
        isLoadingSitting = true
        defer { isLoadingSitting = false }
        do {
            let loaded: [Question]

            // A custom module or a "practise these" sitting arrives with its questions
            // already gathered from several source modules, so there is nothing to fetch.
            if let supplied = payload.questions, !supplied.isEmpty {
                loaded = supplied
            } else {
                let token = try await AuthService.shared.getValidIdToken()
                if payload.kind == "qbank" {
                    let module = try await FirestoreService.shared.fetchQBankModule(moduleId: payload.id, idToken: token)
                    loaded = module.questions ?? []
                } else {
                    loaded = try await FirestoreService.shared.fetchTestQuestions(testId: payload.id, idToken: token)
                }
            }

            guard !loaded.isEmpty else {
                loadState = .unavailable("This paper has no questions yet. Please check back later.")
                return
            }

            questions = MedxQuestionIdentity.uniqued(loaded)
            currentIndex = 0
            furthestIndex = 0
            responses = [:]
            revealedQuestions = [:]
            sectionIndex = 0
            sectionLog = []

            // Sections only apply to a timed paper. Sitting a grand paper in revision mode is
            // 60 seconds a question with the answer revealed as you go, and blocking the back
            // half of it behind a submit would be pointless there.
            let requested = payload.mode == .exam ? (payload.sections ?? []) : []
            let resolved = MedxRunnerSection.clamped(requested, to: loaded.count)
            sections = resolved.count > 1 ? resolved : [wholePaperSection(count: loaded.count)]

            startedAt = Date()
            sectionStartedAt = Date()
            remainingSeconds = payload.mode == .exam ? sections[0].seconds : 60
            armTimeHaptics()
            loadState = .ready
            refreshStatuses()

            // An unfinished sitting of this exact paper (same questions, same mode) is offered
            // back. A different upload under the same id fails the fingerprint and is dropped.
            if persistsSittings, let saved = MedxSittingSnapshot.load(kind: payload.kind, id: payload.id) {
                if saved.fingerprint == MedxSittingSnapshot.fingerprint(questions),
                   saved.mode == payload.mode.rawValue {
                    resumeOffer = saved
                } else {
                    MedxSittingSnapshot.clear(kind: payload.kind, id: payload.id)
                }
            }

            if payload.mode == .exam {
                MedxLiveActivityController.shared.startExam(
                    name: payload.name,
                    subject: payload.subject,
                    totalQuestions: loaded.count,
                    state: examActivityState
                )
            }

            #if DEBUG
            await debugAutopilot()
            #endif
        } catch {
            loadState = .unavailable("We couldn't load this sitting. Check your connection and try again.")
        }
    }

    #if DEBUG
    /// Screenshot runs only. `-medxScreen runner-revision` answers the first question wrongly so
    /// the reveal is on screen; `-medxScreen review` answers the paper (two right, one wrong, …)
    /// and submits it, so the sitting review can be captured.
    private func debugAutopilot() async {
        guard MedxDemoMode.isOn,
              let screen = UserDefaults.standard.string(forKey: "medxScreen")
        else { return }
        try? await Task.sleep(nanoseconds: 900_000_000)

        switch screen {
        case "runner-custom-next":
            // A real custom module (questions supplied, started from the Custom modules sheet):
            // answer question 1, then press Next exactly as the button does. Question 2 must show.
            if let first = questions.first, let pick = first.correctIds.first ?? first.options.first?.id {
                handlePickOption(question: first, chosenId: pick)
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            advance()
            print("[CustomNext] after Next: question \(currentIndex + 1) of \(questions.count)")
        case "runner-zoom":
            // The figure viewer over the runner, opened the way a tap on a figure opens it. The
            // demo questions carry no figures, so the run draws one: a cluster of cocci.
            let size = CGSize(width: 900, height: 640)
            let figure = UIGraphicsImageRenderer(size: size).image { context in
                UIColor(white: 0.96, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                let colours: [UIColor] = [.systemPurple, .systemIndigo, .systemPink]
                for index in 0..<46 {
                    let angle: Double = Double(index) * 2.4
                    let radius: Double = 39.6 * Double(index).squareRoot()
                    let x: CGFloat = CGFloat(450.0 + radius * cos(angle)) - 26
                    let y: CGFloat = CGFloat(300.0 + radius * sin(angle)) - 26
                    colours[index % colours.count].withAlphaComponent(0.8).setFill()
                    UIBezierPath(ovalIn: CGRect(x: x, y: y, width: 52, height: 52)).fill()
                }
                let label = "Gram-positive cocci in clusters (x1000)" as NSString
                label.draw(at: CGPoint(x: 40, y: 580), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 30, weight: .semibold),
                    .foregroundColor: UIColor.darkGray
                ])
            }
            MedxImageZoom.present(image: figure)
        case "runner-revision":
            guard let question = questions.first,
                  let wrong = question.options.first(where: { !question.correctIds.contains($0.id) })
            else { return }
            handlePickOption(question: question, chosenId: wrong.id)
        case "runner-batch":
            // A fresh upload with no question ids: answer the first, move to the second, which
            // must still be open.
            if let first = questions.first, let pick = first.correctIds.first ?? first.options.first?.id {
                handlePickOption(question: first, chosenId: pick)
            }
            if questions.count > 1 { jump(to: 1) }
        case "runner-navigator":
            // Five answered, the sixth on screen with a pick, then the navigator over it.
            for question in questions.prefix(5) {
                guard let pick = question.correctIds.first ?? question.options.first?.id else { continue }
                handlePickOption(question: question, chosenId: pick)
            }
            if questions.count > 5 {
                jump(to: 5)
                if let option = questions[5].options.dropFirst().first {
                    handlePickOption(question: questions[5], chosenId: option.id)
                }
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
            showNavigator = true
        case "runner-answered":
            // Exam mode, three picked, the third on screen with its pick showing.
            for question in questions.prefix(3) {
                guard let pick = question.options.dropFirst().first?.id ?? question.options.first?.id else { continue }
                handlePickOption(question: question, chosenId: pick)
            }
            if questions.count > 2 { jump(to: 2) }
            if let question = currentQuestion { toggleBookmark(question) }
        case "runner-lowtime":
            // The last fifth of the clock: the ring drains orange.
            for question in questions.prefix(4) {
                guard let pick = question.correctIds.first ?? question.options.first?.id else { continue }
                handlePickOption(question: question, chosenId: pick)
            }
            if questions.count > 4 { jump(to: 4) }
            remainingSeconds = max(capacitySeconds / 7, 30)
        case "runner-submit":
            // Most answered, two flagged, three left open, then Submit on the last question.
            for (index, question) in questions.enumerated() where index % 4 != 1 || index > 11 {
                guard let pick = question.correctIds.first ?? question.options.first?.id else { continue }
                handlePickOption(question: question, chosenId: pick)
            }
            for question in questions.prefix(6).suffix(2) { toggleBookmark(question) }
            jump(to: max(activeSection.end - 1, 0))
            try? await Task.sleep(nanoseconds: 400_000_000)
            showSubmitConfirm = true
        case "runner-leave":
            for question in questions.prefix(2) {
                guard let pick = question.correctIds.first ?? question.options.first?.id else { continue }
                handlePickOption(question: question, chosenId: pick)
            }
            if questions.count > 2 { jump(to: 2) }
            showExitAlert = true
        case "runner-resume":
            // What opening a paper left half-way looks like.
            let picks = questions.prefix(5).compactMap { question -> QuestionResponse? in
                guard let pick = question.correctIds.first ?? question.options.first?.id else { return nil }
                return QuestionResponse(questionId: question.id, chosenId: pick, correct: question.correctIds.contains(pick))
            }
            resumeOffer = MedxSittingSnapshot(
                fingerprint: MedxSittingSnapshot.fingerprint(questions),
                mode: payload.mode.rawValue,
                currentIndex: min(5, questions.count - 1),
                furthestIndex: min(5, questions.count - 1),
                responses: picks,
                revealed: [],
                remainingSeconds: max(capacitySeconds * 3 / 5, 60),
                sectionIndex: 0,
                sectionLog: [],
                elapsedSeconds: capacitySeconds * 2 / 5,
                savedAt: Date()
            )
        case "review", "review-question", "review-custom":
            for (index, question) in questions.enumerated() {
                let wrong = question.options.first(where: { !question.correctIds.contains($0.id) })?.id
                let pick: Int? = index % 3 == 2 ? wrong : question.correctIds.first
                guard let pick else { continue }
                responses[question.id] = QuestionResponse(
                    questionId: question.id,
                    chosenId: pick,
                    correct: question.correctIds.contains(pick)
                )
            }
            refreshStatuses()
            finishSitting()
        default:
            break
        }
    }
    #endif

    /// The single block an unsectioned paper is sat in. Its clock is the paper's own official
    /// duration where it has one — a Marrow subject paper is not always one minute a question
    /// — and one minute a question otherwise.
    private func wholePaperSection(count: Int) -> MedxRunnerSection {
        let total = max(count, 1)
        let seconds = payload.examSeconds ?? (total * 60)
        return MedxRunnerSection(
            label: "Section 1",
            start: 0,
            count: total,
            minutes: max(Int((Double(seconds) / 60).rounded()), 1)
        )
    }
}

// MARK: - Load state

enum RunnerLoadState: Equatable {
    case loading
    case ready
    case unavailable(String)
}

// MARK: - Question card

/// Split out of the runner so a timer tick — which fires every second — does not force SwiftUI to
/// re-evaluate the question body as well.
///
/// **No card.** The stem sits directly on the page, full width. It used to be inside a `medxCard`, which
/// on a black page bought nothing except 32 points of gutter taken away from the longest text in the app
/// — and a Marrow stem with a figure in it needs every point. The HUD above and the options below are
/// what frame it.
struct RunnerQuestionCard: View {
    let question: Question
    let showsUngradedNotice: Bool
    /// The question's number in the paper, for the label over the stem.
    var number: Int? = nil
    /// Where a question in a mixed paper came from ("FMGE June 2023"): a neutral chip.
    var sourceTag: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if number != nil || showsUngradedNotice || sourceTag != nil {
                HStack(spacing: 8) {
                    if let number {
                        Text("QUESTION \(number)")
                            .font(.caption2.weight(.heavy))
                            .tracking(0.8)
                            .foregroundStyle(MedxTheme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule(style: .continuous).fill(MedxTheme.accent.opacity(0.14)))
                    }
                    if let sourceTag, !sourceTag.isEmpty {
                        MedxSourceTag(sourceTag)
                    }
                    if showsUngradedNotice {
                        MedxBadge("No official key", tint: MedxDS.warn)
                    }
                    Spacer(minLength: 0)
                }
            }

            // Images embedded in the HTML render inline; `question.images` carries the separately
            // exported figures, so both paths are shown.
            HTMLRichTextView(html: question.displayText, fontSize: 18, weight: .semibold)

            if let images = question.images, !images.isEmpty {
                VStack(spacing: 10) {
                    ForEach(images, id: \.self) { raw in
                        RunnerFigure(raw: raw)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(MedxDS.row)
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [MedxTheme.accent.opacity(0.45), MedxDS.line, MedxDS.line],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
        }
    }
}

// MARK: - Figure

/// A tappable exported figure. Bare filenames are resolved against the image CDN, the
/// same way the ones inside the HTML are.
struct RunnerFigure: View {
    let raw: String

    var body: some View {
        if let url = MedxRichText.figureURL(raw) {
            Button {
                HapticManager.light()
                MedxImageZoom.present(url)
            } label: {
                CachedAsyncImage(url: url, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 280)
                    .clipShape(MedxDS.shape(MedxDS.control))
                    .overlay(
                        MedxDS.shape(MedxDS.control)
                            .strokeBorder(MedxDS.line.opacity(0.35), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Figure")
            .accessibilityHint("Opens the image full screen")
        }
    }
}

// MARK: - Explanation

struct RunnerExplanationCard: View {
    let question: Question
    let response: QuestionResponse?

    private var outcome: RunnerOutcome { RunnerOutcome(response: response) }

    private var correctLabel: String? {
        question.options.first {
            $0.correct == true || question.correctIds.contains($0.id)
        }?.label
    }

    private var reference: String {
        question.reference?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: outcome.icon)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(outcome.color))

                VStack(alignment: .leading, spacing: 1) {
                    Text(outcome.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(outcome.color)
                    if let correctLabel, !correctLabel.isEmpty {
                        Text(outcome == .correct ? "You picked \(correctLabel)" : "Correct answer is \(correctLabel)")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }

            Rectangle()
                .fill(MedxDS.line)
                .frame(height: 1)

            Label {
                Text("Explanation")
                    .font(.subheadline.weight(.bold))
            } icon: {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(MedxDS.warn)
            }

            if let explanation = question.explanation, !explanation.isEmpty {
                HTMLRichTextView(html: explanation, fontSize: 15, weight: .regular, textColor: .secondary)
            } else {
                Text("No explanation provided for this question.")
                    .font(MedxType.body)
                    .foregroundStyle(.secondary)
            }

            if !reference.isEmpty {
                Label(reference, systemImage: "book.closed")
                    .font(MedxType.body)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [outcome.color.opacity(0.12), MedxDS.row],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(outcome.color.opacity(0.35), lineWidth: 1)
                }
        }
    }
}

// MARK: - Per-question status

enum RunnerQuestionStatus {
    case unanswered
    case answered
    case correct
    case wrong
    case timedOut

    /// How this question draws on the answer sheet — the runner's track, and the review after it.
    ///
    /// One mapping, in one place, so the HUD's grid and the review's grid cannot disagree about what a
    /// timed-out question looks like.
    var sheetCell: MedxSheetCell {
        switch self {
        case .unanswered: return .pending
        case .answered: return .answered
        case .correct: return .correct
        case .wrong: return .wrong
        case .timedOut: return .missed
        }
    }

    var chipFill: Color {
        switch self {
        case .unanswered: return MedxDS.sunken
        case .answered: return MedxTheme.accent.opacity(0.16)
        case .correct: return MedxDS.correct.opacity(0.16)
        case .wrong: return MedxDS.wrong.opacity(0.16)
        case .timedOut: return MedxDS.warn.opacity(0.16)
        }
    }

    var chipForeground: Color {
        switch self {
        case .unanswered: return .secondary
        case .answered: return MedxTheme.accent
        case .correct: return MedxDS.correct
        case .wrong: return MedxDS.wrong
        case .timedOut: return MedxDS.warn
        }
    }

    /// The hue this state tints its glass with, or `nil` where the state *is* "nothing has happened here
    /// yet" — an untouched question should be a clear pane, not a coloured one.
    var tileHue: Color? {
        switch self {
        case .unanswered: return nil
        case .answered: return MedxTheme.accent
        case .correct: return MedxDS.correct
        case .wrong: return MedxDS.wrong
        case .timedOut: return MedxDS.warn
        }
    }

    var legendLabel: String {
        switch self {
        case .unanswered: return "Not answered"
        case .answered: return "Answered"
        case .correct: return "Correct"
        case .wrong: return "Wrong"
        case .timedOut: return "Timed out"
        }
    }
}

// MARK: - Outcome

enum RunnerOutcome: Equatable {
    case correct
    case incorrect
    case timedOut
    case unanswered

    init(response: QuestionResponse?) {
        guard let response else {
            self = .unanswered
            return
        }
        if response.timedOut == true {
            self = .timedOut
        } else if response.chosenId == nil {
            self = .unanswered
        } else {
            self = response.correct ? .correct : .incorrect
        }
    }

    var title: String {
        switch self {
        case .correct: return "Correct"
        case .incorrect: return "Incorrect"
        case .timedOut: return "Time up"
        case .unanswered: return "Not answered"
        }
    }

    var icon: String {
        switch self {
        case .correct: return "checkmark.circle.fill"
        case .incorrect: return "xmark.circle.fill"
        case .timedOut: return "clock.badge.exclamationmark.fill"
        case .unanswered: return "minus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .correct: return MedxDS.correct
        case .incorrect: return MedxDS.wrong
        case .timedOut: return MedxDS.warn
        case .unanswered: return MedxDS.warn
        }
    }
}

// MARK: - Question navigator

struct QuestionNavigatorSheet: View {
    /// The questions this sheet may offer, absolute in the paper. A sectioned sitting passes
    /// only the block being sat — a submitted block cannot be re-entered, so listing it here
    /// would be offering a jump that `jump(to:)` then has to refuse.
    let range: Range<Int>
    let currentIndex: Int
    let furthestIndex: Int
    let statuses: [RunnerQuestionStatus]
    /// Revision reveals answers as you go, so jumping past the frontier is not allowed.
    let lockAhead: Bool
    /// Set for a sectioned paper, so the title says which block is on screen. The tile numbers
    /// stay absolute in the paper — "question 63" is what the answer key calls it.
    let sectionLabel: String?
    /// The palette the paper is being sat in, so the navigator's page wears the same wash as
    /// the runner behind it rather than reverting to plain grey mid-sitting.
    let section: MedxSection
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private var legend: [RunnerQuestionStatus] {
        lockAhead
            ? [.unanswered, .correct, .wrong, .timedOut]
            : [.unanswered, .answered]
    }

    private var counts: (answered: Int, open: Int, flaggedOutcome: Int) {
        var answered = 0
        var open = 0
        var wrong = 0
        for index in range {
            let status = statuses.indices.contains(index) ? statuses[index] : .unanswered
            switch status {
            case .unanswered: open += 1
            case .wrong, .timedOut: answered += 1; wrong += 1
            default: answered += 1
            }
        }
        return (answered, open, wrong)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 10) {
                        summaryPill(value: counts.answered, label: "answered", tint: MedxTheme.accent)
                        summaryPill(value: counts.open, label: "left", tint: .secondary)
                        if lockAhead {
                            summaryPill(value: counts.flaggedOutcome, label: "wrong", tint: MedxDS.wrong)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 8)], spacing: 8) {
                        ForEach(Array(range), id: \.self) { index in
                            tile(for: index)
                        }
                    }

                    // The legend as one wrapping row of chips rather than a list.
                    LazyVGrid(
                        columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(Array(legend.enumerated()), id: \.offset) { _, status in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(status.tileHue ?? MedxDS.sunken)
                                    .frame(width: 10, height: 10)
                                Text(status.legendLabel)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle(sectionLabel ?? "Questions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func summaryPill(value: Int, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(MedxType.figure(22, weight: .bold))
                .foregroundStyle(tint)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MedxDS.raised))
    }

    private func tile(for index: Int) -> some View {
        let status = statuses.indices.contains(index) ? statuses[index] : .unanswered
        let isCurrent = index == currentIndex
        let isLocked = lockAhead && index > furthestIndex
        let hue = status.tileHue

        return Button {
            onSelect(index)
        } label: {
            Text("\(index + 1)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(isCurrent ? MedxDS.page : (hue ?? Color.primary))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background {
                    Capsule(style: .continuous)
                        .fill(isCurrent ? Color.primary : (hue?.opacity(0.28) ?? MedxDS.sunken))
                }
                .opacity(isLocked ? 0.35 : 1)
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(MedxPressStyle())
        .disabled(isLocked)
        .accessibilityLabel("Question \(index + 1)")
        .accessibilityValue(isCurrent ? "Current, \(status.legendLabel)" : status.legendLabel)
    }
}

// MARK: - Between sections

/// What was just submitted and what is about to open.
///
/// A submitted block cannot be re-entered, so the paper jumping fifty questions forward on its
/// own would be the single most alarming thing the runner could do. This is the acknowledgement
/// that makes it a handover instead.
struct MedxSectionHandover: Identifiable, Hashable {
    let closedLabel: String
    let score: Int
    let attempted: Int
    let total: Int
    let gradable: Bool
    let nextLabel: String
    let nextCount: Int
    let nextMinutes: Int
    let remainingSections: Int

    var id: String { closedLabel + "→" + nextLabel }
}

struct MedxSectionHandoverSheet: View {
    let summary: MedxSectionHandover
    let onContinue: () -> Void

    /// The closed block as cells. `MedxSectionHandover` carries a score, an attempted count and a total
    /// and no per-question detail — the responses stay on the runner — so this says exactly that much:
    /// right, then wrong, then never reached.
    private var closedCells: [MedxSheetCell] {
        let total = max(summary.total, 1)
        let right = summary.gradable ? min(summary.score, total) : 0
        let attempted = min(summary.attempted, total)
        let wrong = max(attempted - right, 0)

        var cells = [MedxSheetCell](repeating: .correct, count: right)
        cells.append(contentsOf: [MedxSheetCell](repeating: summary.gradable ? .wrong : .answered, count: wrong))
        cells.append(contentsOf: [MedxSheetCell](repeating: .pending, count: max(total - right - wrong, 0)))
        return cells
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // This is the one screen in the app with no navigation bar and no way back, so it has
                    // to introduce itself. An in-content header was that introduction and was kept alive for
                    // this single caller; the three voices say the same thing in less furniture.
                    Text("\(summary.closedLabel) submitted")
                        .medxTag()

                    Text(summary.nextLabel)
                        .font(MedxType.display)
                        .foregroundStyle(.primary)

                    Text("\(summary.nextCount) questions, \(summary.nextMinutes) minutes. "
                         + "The block you just submitted is closed for good, and this one's clock starts "
                         + "when you tap below.")
                        .font(MedxType.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // The block you just closed, as the same grid the HUD was drawing a moment ago.
                    MedxAnswerSheet(
                        cells: closedCells,
                        scale: .sheet,
                        label: "\(summary.attempted) of \(summary.total) attempted"
                    )

                    HStack(alignment: .top, spacing: 10) {
                        if summary.gradable {
                            MedxStat("\(summary.score)/\(summary.total)", label: "scored", tint: MedxDS.correct)
                        }
                        MedxStat("\(summary.attempted)/\(summary.total)", label: "attempted")
                        MedxStat(
                            "\(summary.remainingSections)",
                            label: summary.remainingSections == 1 ? "block left" : "blocks left"
                        )
                    }

                    if !summary.gradable {
                        Text("This paper came through without an answer key, so nothing here is scored, only what you attempted is recorded.")
                            .font(MedxType.body)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, MedxDS.gutter)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }

            Button {
                HapticManager.medium()
                onContinue()
            } label: {
                Text("Start \(summary.nextLabel)")
                    .font(MedxType.heading)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .medxFilled(MedxTheme.accent)
            .medxFloatingBar()
        }
        .medxPage()
        // Full screen and one way out on purpose. There is nothing behind this worth looking
        // at — the block it would show is closed — and a swipe-to-dismiss would start the next
        // section's clock by accident.
        .interactiveDismissDisabled()
    }
}


// MARK: - Saved sitting

/// An unfinished sitting, kept on the device so leaving is not losing.
///
/// Keyed by the paper (`kind` + `id`) and fingerprinted by the question ids actually loaded, so a
/// paper that was re-uploaded under the same id with different questions never has an old
/// sitting's answers laid over it. One per paper; finishing or discarding removes it.
struct MedxSittingSnapshot: Codable, Equatable {
    let fingerprint: String
    let mode: String
    let currentIndex: Int
    let furthestIndex: Int
    let responses: [QuestionResponse]
    let revealed: [Int]
    let remainingSeconds: Int
    let sectionIndex: Int
    let sectionLog: [MedxAttemptSection]
    let elapsedSeconds: Int
    let savedAt: Date

    private static func key(kind: String, id: String) -> String { "medx.sitting.\(kind).\(id)" }

    static func fingerprint(_ questions: [Question]) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for question in questions {
            hash = (hash ^ UInt64(bitPattern: Int64(question.id))) &* 1_099_511_628_211
        }
        return "\(questions.count)-\(String(hash, radix: 16))"
    }

    static func load(kind: String, id: String) -> MedxSittingSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key(kind: kind, id: id)) else { return nil }
        return try? JSONDecoder().decode(MedxSittingSnapshot.self, from: data)
    }

    func save(kind: String, id: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key(kind: kind, id: id))
    }

    static func clear(kind: String, id: String) {
        UserDefaults.standard.removeObject(forKey: key(kind: kind, id: id))
    }

    /// "Question 14 of 50 · 12 answered · 31:20 left"
    func summary(total: Int) -> String {
        let answered = responses.filter { $0.chosenId != nil }.count
        let clamped = max(remainingSeconds, 0)
        let clock = clamped >= 3600
            ? String(format: "%d:%02d:%02d", clamped / 3600, (clamped % 3600) / 60, clamped % 60)
            : String(format: "%02d:%02d", clamped / 60, clamped % 60)
        return "Question \(currentIndex + 1) of \(total) · \(answered) answered · \(clock) left on the clock."
    }
}


// MARK: - Source tag

/// A small neutral chip naming where a question came from, on one line, truncating in the
/// middle so both the paper and the session stay readable ("FMGE…June 2023").
struct MedxSourceTag: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc.text")
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.08)))
        .frame(maxWidth: 220, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("From \(text)")
    }
}
