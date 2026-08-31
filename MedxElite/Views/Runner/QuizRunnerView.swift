import SwiftUI

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
    @State private var loadState: RunnerLoadState = .loading
    @State private var isFinished = false
    @State private var showExitAlert = false
    @State private var showNavigator = false
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
                    section: payload.section
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
            .medxPage(payload.section, intensity: 0)
            .navigationTitle(payload.name)
            .navigationBarTitleDisplayMode(.inline)
            // `RunnerHUD` *is* the chrome now. Two bands of furniture across the top of a phone
            // — a navigation bar and then a floating panel — is one too many, and the HUD
            // carries everything the toolbar did: close, counter, clock, bookmark.
            .toolbar(.hidden, for: .navigationBar)
            .alert("Leave sitting?", isPresented: $showExitAlert) {
                Button("Keep Going", role: .cancel) {}
                Button("Leave", role: .destructive) { dismiss() }
            } message: {
                Text(isSectioned
                     ? "Nothing is saved — including the \(sectionLog.count == 1 ? "block" : "blocks") you have already submitted."
                     : "Your progress in this sitting will not be saved.")
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
    private var hud: some View {
        RunnerHUD(
            number: currentIndex + 1,
            total: questions.count,
            blockLabel: isSectioned ? "Block \(sectionIndex + 1)/\(sections.count)" : nil,
            statuses: sectionStatuses,
            currentIndex: sectionRelativeIndex,
            remainingSeconds: remainingSeconds,
            capacitySeconds: capacitySeconds,
            isPaused: isTimerPaused,
            section: payload.section,
            isBookmarked: isCurrentBookmarked,
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

    /// The track shows the *block* being sat, not the whole paper. In a 3 × 50 grand paper the
    /// other hundred questions are either closed for good or not open yet, so colouring them
    /// would be reporting on something you cannot reach.
    private var sectionStatuses: [RunnerQuestionStatus] {
        guard statuses.count == questions.count else { return statuses }
        let lower = min(activeSection.start, statuses.count)
        let upper = min(activeSection.end, statuses.count)
        guard lower < upper else { return statuses }
        return Array(statuses[lower..<upper])
    }

    private var sectionRelativeIndex: Int {
        max(currentIndex - activeSection.start, 0)
    }

    /// What the clock was wound to, so the ring can draw a fraction rather than a bare number.
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
        let response = responses[question.id]
        let isRevealed = payload.mode == .revision && revealedQuestions[question.id] == true
        let isLocked = payload.mode == .revision && response != nil

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Color.clear
                        .frame(height: 1)
                        .id(topAnchor)

                    RunnerQuestionCard(
                        question: question,
                        showsUngradedNotice: !payload.gradable
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

                    if isRevealed {
                        RunnerExplanationCard(question: question, response: response)
                            // Arrives from under the options rather than fading in on top of
                            // them, so the eye follows the answer down into the reason for it.
                            .transition(
                                .move(edge: .top).combined(with: .opacity)
                            )
                    }
                }
                .padding(.horizontal, MedxSurface.gutter)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(horizontalQuestionGesture)
            .onChange(of: currentIndex) { _, _ in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                    proxy.scrollTo(topAnchor, anchor: .top)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            hud
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            runnerActionBar(question: question, isRevealed: isRevealed)
        }
        .animation(reduceMotion ? nil : MedxMotion.settle, value: isRevealed)
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
        let canGo = canAdvance(isRevealed: isRevealed)
        let showSkip = payload.mode == .exam
            && responses[question.id]?.chosenId == nil
            && !isLastQuestion

        return RunnerActionBar(
            advanceLabel: advanceLabel,
            isLastQuestion: isLastQuestion,
            canGoBack: currentIndex > activeSection.start,
            canAdvance: canGo,
            showSkip: showSkip,
            onBack: {
                goBack()
            },
            onSkip: {
                HapticManager.light()
                nextQuestion()
            },
            onAdvance: {
                HapticManager.medium()
                if isLastQuestion { submitSection() } else { nextQuestion() }
            }
        )
    }

    private var advanceLabel: String {
        guard isLastQuestion else { return "Next" }
        if isSectioned && !isFinalSection { return "Submit section" }
        return "Finish"
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
        guard loadState == .ready, !isFinished, handover == nil, !isTimerPaused else { return }
        if remainingSeconds > 0 {
            remainingSeconds -= 1
        } else {
            handleTimeout()
        }
    }

    private func goBack() {
        guard currentIndex > activeSection.start else { return }
        HapticManager.light()
        currentIndex -= 1
        resetTimerForCurrentQuestion()
        refreshStatuses()
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
    }

    private func finishSitting() {
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

            questions = loaded
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
            loadState = .ready
            refreshStatuses()

            if payload.mode == .exam {
                MedxLiveActivityController.shared.startExam(
                    name: payload.name,
                    subject: payload.subject,
                    totalQuestions: loaded.count,
                    state: examActivityState
                )
            }
        } catch {
            loadState = .unavailable("We couldn't load this sitting. Check your connection and try again.")
        }
    }

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

/// Split out of the runner so a timer tick — which fires every second — does not force
/// SwiftUI to re-evaluate the question body as well.
///
/// Deliberately just the stem and its figures. The "QUESTION 12" eyebrow that used to head it
/// was saying what the HUD says two centimetres above, and the section hue it wore is already
/// on the page behind it — so both are gone and the card is only the thing you have to read.
struct RunnerQuestionCard: View {
    let question: Question
    let showsUngradedNotice: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsUngradedNotice {
                MedxChip("No official key", tint: MedxTheme.warningOrange)
            }

            // Images embedded in the HTML render inline; `question.images` carries the
            // separately exported figures, so both paths are shown.
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
        .padding(18)
        .medxCard()
    }
}

