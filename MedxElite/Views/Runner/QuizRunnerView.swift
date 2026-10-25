import SwiftUI
import UIKit

// MARK: - Sitting runner

/// The sitting runner, on the platform's own chrome.
///
/// The navigation bar carries the close button, "Question 3 of 12" — the counter, said once —
/// the paper's name as its subtitle, the clock and the bookmark; a thin bar under it drains with
/// the clock; the bottom bar carries Previous, the question navigator and Next, which becomes
/// Submit on the last question of a block. The bars are Liquid Glass because iOS 26 makes them
/// so. Nothing in this file draws glass, and the plain buttons inside the bars are what keep
/// every tap landing.
///
/// Time is a wall-clock deadline, not a counter. The system draws the clock counting down to
/// it, a locked phone keeps spending it, and the Lock Screen activity carries the same date —
/// so the app and the Lock Screen can no longer disagree, and backgrounding is no longer a free
/// pause. The one-second tick only *acts* on the clock: haptics at the thresholds, the timeout,
/// and the periodic save.
public struct QuizRunnerView: View {
    public let payload: RunnerPayload
    public var onFinishedSession: () -> Void

    @State private var questions: [Question] = []
    @State private var currentIndex = 0
    @State private var furthestIndex = 0
    @State private var responses: [Int: QuestionResponse] = [:]
    @State private var revealedQuestions: [Int: Bool] = [:]
    @State private var statuses: [RunnerQuestionStatus] = []
    @State private var loadState: RunnerLoadState = .loading
    /// A load in flight, so two overlapping `.task` runs cannot both reset the sitting.
    @State private var isLoadingSitting = false
    @State private var isFinished = false
    @State private var completedSeconds = 0
    @State private var showExitAlert = false
    @State private var showNavigator = false
    @State private var showSubmitConfirm = false
    /// A saved, unfinished sitting of this same paper, offered back when it is opened again.
    @State private var resumeOffer: MedxSittingSnapshot?
    @State private var startedAt = Date()
    /// The blocks this paper is sat in. Always at least one element once loaded.
    @State private var sections: [MedxRunnerSection] = []
    @State private var sectionIndex = 0
    /// Blocks already submitted, scored at the moment their own clock was still meaningful.
    @State private var sectionLog: [MedxAttemptSection] = []
    @State private var sectionStartedAt = Date()
    /// Raised between blocks, so a submitted section is acknowledged rather than the paper
    /// silently jumping fifty questions forward.
    @State private var handover: MedxSectionHandover?

