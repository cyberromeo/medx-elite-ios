import SwiftUI

// MARK: - Sitting Runner

public struct QuizRunnerView: View {
    public let payload: RunnerPayload
    public var onFinishedSession: () -> Void

    @State private var questions: [Question] = []
    @State private var currentIndex = 0
    @State private var furthestIndex = 0
    @State private var responses: [Int: QuestionResponse] = [:]
    @State private var revealedQuestions: [Int: Bool] = [:]
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

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let topAnchor = "runner.top"

    public init(payload: RunnerPayload, onFinishedSession: @escaping () -> Void) {
        self.payload = payload
        self.onFinishedSession = onFinishedSession
    }

    public var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            switch loadState {
            case .loading:
                loadingState
            case .unavailable(let message):
                unavailableState(message: message)
            case .ready:
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
                } else if let question = currentQuestion {
                    activeRunner(question: question)
                }
            }
        }
        .alert("Leave sitting?", isPresented: $showExitAlert) {
            Button("Keep Going", role: .cancel) {}
            Button("Leave", role: .destructive) { dismiss() }
        } message: {
            Text("Your progress in this sitting will not be saved.")
        }
        .sheet(isPresented: $showNavigator) {
            navigatorSheet
        }
        .onReceive(timer) { _ in
            tick()
        }
        .task {
            await loadSittingQuestions()
        }
    }

    // MARK: - Derived state

    /// One accent for both modes. Revision used to run on purple, which tinted the whole
    /// glass chrome pink — the mode is already spelled out in `subtitleLine`.
    private var accent: Color {
        MedxTheme.primaryBlue
    }

    private var currentQuestion: Question? {
        guard questions.indices.contains(currentIndex) else { return nil }
        return questions[currentIndex]
    }

    private var uid: String? {
        authService.currentSession?.uid
    }

    private var answeredCount: Int {
        responses.values.filter { $0.chosenId != nil }.count
    }

    private var subtitleLine: String {
        var parts: [String] = [payload.mode == .exam ? "Exam" : "Revision"]
        if !payload.subject.isEmpty { parts.append(payload.subject) }
        if !payload.gradable { parts.append("Ungraded") }
        return parts.joined(separator: " · ")
    }

    private var questionStatuses: [RunnerQuestionStatus] {
        questions.map { status(for: $0) }
    }

    /// In revision mode the per-question clock stops once the answer is revealed.
    private var isTimerPaused: Bool {
        guard payload.mode == .revision, let question = currentQuestion else { return false }
        return responses[question.id] != nil
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

    private func isBookmarked(_ question: Question) -> Bool {
        activityStore.isBookmarked(questionId: question.id, sourceId: payload.id, uid: uid)
    }

    // MARK: - Active runner

    private func activeRunner(question: Question) -> some View {
        let response = responses[question.id]
        let isRevealed = payload.mode == .revision && revealedQuestions[question.id] == true
        let isLocked = payload.mode == .revision && response != nil

        return VStack(spacing: 0) {
            header(question: question)
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Color.clear
                            .frame(height: 1)
                            .id(topAnchor)

                        questionCard(question: question)

                        answerSection(
                            question: question,
                            response: response,
                            isRevealed: isRevealed,
                            isLocked: isLocked
                        )

                        if isRevealed {
                            explanationCard(question: question, response: response)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
                .simultaneousGesture(horizontalQuestionGesture)
                .onChange(of: currentIndex) { _, _ in
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(topAnchor, anchor: .top)
                    }
                }
            }

            footer(question: question, isRevealed: isRevealed)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)
        }
        .animation(.easeOut(duration: 0.2), value: isRevealed)
    }

    // MARK: - Header

    private func header(question: Question) -> some View {
        let bookmarked = isBookmarked(question)

        return VStack(spacing: 10) {
            HStack(spacing: 6) {
                RunnerCircleButton(icon: "xmark", accessibilityLabel: "Close sitting") {
                    HapticManager.light()
                    showExitAlert = true
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(payload.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitleLine)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 2)

                timerPill

                RunnerCircleButton(
                    icon: bookmarked ? "bookmark.fill" : "bookmark",
                    tint: bookmarked ? MedxTheme.warningOrange : nil,
                    accessibilityLabel: bookmarked ? "Remove bookmark" : "Bookmark question"
                ) {
                    toggleBookmark(question)
                }
            }

            Button {
                HapticManager.light()
                showNavigator = true
            } label: {
                VStack(spacing: 7) {
                    HStack(spacing: 5) {
                        Text("Question \(currentIndex + 1) of \(questions.count)")
                            .font(.caption.weight(.semibold).monospacedDigit())
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text("\(answeredCount) answered")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    progressTrack
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Question \(currentIndex + 1) of \(questions.count)")
            .accessibilityValue("\(answeredCount) answered")
            .accessibilityHint("Opens the question navigator")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // Untinted glass: the chrome stays neutral so the question content carries the colour.
        .medxNavigationGlass(cornerRadius: 22)
    }

    private var timerPill: some View {
        let paused = isTimerPaused
        let isLow = !paused && remainingSeconds <= 10
        let tint: Color = paused
            ? MedxTheme.successGreen
            : (isLow ? MedxTheme.destructiveRed : Color.primary)

        return HStack(spacing: 5) {
            Image(systemName: paused ? "checkmark.circle.fill" : "timer")
                .font(.caption.weight(.bold))
                .symbolEffect(.pulse, options: .repeating, isActive: isLow)
            Text(paused ? "Done" : formatTime(remainingSeconds))
                .font(.footnote.weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            isLow ? MedxTheme.destructiveRed.opacity(0.14) : Color(uiColor: .tertiarySystemFill),
            in: Capsule()
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            paused
                ? "Answer revealed, timer paused"
                : "Time remaining \(formatTime(remainingSeconds))"
        )
    }

    private var progressTrack: some View {
        let statuses = questionStatuses

        return Group {
            if statuses.count <= 28 {
                HStack(spacing: 3) {
                    ForEach(Array(statuses.enumerated()), id: \.offset) { index, status in
                        Capsule()
                            .fill(status.trackColor(accent: accent, isCurrent: index == currentIndex))
                            .frame(height: index == currentIndex ? 6 : 4)
                    }
                }
                .frame(height: 6)
            } else {
                continuousTrack
            }
        }
        .animation(.easeOut(duration: 0.22), value: currentIndex)
    }

    private var continuousTrack: some View {
        let fraction = Double(currentIndex + 1) / Double(max(questions.count, 1))

        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(uiColor: .quaternaryLabel))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [accent, MedxTheme.cyanAccent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, geo.size.width * fraction))
            }
        }
        .frame(height: 5)
    }

    // MARK: - Question, options, explanation

    private func questionCard(question: Question) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("QUESTION \(currentIndex + 1)")
                    .font(MedxFont.mono(11, weight: .bold))
                    .foregroundStyle(accent)
                Spacer(minLength: 0)
                if !payload.gradable {
                    RunnerChip(text: "No official key", tint: MedxTheme.warningOrange)
                }
            }

            HTMLRichTextView(html: question.displayText, fontSize: 17, weight: .semibold)

            if let images = question.images, !images.isEmpty {
                VStack(spacing: 10) {
                    ForEach(images, id: \.self) { imageUrl in
                        CachedAsyncImage(url: URL(string: imageUrl))
                            .frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .liquidGlassCard(cornerRadius: 22)
    }

    private func answerSection(
        question: Question,
        response: QuestionResponse?,
        isRevealed: Bool,
        isLocked: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(answerHint(response: response, isRevealed: isRevealed))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            ForEach(question.options) { option in
                let isChosen = response?.chosenId == option.id
                let isCorrect = option.correct == true || question.correctIds.contains(option.id)

                QuestionOptionButton(
                    option: option,
                    isChosen: isChosen,
                    isCorrect: isCorrect,
                    isRevealed: isRevealed,
                    isLocked: isLocked,
                    accent: accent,
                    isDimmed: isRevealed && !isChosen && !isCorrect
                ) {
                    handlePickOption(question: question, chosenId: option.id)
                }
            }
        }
    }

    private func answerHint(response: QuestionResponse?, isRevealed: Bool) -> String {
        if isRevealed { return "Correct answer highlighted below" }
        if response?.chosenId != nil { return "Tap another option to change your answer" }
        return "Choose the best answer"
    }

    private func explanationCard(question: Question, response: QuestionResponse?) -> some View {
        let outcome = RunnerOutcome(response: response)
        let correctLabel = question.options.first { option in
            option.correct == true || question.correctIds.contains(option.id)
        }?.label
        let reference = question.reference?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: outcome.icon)
                    .font(.subheadline.weight(.bold))
                Text(outcome.title)
                    .font(.subheadline.weight(.bold))
                Spacer(minLength: 0)

                if outcome != .correct, let correctLabel, !correctLabel.isEmpty {
                    Text("Answer \(correctLabel)")
                        .font(MedxFont.mono(11, weight: .bold))
                        .foregroundStyle(MedxTheme.successGreen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(MedxTheme.successGreen.opacity(0.14), in: Capsule())
                }
            }
            .foregroundStyle(outcome.color)

            if let explanation = question.explanation, !explanation.isEmpty {
                HTMLRichTextView(html: explanation, fontSize: 14, weight: .regular, textColor: .secondary)
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
        .liquidGlassCard(cornerRadius: 20, glowColor: outcome.color)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
    // MARK: - Footer

    private var isLastQuestion: Bool {
        currentIndex >= questions.count - 1
    }

    /// Exam mode never blocks navigation; revision requires the answer to be revealed first.
    private func canAdvance(isRevealed: Bool) -> Bool {
        payload.mode == .exam || isRevealed
    }

    private func footer(question: Question, isRevealed: Bool) -> some View {
        let canGo = canAdvance(isRevealed: isRevealed)
        let showSkip = payload.mode == .exam && responses[question.id]?.chosenId == nil && !isLastQuestion

        return VStack(spacing: 8) {
            if !canGo {
                Text("Choose an answer to reveal the explanation")
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
                            .frame(minWidth: 62, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                }

                Button {
                    HapticManager.medium()
                    if isLastQuestion {
                        finishSitting()
                    } else {
                        nextQuestion()
                    }
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
                .tint(accent)
                .disabled(!canGo)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .medxNavigationGlass(cornerRadius: 20)
        .safeAreaPadding(.bottom, 4)
    }

    private var horizontalQuestionGesture: some Gesture {
        DragGesture(minimumDistance: 32)
            .onEnded { value in
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                guard horizontal > 70, horizontal > vertical * 1.25 else { return }

                if value.translation.width < 0 {
                    guard let question = currentQuestion else { return }
                    let isRevealed = payload.mode == .revision && revealedQuestions[question.id] == true
                    guard canAdvance(isRevealed: isRevealed), !isLastQuestion else {
                        HapticManager.error()
                        return
                    }
                    nextQuestion()
                } else if currentIndex > 0 {
                    goBack()
                }
            }
    }

    // MARK: - Navigator

    private var navigatorSheet: some View {
        QuestionNavigatorSheet(
            questionCount: questions.count,
            currentIndex: currentIndex,
            furthestIndex: furthestIndex,
            statuses: questionStatuses,
            accent: accent,
            lockAhead: payload.mode == .revision
        ) { index in
            showNavigator = false
            jump(to: index)
        }
    }

    // MARK: - Loading & unavailable states

    private var loadingState: some View {
        VStack(spacing: 0) {
            dismissRow

            Spacer()

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

            Spacer()
            Spacer()
        }
    }

    private func unavailableState(message: String) -> some View {
        VStack(spacing: 0) {
            dismissRow

            Spacer()

            ContentUnavailableView {
                Label("Sitting unavailable", systemImage: "exclamationmark.triangle")
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
                    .tint(accent)

                    Button("Close") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

            Spacer()
            Spacer()
        }
    }

    private var dismissRow: some View {
        HStack {
            RunnerCircleButton(icon: "xmark", accessibilityLabel: "Close sitting") {
                HapticManager.light()
                dismiss()
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
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
            if isCorrect {
                HapticManager.success()
            } else {
                HapticManager.error()
            }
        } else {
            HapticManager.selection()
        }
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
    }

    private func nextQuestion() {
        guard currentIndex + 1 < questions.count else { return }
        currentIndex += 1
        furthestIndex = max(furthestIndex, currentIndex)
        resetTimerForCurrentQuestion()
    }

    private func jump(to index: Int) {
        guard questions.indices.contains(index), index != currentIndex else { return }
        HapticManager.light()
        currentIndex = index
        furthestIndex = max(furthestIndex, index)
        resetTimerForCurrentQuestion()
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

// MARK: - Small circular icon button

/// 34pt glyph in a neutral circle with a 44pt hit target. Used for close and
/// bookmark in the runner header and for bookmark in the review cards.
struct RunnerCircleButton: View {
    let icon: String
    var tint: Color?
    let accessibilityLabel: String
    var accessibilityValue: String?
    let action: () -> Void

    init(
        icon: String,
        tint: Color? = nil,
        accessibilityLabel: String,
        accessibilityValue: String? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.tint = tint
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint ?? Color.primary)
                .frame(width: 34, height: 34)
                .background(
                    (tint ?? Color.primary).opacity(tint == nil ? 0.06 : 0.14),
                    in: Circle()
                )
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue ?? "")
    }
}

// MARK: - Chip

struct RunnerChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(MedxFont.mono(10, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

// MARK: - Per-question status

enum RunnerQuestionStatus {
    case unanswered
    case answered
    case correct
    case wrong
    case timedOut

    func trackColor(accent: Color, isCurrent: Bool) -> Color {
        if isCurrent { return accent }
        switch self {
        case .unanswered: return Color(uiColor: .quaternaryLabel)
        case .answered: return accent.opacity(0.55)
        case .correct: return MedxTheme.successGreen.opacity(0.75)
        case .wrong: return MedxTheme.destructiveRed.opacity(0.75)
        case .timedOut: return MedxTheme.warningOrange.opacity(0.75)
        }
    }

    func chipFill(accent: Color) -> Color {
        switch self {
        case .unanswered: return Color(uiColor: .tertiarySystemFill)
        case .answered: return accent.opacity(0.16)
        case .correct: return MedxTheme.successGreen.opacity(0.16)
        case .wrong: return MedxTheme.destructiveRed.opacity(0.16)
        case .timedOut: return MedxTheme.warningOrange.opacity(0.16)
        }
    }

    func chipForeground(accent: Color) -> Color {
        switch self {
        case .unanswered: return .secondary
        case .answered: return accent
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

    var voiceOverLabel: String { legendLabel }
}

// MARK: - Outcome banner

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
    let accent: Color
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
                VStack(alignment: .leading, spacing: 18) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 54), spacing: 10)], spacing: 10) {
                        ForEach(0..<questionCount, id: \.self) { index in
                            tile(for: index)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Legend")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        ForEach(Array(legend.enumerated()), id: \.offset) { _, status in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(status.chipFill(accent: accent))
                                    .overlay(Circle().strokeBorder(status.chipForeground(accent: accent).opacity(0.5), lineWidth: 1))
                                    .frame(width: 14, height: 14)
                                Text(status.legendLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(20)
            }
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
                .font(MedxFont.mono(15, weight: .bold))
                .foregroundStyle(isCurrent ? accent : status.chipForeground(accent: accent))
                .frame(minWidth: 48, minHeight: 48)
                .background(status.chipFill(accent: accent), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isCurrent ? accent : Color.clear, lineWidth: 2)
                )
                .opacity(isLocked ? 0.35 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
        .accessibilityLabel("Question \(index + 1)")
        .accessibilityValue(isCurrent ? "Current, \(status.voiceOverLabel)" : status.voiceOverLabel)
    }
}