// MARK: - Figure

/// A tappable exported figure. Bare filenames are resolved against the image CDN, the
/// same way the ones inside the HTML are.
struct RunnerFigure: View {
    let raw: String

    @State private var zoomTarget: MedxZoomTarget?

    var body: some View {
        if let url = MedxRichText.figureURL(raw) {
            Button {
                HapticManager.light()
                zoomTarget = MedxZoomTarget(url: url)
            } label: {
                CachedAsyncImage(url: url, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: MedxRadius.control, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: MedxRadius.control, style: .continuous)
                            .strokeBorder(MedxSurface.separator.opacity(0.35), lineWidth: MedxSurface.hairline)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Figure")
            .accessibilityHint("Opens the image full screen")
            .fullScreenCover(item: $zoomTarget) { target in
                MedxImageViewer(url: target.url)
            }
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(outcome.title, systemImage: outcome.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(outcome.color)

                Spacer(minLength: 0)

                if outcome != .correct, let correctLabel, !correctLabel.isEmpty {
                    MedxChip("Answer \(correctLabel)", tint: MedxTheme.successGreen)
                }
            }

            if let explanation = question.explanation, !explanation.isEmpty {
                HTMLRichTextView(html: explanation, fontSize: 15, weight: .regular, textColor: .secondary)
            } else {
                Text("No explanation provided for this question.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !reference.isEmpty {
                Label(reference, systemImage: "book.closed")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .medxCard()
        .transition(.blurReplace)
    }
}

// MARK: - Per-question status

enum RunnerQuestionStatus {
    case unanswered
    case answered
    case correct
    case wrong
    case timedOut

    func trackColor(isCurrent: Bool) -> Color {
        if isCurrent { return MedxTheme.accent }
        switch self {
        case .unanswered: return Color(uiColor: .quaternaryLabel)
        case .answered: return MedxTheme.accent.opacity(0.55)
        case .correct: return MedxTheme.successGreen.opacity(0.75)
        case .wrong: return MedxTheme.destructiveRed.opacity(0.75)
        case .timedOut: return MedxTheme.warningOrange.opacity(0.75)
        }
    }

    var chipFill: Color {
        switch self {
        case .unanswered: return MedxSurface.fieldFill
        case .answered: return MedxTheme.accent.opacity(0.16)
        case .correct: return MedxTheme.successGreen.opacity(0.16)
        case .wrong: return MedxTheme.destructiveRed.opacity(0.16)
        case .timedOut: return MedxTheme.warningOrange.opacity(0.16)
        }
    }

    var chipForeground: Color {
        switch self {
        case .unanswered: return .secondary
        case .answered: return MedxTheme.accent
        case .correct: return MedxTheme.successGreen
        case .wrong: return MedxTheme.destructiveRed
        case .timedOut: return MedxTheme.warningOrange
        }
    }

    /// The hue this state tints its glass with, or `nil` where the state *is* "nothing has
    /// happened here yet" — an untouched question should be a clear pane, not a coloured one.
    var tileHue: Color? {
        switch self {
        case .unanswered: return nil
        case .answered: return MedxTheme.accent
        case .correct: return MedxTheme.successGreen
        case .wrong: return MedxTheme.destructiveRed
        case .timedOut: return MedxTheme.warningOrange
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
        case .correct: return MedxTheme.successGreen
        case .incorrect: return MedxTheme.destructiveRed
        case .timedOut: return MedxTheme.warningOrange
        case .unanswered: return MedxTheme.warningOrange
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 10)], spacing: 10) {
                        ForEach(Array(range), id: \.self) { index in
                            tile(for: index)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Legend")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(Array(legend.enumerated()), id: \.offset) { _, status in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(status.chipFill)
                                    .overlay(Circle().strokeBorder(status.chipForeground.opacity(0.5), lineWidth: 1))
                                    .frame(width: 14, height: 14)
                                Text(status.legendLabel)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .medxPage(section)
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

    private func tile(for index: Int) -> some View {
        let status = statuses.indices.contains(index) ? statuses[index] : .unanswered
        let isCurrent = index == currentIndex
        let isLocked = lockAhead && index > furthestIndex
        let hue: Color? = isCurrent ? MedxTheme.accent : status.tileHue

        return Button {
            onSelect(index)
        } label: {
            Text("\(index + 1)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(isCurrent ? MedxTheme.accent : status.chipForeground)
                .frame(minWidth: 46, minHeight: 46)
                // Glass, because the navigator is a sheet floating over the sitting — one of the
                // three places in the app allowed it.
                .medxSurface(
                    RoundedRectangle(cornerRadius: MedxRadius.control, style: .continuous),
                    MedxSurfaceSpec(
                        material: .glass(clear: false),
                        fill: status.chipFill,
                        tint: hue,
                        strokeHue: hue,
                        strokeOpacity: isCurrent ? 0.9 : 0.45,
                        strokeWidth: isCurrent ? 1.8 : 0.5
                    )
                )
                .opacity(isLocked ? 0.35 : 1)
                .contentShape(RoundedRectangle(cornerRadius: MedxRadius.control, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
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

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    MedxPageHeader(
                        section: .tests,
                        eyebrow: "\(summary.closedLabel) submitted",
                        title: summary.nextLabel,
                        lead: "\(summary.nextCount) questions, \(summary.nextMinutes) minutes. "
                            + "The block you just submitted is closed for good, and this one's "
                            + "clock starts when you tap below.",
                        symbol: "hourglass"
                    )

                    MedxMetricsRow {
                        if summary.gradable {
                            MedxMetric(
                                icon: "checkmark.circle.fill",
                                value: "\(summary.score)/\(summary.total)",
                                label: "scored",
                                color: MedxTheme.successGreen
                            )
                        }
                        MedxMetric(
                            icon: "hand.tap.fill",
                            value: "\(summary.attempted)/\(summary.total)",
                            label: "attempted",
                            color: MedxCandy.tangerine
                        )
                        MedxMetric(
                            icon: "square.stack.3d.up.fill",
                            value: "\(summary.remainingSections)",
                            label: summary.remainingSections == 1 ? "block left" : "blocks left",
                            color: MedxCandy.sky
                        )
                    }

                    if !summary.gradable {
                        Text("This paper came through without an answer key, so nothing here is scored — only what you attempted is recorded.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, MedxSurface.gutter)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }

            Button {
                HapticManager.medium()
                onContinue()
            } label: {
                Text("Start \(summary.nextLabel)")
                    .font(.headline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .medxFilled(MedxCandy.tangerine)
            .medxFloatingBar()
        }
        // A block handover only ever happens in a Marrow grand paper, so the page wears Tests'
        // tangerine — the same wash the paper was opened under.
        .medxPage(.tests)
        // Full screen and one way out on purpose. There is nothing behind this worth looking
        // at — the block it would show is closed — and a swipe-to-dismiss would start the next
        // section's clock by accident.
        .interactiveDismissDisabled()
    }
}