    /// When the active clock was wound and when it runs out: the block's in exam mode, the
    /// question's in revision.
    @State private var clockStart = Date()
    @State private var deadline = Date.distantFuture
    /// A revision question whose answer has been shown holds the seconds it had left.
    @State private var frozenByQuestion: [Int: Int] = [:]
    @State private var clockPhase: RunnerClockPhase = .calm
    /// One-shot guards so the halfway and final-fifth haptics each fire once per wound clock.
    @State private var firedHaptic50 = false
    @State private var firedHaptic20 = false
    @State private var ticksSinceSave = 0
    /// What the Lock Screen was last told, so a navigation tap does not push an identical update.
    @State private var lastPushedAnswered = -1
    @State private var lastPushedNumber = -1

    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var authService = AuthService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
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
                // The block handover is an overlay *inside* the runner, never a cover over it:
                // a cover fired the runner's `onDisappear`, which ended the Live Activity, so a
                // grand test had no Lock Screen clock from block two onward.
                .overlay {
                    if let handover {
                        RunnerHandoverOverlay(summary: handover) {
                            beginActiveSection()
                        }
                        .transition(.opacity)
                    }
                }
            }
        }
        .onReceive(timer) { _ in
            tick()
        }
        .task {
            await loadSittingQuestions()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                // A clock that ran out while the phone was locked is settled now, not a second later.
                tick()
            } else {
                persistSnapshot()
            }
        }
    }

    private var runnerScreen: some View {
        content
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(runnerTitle)
            .navigationSubtitle(runnerSubtitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { runnerToolbar }
            .toolbar(loadState == .ready ? .visible : .hidden, for: .bottomBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                if loadState == .ready {
                    RunnerTimeBar(
                        start: clockStart,
                        deadline: deadline,
                        frozen: currentFrozen,
                        capacity: capacitySeconds,
                        phase: clockPhase
                    )
                }
            }
            .alert("Leave sitting?", isPresented: $showExitAlert) {
                Button("Keep going", role: .cancel) {}
                Button("Save and leave") {
                    persistSnapshot()
                    endActivityAndClose()
                }
                Button("Discard", role: .destructive) {
                    clearSnapshot()
                    endActivityAndClose()
                }
            } message: {
                Text("Save and leave keeps your answers and the clock where they are, so opening this paper again picks up at question \(currentIndex + 1).")
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
                Button("Start over", role: .destructive) {
                    clearSnapshot()
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
                    clock: payload.mode == .exam ? MedxFormat.clock(remainingSeconds) : nil,
                    title: isSectioned && !isFinalSection ? "Submit \(activeSection.label)?" : "Submit the paper?",
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
                .medxTaskSheet()
            }
            .sheet(isPresented: $showNavigator) {
                QuestionNavigatorSheet(
                    range: navigatorRange,
                    currentIndex: currentIndex,
                    furthestIndex: furthestIndex,
                    statuses: statuses,
                    marked: markedInRange,
                    lockAhead: payload.mode == .revision,
                    sectionLabel: isSectioned ? activeSection.label : nil
                ) { index in
                    showNavigator = false
                    jump(to: index)
                }
                .medxTaskSheet()
            }
    }

    // MARK: - Chrome

    private var runnerTitle: String {
        guard loadState == .ready, !questions.isEmpty else { return payload.name }
        return "Question \(currentIndex + 1) of \(questions.count)"
    }

    private var runnerSubtitle: String {
        var parts = [payload.mode == .exam ? "Exam" : "Revision"]
        if isSectioned {
            parts.append("Block \(sectionIndex + 1) of \(sections.count)")
        }
        if loadState == .ready {
            parts.append(payload.name)
        }
        return parts.joined(separator: " · ")
    }

    @ToolbarContentBuilder
    private var runnerToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(role: .close) { requestClose() }
        }
        if loadState == .ready {
            ToolbarItem(placement: .topBarTrailing) {
                RunnerClock(start: clockStart, deadline: deadline, frozen: currentFrozen, phase: clockPhase)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let question = currentQuestion { toggleBookmark(question) }
                } label: {
                    Image(systemName: isCurrentBookmarked ? "bookmark.fill" : "bookmark")
                }
                .tint(isCurrentBookmarked ? MedxOutcome.flagged : nil)
                .accessibilityLabel(isCurrentBookmarked ? "Remove bookmark" : "Bookmark question")
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                    goBack()
                } label: {
                    Label("Previous", systemImage: "chevron.backward")
                }
                .disabled(!canGoBack)
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button {
                    openNavigator()
                } label: {
                    Label("Questions", systemImage: "square.grid.3x3")
                }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button {
                    advance()
                } label: {
                    Label(isLastQuestion ? "Submit" : "Next", systemImage: isLastQuestion ? "checkmark" : "chevron.forward")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.glassProminent)
                .tint(isLastQuestion ? MedxOutcome.correct : nil)
                .disabled(!canAdvanceNow)
            }
        }
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

    /// The block being sat. Falls back to the whole paper before the sections are resolved.
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

    /// One block over the whole paper is not a sectioned sitting; only a genuine split changes
    /// the chrome, the guards and the submit button.
    private var isSectioned: Bool { sections.count > 1 }

    private var isFinalSection: Bool { sectionIndex >= sections.count - 1 }

    private var questionsInSection: [Question] {
        let range = activeSection
        guard range.start < questions.count else { return [] }
        return Array(questions[range.start..<min(range.end, questions.count)])
    }

    /// Answered (an option picked, not just timed out) in the block on screen.
    private var sectionAnsweredCount: Int {
        questionsInSection.reduce(0) { $0 + (responses[$1.id]?.chosenId != nil ? 1 : 0) }
    }

    /// The first question in this block with no option picked, for the submit sheet's way back.
    private var firstUnansweredInSection: Int? {
        let range = activeSection.start..<min(activeSection.end, questions.count)
        return range.first { responses[questions[$0].id]?.chosenId == nil }
    }

    /// What the navigator may offer, clamped to the questions that exist.
    private var navigatorRange: Range<Int> {
        let lower = min(activeSection.start, questions.count)
        let upper = min(activeSection.end, questions.count)
        return lower < upper ? lower..<upper : 0..<0
    }

    private var markedInRange: Set<Int> {
        Set(navigatorRange.filter { $0 < questions.count && isBookmarked(questions[$0]) })
    }

    /// The last question *of this block*, where Next becomes Submit.
    private var isLastQuestion: Bool {
        currentIndex >= activeSection.end - 1
    }

    private var canGoBack: Bool {
        currentIndex > activeSection.start
    }

    private var isCurrentRevealed: Bool {
        guard let question = currentQuestion else { return false }
        return payload.mode == .revision && revealedQuestions[question.id] == true
    }

    /// Exam mode never blocks navigation; revision requires the answer to be revealed first.
    private var canAdvanceNow: Bool {
        payload.mode == .exam || isCurrentRevealed
    }

    /// Exam clocks always run; a revision clock runs while its question is still open.
    private var isClockRunning: Bool {
        guard payload.mode == .revision else { return true }
        guard let question = currentQuestion else { return false }
        return responses[question.id] == nil
    }

    /// The seconds a revision answer was shown with, for the held clock.
    private var currentFrozen: Int? {
        guard payload.mode == .revision, let question = currentQuestion, responses[question.id] != nil else { return nil }
        return frozenByQuestion[question.id] ?? 0
    }

    /// What the clock was wound to: the block's duration in exam mode, sixty seconds a question
    /// in revision.
    private var capacitySeconds: Int {
        payload.mode == .exam ? max(activeSection.seconds, 1) : 60
    }

    private var remainingSeconds: Int {
        guard deadline != .distantFuture else { return capacitySeconds }
        return max(Int(deadline.timeIntervalSinceNow.rounded(.up)), 0)
    }

    private var isCurrentBookmarked: Bool {
        guard let question = currentQuestion else { return false }
        return isBookmarked(question)
    }

    private func isBookmarked(_ question: Question) -> Bool {
        activityStore.isBookmarked(questionId: question.id, sourceId: payload.id, uid: uid)
    }

    /// Demo screenshot runs never write a sitting: one screen's answers would otherwise be
    /// offered back on the next screen's launch.
    private var persistsSittings: Bool {
        #if DEBUG
        return !MedxDemoMode.isOn
        #else
        return true
        #endif
    }

    // MARK: - Saved sitting

    private func persistSnapshot() {
        guard persistsSittings, let uid, loadState == .ready, !isFinished, !questions.isEmpty else { return }
        guard !responses.isEmpty || currentIndex > 0 || sectionIndex > 0 else { return }

        let remaining: Int
        if handover != nil {
            // Saved on the handover: the next block has not started, so it opens with its full clock.
            remaining = activeSection.seconds
        } else if let currentFrozen, payload.mode == .revision {
            remaining = currentFrozen
        } else {
            remaining = remainingSeconds
        }

        MedxSittingSnapshot(
            fingerprint: MedxSittingSnapshot.fingerprint(questions),
            order: questions.map(\.id),
            mode: payload.mode.rawValue,
            currentIndex: currentIndex,
            furthestIndex: furthestIndex,
            responses: Array(responses.values),
            revealed: revealedQuestions.compactMap { $0.value ? $0.key : nil },
            remainingSeconds: remaining,
            sectionIndex: sectionIndex,
            sectionLog: sectionLog,
            awaitingHandover: handover != nil,
            elapsedSeconds: Int(Date().timeIntervalSince(startedAt)),
            savedAt: Date()
        )
        .save(uid: uid, kind: payload.kind, id: payload.id)
    }

    private func clearSnapshot() {
        guard let uid else { return }
        MedxSittingSnapshot.clear(uid: uid, kind: payload.kind, id: payload.id)
    }

    private func applySnapshot(_ snapshot: MedxSittingSnapshot) {
        // A shuffled paper resumes in the order it was sat, so the indices below line up.
        if !snapshot.order.isEmpty, Set(snapshot.order) == Set(questions.map(\.id)) {
            let byId = Dictionary(questions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            questions = snapshot.order.compactMap { byId[$0] }
        }

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
        if payload.mode == .revision {
            for response in restored.values { frozenByQuestion[response.questionId] = 0 }
        }
        sectionIndex = min(max(snapshot.sectionIndex, 0), max(sections.count - 1, 0))
        sectionLog = snapshot.sectionLog
        let range = activeSection.start..<max(activeSection.end, activeSection.start + 1)
        currentIndex = min(max(snapshot.currentIndex, range.lowerBound), range.upperBound - 1)
        furthestIndex = max(snapshot.furthestIndex, currentIndex)
        startedAt = Date().addingTimeInterval(-Double(max(snapshot.elapsedSeconds, 0)))
        refreshStatuses()
        HapticManager.success()

        if snapshot.awaitingHandover, isSectioned, sectionIndex > 0 {
            // Saved on the handover screen: the next block starts when it is tapped, not now.
            let closed = sections[sectionIndex - 1]
            let row = sectionLog.first { $0.index == sectionIndex - 1 }
            deadline = .distantFuture
            handover = MedxSectionHandover(
                closedLabel: closed.label,
                score: row?.score ?? 0,
                attempted: row?.attempted ?? 0,
                total: closed.count,
                gradable: payload.gradable,
                nextLabel: activeSection.label,
                nextCount: activeSection.count,
                nextMinutes: activeSection.minutes,
                remainingSections: sections.count - sectionIndex
            )
        } else {
            windClock(seconds: max(snapshot.remainingSeconds, 1))
            let spent = payload.mode == .exam ? max(activeSection.seconds - snapshot.remainingSeconds, 0) : 0
            sectionStartedAt = Date().addingTimeInterval(-Double(spent))
        }
    }

    // MARK: - Status and Live Activity

    private func status(for question: Question) -> RunnerQuestionStatus {
        guard let response = responses[question.id] else { return .unanswered }
        if response.timedOut == true { return .timedOut }
        guard response.chosenId != nil else { return .unanswered }
        if revealedQuestions[question.id] == true {
            return response.correct ? .correct : .wrong
        }
        return .answered
    }

    /// Recomputed on change instead of inside `body`: the navigator reads it, and it walks
    /// every question in the sitting.
    private func refreshStatuses() {
        statuses = questions.map { status(for: $0) }
        refreshLiveActivity()
    }

    /// Exam mode mirrors the sitting onto the Lock Screen. The clock is handed over as the same
    /// deadline the runner uses, so the system ticks it; only the counts and the question number
    /// are pushed, and only when they change.
    private func refreshLiveActivity() {
        guard payload.mode == .exam, loadState == .ready, !isFinished else { return }
        let answered = sectionAnsweredCount
        let number = currentIndex + 1
        guard answered != lastPushedAnswered || number != lastPushedNumber else { return }
        lastPushedAnswered = answered
        lastPushedNumber = number
        MedxLiveActivityController.shared.updateExam(state: examActivityState)
    }

    /// One place builds the activity's state, so the start, every update and the end cannot
    /// disagree about what the numbers mean. Counts are the *block's*, like its total.
    private var examActivityState: MedxExamActivityAttributes.ContentState {
        let scored = questionsInSection.compactMap { responses[$0.id] }.filter { $0.chosenId != nil }
        return MedxExamActivityAttributes.ContentState(
            answered: sectionAnsweredCount,
            correct: payload.gradable ? scored.filter(\.correct).count : 0,
            wrong: payload.gradable ? scored.filter { !$0.correct }.count : 0,
            currentNumber: currentIndex + 1,
            endDate: deadline == .distantFuture ? Date() : deadline,
            sectionLabel: isSectioned ? activeSection.label : nil,
            sectionIndex: sectionIndex,
            sectionCount: sections.count,
            sectionTotal: activeSection.count,
            revealsAnswers: payload.mode == .revision
        )
    }

    // MARK: - Layout

    private func activeRunner(question: Question) -> some View {
        // iPad in landscape gets three panes: the navigator as a sidebar, the question as a
        // readable column, and in revision the explanation beside it.
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
                sidebarNavigator
                    .frame(width: 300)
                    .padding(.leading, MedxSpace.l)
                    .padding(.vertical, MedxSpace.m)
            }

            questionColumn(
                question: question,
                response: response,
                isRevealed: isRevealed,
                isLocked: isLocked,
                inlineExplanation: !explanationBeside
            )

            if explanationBeside {
                ScrollView {
                    if isRevealed {
                        RunnerExplanationCard(question: question, response: response)
                    } else {
                        Text("The explanation appears here once you answer.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(MedxSpace.l)
                    }
                }
                .frame(width: 360)
                .padding(.trailing, MedxSpace.l)
                .padding(.vertical, MedxSpace.m)
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: isRevealed)
    }

    /// iPad landscape: the whole block as tiles beside the question, with Submit under them.
    private var sidebarNavigator: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MedxSpace.l) {
                if isSectioned {
                    Text(activeSection.label)
                        .font(.headline)
                }

                RunnerNavigatorGrid(
                    range: navigatorRange,
                    currentIndex: currentIndex,
                    furthestIndex: furthestIndex,
                    statuses: statuses,
                    marked: markedInRange,
                    lockAhead: payload.mode == .revision
                ) { index in
                    jump(to: index)
                }

                RunnerNavigatorLegend(lockAhead: payload.mode == .revision)

                Button {
                    HapticManager.medium()
                    showSubmitConfirm = true
                } label: {
                    Text(isSectioned && !isFinalSection ? "Submit block" : "Submit")
                        .frame(maxWidth: .infinity)
                }
                .medxPrimary()
            }
            .padding(MedxSpace.l)
        }
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: MedxRadius.card, style: .continuous)
        )
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
                VStack(alignment: .leading, spacing: MedxSpace.l) {
                    Color.clear
                        .frame(height: 1)
                        .id(topAnchor)

                    RunnerQuestionCard(
                        question: question,
                        showsUngradedNotice: !payload.gradable,
                        sourceTag: payload.questionTags.flatMap { tags in
                            tags.indices.contains(currentIndex) ? tags[currentIndex] : nil
                        }
                    )
                    // Double-tap the stem to bookmark, the way Photos favourites a picture. The
                    // toolbar button stays the discoverable route; VoiceOver gets the same thing
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
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, MedxSpace.l)
                .padding(.top, MedxSpace.s)
                .padding(.bottom, MedxSpace.xl)
                // iPad: a readable column rather than lines the width of a landscape screen.
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
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

    /// Just the options. Four lettered rows under a stem do not need to be introduced.
    private func answerSection(
        question: Question,
        response: QuestionResponse?,
        isRevealed: Bool,
        isLocked: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: MedxSpace.s) {
            // Keyed on position, not on `option.id`: a backend that hands out duplicate option ids
            // would otherwise make `ForEach` draw one row several times.
            ForEach(Array(question.options.enumerated()), id: \.offset) { pair in
                QuestionOptionButton(
                    option: pair.element,
                    index: pair.offset,
                    isChosen: response?.chosenId == pair.element.id,
                    isCorrect: question.isCorrect(optionId: pair.element.id),
                    isRevealed: isRevealed,
                    isLocked: isLocked
                ) {
                    handlePickOption(question: question, chosenId: pair.element.id)
                }
            }
        }
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
                    guard canAdvanceNow, !isLastQuestion else {
                        HapticManager.warning()
                        return
                    }
                    nextQuestion()
                } else if canGoBack {
                    goBack()
                }
            }
    }

    // MARK: - Loading & unavailable

    private var loadingState: some View {
        VStack(spacing: MedxSpace.m) {
            ProgressView()
                .controlSize(.large)
            Text("Preparing your sitting")
                .font(.headline)
            Text(payload.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, MedxSpace.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unavailableState(message: String) -> some View {
        MedxEmptyState(
            "Sitting unavailable",
            symbol: "exclamationmark.triangle",
            message: message,
            actionTitle: "Try again"
        ) {
            HapticManager.light()
            loadState = .loading
            Task { await loadSittingQuestions() }
        }
    }

    // MARK: - Actions

    private func requestClose() {
        HapticManager.light()
        if loadState == .ready, !responses.isEmpty {
            showExitAlert = true
        } else {
            endActivityAndClose()
        }
    }

    private func endActivityAndClose() {
        MedxLiveActivityController.shared.endExam(state: examActivityState)
        dismiss()
    }

    private func openNavigator() {
        guard loadState == .ready else { return }
        HapticManager.light()
        showNavigator = true
    }

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

        let isCorrect = question.isCorrect(optionId: chosenId)
        if payload.mode == .revision {
            frozenByQuestion[question.id] = remainingSeconds
        }
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
            // A spent block closes that block, not the paper. Only the last one ends the sitting.
            submitSection()
        } else if let question = currentQuestion, responses[question.id] == nil {
            frozenByQuestion[question.id] = 0
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

    /// Once a second: a save every fifteen, and whatever the clock has crossed since the last
    /// look — the system draws the countdown itself.
    private func tick() {
        guard loadState == .ready, !isFinished, handover == nil, resumeOffer == nil else { return }
        ticksSinceSave += 1
        if ticksSinceSave >= 15 {
            ticksSinceSave = 0
            persistSnapshot()
        }
        guard isClockRunning else { return }
        let remaining = remainingSeconds
        let phase = RunnerClockPhase.of(remaining: remaining, capacity: capacitySeconds)
        if phase != clockPhase { clockPhase = phase }
        fireTimeHaptics(remaining: remaining)
        if remaining <= 0 { handleTimeout() }
    }

    /// A light tap as the clock passes the halfway mark, and again entering the final fifth.
    private func fireTimeHaptics(remaining: Int) {
        let capacity = capacitySeconds
        guard capacity > 0 else { return }
        let fraction = Double(remaining) / Double(capacity)
        if !firedHaptic50, fraction <= 0.5 {
            firedHaptic50 = true
            HapticManager.light()
        }
        if !firedHaptic20, fraction <= 0.2 {
            firedHaptic20 = true
            HapticManager.light()
        }
    }

    /// Winds the active clock to `seconds` from now and re-arms the threshold haptics.
    private func windClock(seconds: Int) {
        clockStart = Date()
        deadline = Date().addingTimeInterval(TimeInterval(max(seconds, 0)))
        clockPhase = RunnerClockPhase.of(remaining: seconds, capacity: capacitySeconds)
        firedHaptic50 = false
        firedHaptic20 = false
    }

    private func goBack() {
        guard canGoBack else { return }
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
        // to jump into a submitted one; revision never jumps past the furthest question seen.
        guard questions.indices.contains(index),
              index >= activeSection.start,
              index < activeSection.end,
              index != currentIndex
        else { return }
        if payload.mode == .revision, index > furthestIndex {
            HapticManager.warning()
            return
        }
        HapticManager.light()
        currentIndex = index
        furthestIndex = max(furthestIndex, index)
        resetTimerForCurrentQuestion()
        refreshStatuses()
    }

    /// Revision runs a 60 s clock per question; wound only when the question is still open.
    private func resetTimerForCurrentQuestion() {
        guard payload.mode == .revision else { return }
        if let question = currentQuestion, responses[question.id] != nil { return }
        windClock(seconds: 60)
    }

    private func finishSitting() {
        clearSnapshot()
        // The block that was still open when the paper ended is scored too, so a paper
        // submitted early does not lose the section it was in.
        logSection()
        completedSeconds = Int(Date().timeIntervalSince(startedAt))
        isFinished = true
        HapticManager.success()
        MedxLiveActivityController.shared.endExam(state: examActivityState)
        saveSittingAttempt()
    }

    /// Close the block being sat, or open the next one. A sectioned paper is scored per block
    /// *as it is submitted*, because that is the only moment the block's own clock is still
    /// meaningful; there is no way back into a submitted block.
    private func submitSection() {
        guard isSectioned, !isFinished else {
            finishSitting()
            return
        }
        logSection()

        guard !isFinalSection else {
            finishSitting()
            return
        }

        let closed = activeSection
        let closedRow = sectionLog.last
        sectionIndex += 1
        currentIndex = activeSection.start
        furthestIndex = max(furthestIndex, currentIndex)
        deadline = .distantFuture
        refreshStatuses()
        HapticManager.success()

        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
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
        persistSnapshot()
    }

    /// Starts the block's clock, which is deliberately *not* running while the handover is on
    /// screen: a summary you are still reading must not be spending the next block's minutes.
    private func beginActiveSection() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
            handover = nil
        }
        sectionStartedAt = Date()
        windClock(seconds: activeSection.seconds)
        lastPushedAnswered = -1
        refreshStatuses()
    }

    /// One row per submitted block, in the exact shape the PWA writes. Guarded on the index so
    /// submitting twice cannot double-count.
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
            id: MedxAttemptOutbox.newId(),
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
            finishedAt: MedxDates.stamp(),
            responses: Array(responses.values),
            sections: sectionLog.isEmpty ? nil : sectionLog.sorted { $0.index < $1.index }
        )

        // Written to the outbox first, counted at once, uploaded when it can be.
        MedxAttemptOutbox.shared.enqueue(attempt)
    }

    // MARK: - Loading

    private func loadSittingQuestions() async {
        // Once a paper is on screen it is never loaded again under the student: `.task` runs
        // again whenever the runner re-appears, and every run used to reset the sitting to
        // question 1. Only "Try again" after a failure reloads.
        guard loadState != .ready || questions.isEmpty else { return }
        guard !isLoadingSitting else { return }
        isLoadingSitting = true
        defer { isLoadingSitting = false }
        do {
            let loaded: [Question]

            // A custom module or a "practise these" sitting arrives with its questions already
            // gathered from several source modules, so there is nothing to fetch.
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
            frozenByQuestion = [:]
            sectionIndex = 0
            sectionLog = []

            // Sections only apply to a timed paper: a grand paper in revision mode is sixty
            // seconds a question with the answer revealed as you go.
            let requested = payload.mode == .exam ? (payload.sections ?? []) : []
            let resolved = MedxRunnerSection.clamped(requested, to: loaded.count)
            sections = resolved.count > 1 ? resolved : [wholePaperSection(count: loaded.count)]

            startedAt = Date()
            sectionStartedAt = Date()
            windClock(seconds: payload.mode == .exam ? sections[0].seconds : 60)
            loadState = .ready
            refreshStatuses()

            // An unfinished sitting of this exact paper (same questions, same mode, same person)
            // is offered back. A different upload under the same id fails the fingerprint.
            if persistsSittings, let uid {
                MedxSittingSnapshot.pruneStale(uid: uid)
                if let saved = MedxSittingSnapshot.load(uid: uid, kind: payload.kind, id: payload.id) {
                    if saved.fingerprint == MedxSittingSnapshot.fingerprint(questions),
                       saved.mode == payload.mode.rawValue {
                        resumeOffer = saved
                    } else {
                        clearSnapshot()
                    }
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

    /// The single block an unsectioned paper is sat in: the paper's own official duration where
    /// it has one, and one minute a question otherwise.
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

    #if DEBUG
    /// Screenshot runs only. Each `-medxScreen` value stages one runner state.
    private func debugAutopilot() async {
        guard MedxDemoMode.isOn,
              let screen = UserDefaults.standard.string(forKey: "medxScreen")
        else { return }
        try? await Task.sleep(nanoseconds: 900_000_000)

        switch screen {
        case "runner-custom-next":
            if let first = questions.first, let pick = first.correctIds.first ?? first.options.first?.id {
                handlePickOption(question: first, chosenId: pick)
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
            advance()
            print("[CustomNext] after Next: question \(currentIndex + 1) of \(questions.count)")
        case "runner-zoom":
            // The figure viewer over the runner. The demo questions carry no figures, so the run
            // draws one: a cluster of cocci.
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
                  let wrong = question.options.first(where: { !question.isCorrect(optionId: $0.id) })
            else { return }
            handlePickOption(question: question, chosenId: wrong.id)
        case "runner-batch":
            if let first = questions.first, let pick = first.correctIds.first ?? first.options.first?.id {
                handlePickOption(question: first, chosenId: pick)
            }
            if questions.count > 1 { jump(to: 1) }
        case "runner-navigator":
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
            for question in questions.prefix(3) {
                guard let pick = question.options.dropFirst().first?.id ?? question.options.first?.id else { continue }
                handlePickOption(question: question, chosenId: pick)
            }
            if questions.count > 2 { jump(to: 2) }
            if let question = currentQuestion { toggleBookmark(question) }
        case "runner-lowtime":
            for question in questions.prefix(4) {
                guard let pick = question.correctIds.first ?? question.options.first?.id else { continue }
                handlePickOption(question: question, chosenId: pick)
            }
            if questions.count > 4 { jump(to: 4) }
            windClock(seconds: max(capacitySeconds / 7, 30))
            clockPhase = .low
        case "runner-submit":
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
            let picks = questions.prefix(5).compactMap { question -> QuestionResponse? in
                guard let pick = question.correctIds.first ?? question.options.first?.id else { return nil }
                return QuestionResponse(questionId: question.id, chosenId: pick, correct: question.isCorrect(optionId: pick))
            }
            resumeOffer = MedxSittingSnapshot(
                fingerprint: MedxSittingSnapshot.fingerprint(questions),
                order: questions.map(\.id),
                mode: payload.mode.rawValue,
                currentIndex: min(5, questions.count - 1),
                furthestIndex: min(5, questions.count - 1),
                responses: picks,
                revealed: [],
                remainingSeconds: max(capacitySeconds * 3 / 5, 60),
                sectionIndex: 0,
                sectionLog: [],
                awaitingHandover: false,
                elapsedSeconds: capacitySeconds * 2 / 5,
                savedAt: Date()
            )
        case "review", "review-question", "review-custom":
            for (index, question) in questions.enumerated() {
                let wrong = question.options.first(where: { !question.isCorrect(optionId: $0.id) })?.id
                let pick: Int? = index % 3 == 2 ? wrong : question.correctIds.first
                guard let pick else { continue }
                responses[question.id] = QuestionResponse(
                    questionId: question.id,
                    chosenId: pick,
                    correct: question.isCorrect(optionId: pick)
                )
            }
            refreshStatuses()
            finishSitting()
        default:
            break
        }
    }
    #endif
}

// MARK: - Load state

enum RunnerLoadState: Equatable {
    case loading
    case ready
    case unavailable(String)
}

// MARK: - The question

/// The stem, directly on the page and full width: a Marrow stem with a figure in it needs every
/// point. Split out of the runner so a clock change does not re-evaluate the question body.
struct RunnerQuestionCard: View {
    let question: Question
    let showsUngradedNotice: Bool
    /// Where a question in a mixed paper came from ("FMGE June 2023").
    var sourceTag: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: MedxSpace.m) {
            if showsUngradedNotice || (sourceTag?.isEmpty == false) {
                HStack(spacing: MedxSpace.s) {
                    if let sourceTag, !sourceTag.isEmpty {
                        MedxSourceTag(sourceTag)
                    }
                    if showsUngradedNotice {
                        Label("No answer key", systemImage: "exclamationmark.circle")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(MedxOutcome.flagged)
                    }
                    Spacer(minLength: 0)
                }
            }

            // Images embedded in the HTML render inline; `question.images` carries the separately
            // exported figures, so both paths are shown.
            HTMLRichTextView(html: question.displayText, fontSize: 18, weight: .semibold)

            if let images = question.images, !images.isEmpty {
                VStack(spacing: MedxSpace.s) {
                    ForEach(images, id: \.self) { raw in
                        RunnerFigure(raw: raw)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, MedxSpace.s)
    }
}
