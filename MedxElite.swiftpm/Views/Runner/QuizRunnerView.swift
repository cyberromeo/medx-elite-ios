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
                    elapsedSeconds: completedSeconds
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
    }

    private var runnerScreen: some View {
        content
            .background(MedxSurface.groupedBackground.ignoresSafeArea())
            .navigationTitle(payload.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .alert("Leave sitting?", isPresented: $showExitAlert) {
                Button("Keep Going", role: .cancel) {}
                Button("Leave", role: .destructive) { dismiss() }
            } message: {
                Text("Your progress in this sitting will not be saved.")
            }
            .sheet(isPresented: $showNavigator) {
                QuestionNavigatorSheet(
                    questionCount: questions.count,
                    currentIndex: currentIndex,
                    furthestIndex: furthestIndex,
                    statuses: statuses,
                    lockAhead: payload.mode == .revision
                ) { index in
                    showNavigator = false
                    jump(to: index)
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

    private var currentQuestion: Question? {
        questions.indices.contains(currentIndex) ? questions[currentIndex] : nil
    }

    private var uid: String? { authService.currentSession?.uid }

    private var answeredCount: Int {
        responses.values.reduce(into: 0) { total, response in
            if response.chosenId != nil { total += 1 }
        }
    }

    private var subtitleLine: String {
        var parts: [String] = [payload.mode == .exam ? "Exam" : "Revision"]
        if !payload.subject.isEmpty { parts.append(payload.subject) }
        if !payload.gradable { parts.append("Ungraded") }
        return parts.joined(separator: " · ")
    }

    /// In revision mode the per-question clock stops once the answer is revealed.
    private var isTimerPaused: Bool {
        guard payload.mode == .revision, let question = currentQuestion else { return false }
        return responses[question.id] != nil
    }

    private var isLastQuestion: Bool {
        currentIndex >= questions.count - 1
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
    }

    private func isBookmarked(_ question: Question) -> Bool {
        activityStore.isBookmarked(questionId: question.id, sourceId: payload.id, uid: uid)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                HapticManager.light()
                if loadState == .ready, !responses.isEmpty {
                    showExitAlert = true
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
            }
            .accessibilityLabel("Close sitting")
        }

        ToolbarItem(placement: .principal) {
            Button {
                guard loadState == .ready else { return }
                HapticManager.light()
                showNavigator = true
            } label: {
                VStack(spacing: 0) {
                    Text(loadState == .ready ? "Question \(currentIndex + 1) of \(questions.count)" : payload.name)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                    Text(subtitleLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Question \(currentIndex + 1) of \(questions.count)")
            .accessibilityValue("\(answeredCount) answered")
            .accessibilityHint("Opens the question navigator")
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            if loadState == .ready {
                timerPill

                if let question = currentQuestion {
                    Button {
                        toggleBookmark(question)
                    } label: {
                        Image(systemName: isBookmarked(question) ? "bookmark.fill" : "bookmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isBookmarked(question) ? MedxTheme.warningOrange : Color.accentColor)
                    }
                    .accessibilityLabel(isBookmarked(question) ? "Remove bookmark" : "Bookmark question")
                }
            }
        }
    }

    private var timerPill: some View {
        let paused = isTimerPaused
        let isLow = !paused && remainingSeconds <= 10
        let tint: Color = paused
            ? MedxTheme.successGreen
            : (isLow ? MedxTheme.destructiveRed : Color.secondary)

        return HStack(spacing: 4) {
            Image(systemName: paused ? "checkmark.circle.fill" : "timer")
                .font(.caption.weight(.bold))
            Text(paused ? "Done" : formatTime(remainingSeconds))
                .font(.footnote.weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            isLow ? MedxTheme.destructiveRed.opacity(0.14) : MedxSurface.fieldFill,
            in: Capsule()
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            paused ? "Answer revealed, timer paused" : "Time remaining \(formatTime(remainingSeconds))"
        )
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
                        number: currentIndex + 1,
                        showsUngradedNotice: !payload.gradable
                    )

                    answerSection(
                        question: question,
                        response: response,
                        isRevealed: isRevealed,
                        isLocked: isLocked
                    )

                    if isRevealed {
                        RunnerExplanationCard(question: question, response: response)
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
            progressTrack
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionBar(question: question, isRevealed: isRevealed)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isRevealed)
    }

    // MARK: - Progress track

    /// A single hairline strip under the navigation bar. Per-question segments are only
    /// drawn while they are still individually legible.
    private var progressTrack: some View {
        Group {
            if statuses.count > 1, statuses.count <= 30 {
                HStack(spacing: 2) {
                    ForEach(Array(statuses.enumerated()), id: \.offset) { index, status in
                        Capsule()
                            .fill(status.trackColor(isCurrent: index == currentIndex))
                            .frame(height: index == currentIndex ? 5 : 3)
                    }
                }
                .frame(height: 5)
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(uiColor: .quaternaryLabel))
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: max(6, geo.size.width * progressFraction))
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, MedxSurface.gutter)
        .padding(.bottom, 8)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: currentIndex)
        .accessibilityHidden(true)
    }

    private var progressFraction: Double {
        guard !questions.isEmpty else { return 0 }
        return Double(currentIndex + 1) / Double(questions.count)
    }

    // MARK: - Answers

    private func answerSection(
        question: Question,
        response: QuestionResponse?,
        isRevealed: Bool,
        isLocked: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(answerHint(response: response, isRevealed: isRevealed))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ForEach(question.options) { option in
                QuestionOptionButton(
                    option: option,
                    isChosen: response?.chosenId == option.id,
                    isCorrect: option.correct == true || question.correctIds.contains(option.id),
                    isRevealed: isRevealed,
                    isLocked: isLocked
                ) {
                    handlePickOption(question: question, chosenId: option.id)
                }
            }
        }
    }

    private func answerHint(response: QuestionResponse?, isRevealed: Bool) -> String {
        if isRevealed { return "The correct answer is marked below." }
        if response?.chosenId != nil { return "Tap another option to change your answer." }
        return "Choose the best answer."
    }

    // MARK: - Bottom action bar

    private func actionBar(question: Question, isRevealed: Bool) -> some View {
        let canGo = canAdvance(isRevealed: isRevealed)
        let showSkip = payload.mode == .exam
            && responses[question.id]?.chosenId == nil
            && !isLastQuestion

        return VStack(spacing: 6) {
            if !canGo {
                Text("Answer to reveal the explanation")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .disabled(currentIndex == 0)
                .accessibilityLabel("Previous question")

                if showSkip {
                    Button {
                        HapticManager.light()
                        nextQuestion()
                    } label: {
                        Text("Skip")
                            .font(.subheadline.weight(.semibold))
                            .frame(minWidth: 60, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }

                Button {
                    HapticManager.medium()
                    if isLastQuestion { finishSitting() } else { nextQuestion() }
                } label: {
                    HStack(spacing: 6) {
                        Text(isLastQuestion ? "Finish" : "Next")
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: isLastQuestion ? "checkmark" : "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(!canGo)
            }
        }
        .padding(.horizontal, MedxSurface.gutter)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .medxBar(topDivider: true)
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
            Label("Sitting Unavailable", systemImage: "exclamationmark.triangle")
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
                .buttonStyle(.borderedProminent)
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
            finishSitting()
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
        guard loadState == .ready, !isFinished, !isTimerPaused else { return }
        if remainingSeconds > 0 {
            remainingSeconds -= 1
        } else {
            handleTimeout()
        }
    }

    private func goBack() {
        guard currentIndex > 0 else { return }
        HapticManager.light()
        currentIndex -= 1
        resetTimerForCurrentQuestion()
        refreshStatuses()
    }

    private func nextQuestion() {
        guard currentIndex + 1 < questions.count else { return }
        currentIndex += 1
        furthestIndex = max(furthestIndex, currentIndex)
        resetTimerForCurrentQuestion()
        refreshStatuses()
    }

    private func jump(to index: Int) {
        guard questions.indices.contains(index), index != currentIndex else { return }
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
        completedSeconds = Int(Date().timeIntervalSince(startedAt))
        isFinished = true
        HapticManager.success()
        saveSittingAttempt()
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
            responses: Array(responses.values)
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
            let token = try await AuthService.shared.getValidIdToken()
            let loaded: [Question]
            if payload.kind == "qbank" {
                let module = try await FirestoreService.shared.fetchQBankModule(moduleId: payload.id, idToken: token)
                loaded = module.questions ?? []
            } else {
                loaded = try await FirestoreService.shared.fetchTestQuestions(testId: payload.id, idToken: token)
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
            remainingSeconds = payload.mode == .exam ? max(loaded.count * 60, 60) : 60
            startedAt = Date()
            loadState = .ready
            refreshStatuses()
        } catch {
            loadState = .unavailable("We couldn't load this sitting. Check your connection and try again.")
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let clamped = max(seconds, 0)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
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
struct RunnerQuestionCard: View {
    let question: Question
    let number: Int
    let showsUngradedNotice: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("QUESTION \(number)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .tracking(0.6)

                Spacer(minLength: 0)

                if showsUngradedNotice {
                    MedxChip("No official key", tint: MedxTheme.warningOrange)
                }
            }

            // Images embedded in the HTML render inline; `question.images` carries the
            // separately exported figures, so both paths are shown.
            HTMLRichTextView(html: question.displayText, fontSize: 17, weight: .semibold)

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
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
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
        .transition(.opacity)
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
        if isCurrent { return Color.accentColor }
        switch self {
        case .unanswered: return Color(uiColor: .quaternaryLabel)
        case .answered: return Color.accentColor.opacity(0.55)
        case .correct: return MedxTheme.successGreen.opacity(0.75)
        case .wrong: return MedxTheme.destructiveRed.opacity(0.75)
        case .timedOut: return MedxTheme.warningOrange.opacity(0.75)
        }
    }

    var chipFill: Color {
        switch self {
        case .unanswered: return MedxSurface.fieldFill
        case .answered: return Color.accentColor.opacity(0.16)
        case .correct: return MedxTheme.successGreen.opacity(0.16)
        case .wrong: return MedxTheme.destructiveRed.opacity(0.16)
        case .timedOut: return MedxTheme.warningOrange.opacity(0.16)
        }
    }

    var chipForeground: Color {
        switch self {
        case .unanswered: return .secondary
        case .answered: return Color.accentColor
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
    let questionCount: Int
    let currentIndex: Int
    let furthestIndex: Int
    let statuses: [RunnerQuestionStatus]
    /// Revision reveals answers as you go, so jumping past the frontier is not allowed.
    let lockAhead: Bool
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
                        ForEach(0..<questionCount, id: \.self) { index in
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
            .background(MedxSurface.groupedBackground.ignoresSafeArea())
            .navigationTitle("Questions")
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

        return Button {
            onSelect(index)
        } label: {
            Text("\(index + 1)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(isCurrent ? Color.accentColor : status.chipForeground)
                .frame(minWidth: 46, minHeight: 46)
                .background(status.chipFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isCurrent ? Color.accentColor : Color.clear, lineWidth: 2)
                )
                .opacity(isLocked ? 0.35 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .accessibilityLabel("Question \(index + 1)")
        .accessibilityValue(isCurrent ? "Current, \(status.legendLabel)" : status.legendLabel)
    }
}
