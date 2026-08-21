import SwiftUI

public struct QuizRunnerView: View {
    public let payload: RunnerPayload
    public var onFinishedSession: () -> Void

    @State private var questions: [Question] = []
    @State private var currentIndex = 0
    @State private var responses: [Int: QuestionResponse] = [:]
    @State private var revealedQuestions: [Int: Bool] = [:]
    @State private var remainingSeconds: Int = 0
    @State private var isFinished = false
    @State private var isSaving = false
    @State private var isLoading = true
    @State private var showExitAlert = false
    @State private var startedAt = Date()
    @ObservedObject private var activityStore = ActivityStore.shared

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @Environment(\.dismiss) private var dismiss

    public init(payload: RunnerPayload, onFinishedSession: @escaping () -> Void) {
        self.payload = payload
        self.onFinishedSession = onFinishedSession
    }

    private var currentQuestion: Question? {
        guard questions.indices.contains(currentIndex) else { return nil }
        return questions[currentIndex]
    }

    public var body: some View {
        ZStack {
            ambientBackground

            if isLoading {
                ProgressView("Loading sitting…")
                    .controlSize(.large)
            } else if isFinished {
                SittingReviewView(
                    name: payload.name,
                    subject: payload.subject,
                    questions: questions,
                    responses: responses,
                    gradable: payload.gradable
                ) {
                    onFinishedSession()
                    dismiss()
                }
            } else if let question = currentQuestion {
                let currentResp = responses[question.id]
                let isLocked = currentResp != nil
                let isRevealed = payload.mode == .revision && revealedQuestions[question.id] == true

                VStack(spacing: 0) {
                    // MARK: - Floating Liquid Glass Top HUD
                    topHUD(question: question)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    // Linear Progress Bar
                    GeometryReader { geo in
                        let progress = Double(currentIndex + 1) / Double(max(questions.count, 1))
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 4)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            payload.mode == .exam ? MedxTheme.primaryBlue : MedxTheme.primaryPurple,
                                            MedxTheme.cyanAccent
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geo.size.width * CGFloat(progress), height: 4)
                                .animation(.spring(), value: progress)
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 20)

                    // Main Scrollable Question Content
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            // Mode & Subject Tags
                            HStack(spacing: 8) {
                                Text(payload.mode.displayName)
                                    .font(MedxFont.mono(11, weight: .bold))
                                    .foregroundColor(payload.mode == .exam ? MedxTheme.primaryBlue : MedxTheme.primaryPurple)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 4)
                                    .background((payload.mode == .exam ? MedxTheme.primaryBlue : MedxTheme.primaryPurple).opacity(0.12), in: Capsule())

                                if !payload.subject.isEmpty {
                                    Text(payload.subject)
                                        .font(MedxFont.caption(11))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 4)
                                        .background(Color.primary.opacity(0.05), in: Capsule())
                                }

                                if !payload.gradable {
                                    Text("Practice Only")
                                        .font(MedxFont.mono(10, weight: .bold))
                                        .foregroundColor(MedxTheme.warningOrange)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(MedxTheme.warningOrange.opacity(0.12), in: Capsule())
                                }
                            }
                            .padding(.top, 12)

                            // Question Text (Native SF Pro via HTMLRichTextView)
                            HTMLRichTextView(html: question.displayText, fontSize: 17, weight: .semibold)

                            // Question Images
                            if let imgs = question.images, !imgs.isEmpty {
                                ForEach(imgs, id: \.self) { imgUrl in
                                    CachedAsyncImage(url: URL(string: imgUrl))
                                        .frame(maxHeight: 240)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                }
                            }

                            // Options List
                            VStack(spacing: 12) {
                                ForEach(question.options) { opt in
                                    let isChosen = currentResp?.chosenId == opt.id
                                    let isCorrect = opt.correct == true || question.correctIds.contains(opt.id)

                                    QuestionOptionButton(
                                        option: opt,
                                        isChosen: isChosen,
                                        isCorrect: isCorrect,
                                        isRevealed: isRevealed,
                                        isLocked: isLocked
                                    ) {
                                        handlePickOption(question: question, chosenId: opt.id)
                                    }
                                }
                            }

                            // Revision Instant Explanation Card (Liquid Glass)
                            if isRevealed {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        if currentResp?.timedOut == true {
                                            Label("Time Up · Unattempted", systemImage: "clock.badge.xmark")
                                                .font(MedxFont.label(12))
                                                .foregroundColor(MedxTheme.warningOrange)
                                        } else if currentResp?.correct == true {
                                            Label("Correct Answer", systemImage: "checkmark.circle.fill")
                                                .font(MedxFont.label(12))
                                                .foregroundColor(MedxTheme.successGreen)
                                        } else {
                                            Label("Incorrect Answer", systemImage: "xmark.circle.fill")
                                                .font(MedxFont.label(12))
                                                .foregroundColor(MedxTheme.destructiveRed)
                                        }
                                    }

                                    if let expl = question.explanation, !expl.isEmpty {
                                        HTMLRichTextView(html: expl, fontSize: 14, weight: .regular, textColor: .secondary)
                                    } else {
                                        Text("No explanation provided.")
                                            .font(MedxFont.caption(13))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(18)
                                .liquidGlassCard(cornerRadius: 20, glowColor: currentResp?.correct == true ? MedxTheme.successGreen : MedxTheme.destructiveRed)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 110)
                    }
                    .simultaneousGesture(horizontalQuestionGesture)

                    // MARK: - Bottom Liquid Glass Floating Bar
                    bottomBar(question: question, isRevealed: isRevealed)
                }
            }
        }
        .alert("Leave Sitting?", isPresented: $showExitAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Leave", role: .destructive) {
                dismiss()
            }
        } message: {
            Text("Your sitting progress will not be saved if you exit now.")
        }
        .onReceive(timer) { _ in
            guard !isLoading, !isFinished else { return }
            if payload.mode == .revision, let q = currentQuestion, responses[q.id] != nil {
                return
            }
            if remainingSeconds > 0 {
                remainingSeconds -= 1
            } else {
                handleTimeout()
            }
        }
        .task {
            await loadSittingQuestions()
        }
    }

    // MARK: - Top Glass HUD

    private func topHUD(question: Question) -> some View {
        HStack(spacing: 12) {
            Button {
                showExitAlert = true
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close sitting")
            .accessibilityHint("Shows options to leave this sitting")

            VStack(alignment: .leading, spacing: 2) {
                Text(payload.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("Question \(currentIndex + 1) of \(questions.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

             Button {
                 guard let question = currentQuestion, let uid = AuthService.shared.currentSession?.uid else { return }
                 activityStore.toggleBookmark(question: question, payload: payload, uid: uid)
                 HapticManager.selection()
             } label: {
                 Image(systemName: activityStore.isBookmarked(questionId: question.id, sourceId: payload.id, uid: AuthService.shared.currentSession?.uid) ? "bookmark.fill" : "bookmark")
                     .font(.body.weight(.semibold))
                     .frame(width: 44, height: 44)
             }
             .buttonStyle(.plain)
             .accessibilityLabel(activityStore.isBookmarked(questionId: question.id, sourceId: payload.id, uid: AuthService.shared.currentSession?.uid) ? "Remove bookmark" : "Bookmark question")

             Label(formatTime(remainingSeconds), systemImage: "timer")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(remainingSeconds <= 10 ? MedxTheme.destructiveRed : .primary)
                .padding(.horizontal, 10)
                .frame(minHeight: 36)
                .background(Color(uiColor: .tertiarySystemFill), in: Capsule())
                .accessibilityLabel("Time remaining")
                .accessibilityValue(formatTime(remainingSeconds))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .medxNavigationGlass(cornerRadius: 16, tint: payload.mode == .exam ? MedxTheme.primaryBlue : MedxTheme.primaryPurple)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    // MARK: - Bottom Floating Bar

    private func bottomBar(question: Question, isRevealed: Bool) -> some View {
        let isLast = currentIndex + 1 >= questions.count
        let canAdvance = payload.mode == .exam || isRevealed

        return VStack(spacing: 8) {
            bookmarkButton(question: question)

            HStack(spacing: 12) {
                Button {
                    HapticManager.light()
                    currentIndex -= 1
                    resetTimerForQuestion()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.titleAndIcon)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(currentIndex == 0)

                if payload.mode == .exam && responses[question.id] == nil {
                    Button {
                        HapticManager.light()
                        nextQuestion()
                    } label: {
                        Text("Skip")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    HapticManager.medium()
                    if isLast {
                        finishSitting()
                    } else {
                        nextQuestion()
                    }
                } label: {
                    Text(isLast ? "Finish" : "Next")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(payload.mode == .exam ? MedxTheme.primaryBlue : MedxTheme.primaryPurple)
                .disabled(!canAdvance)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .medxNavigationGlass(cornerRadius: 20, tint: payload.mode == .exam ? MedxTheme.primaryBlue : MedxTheme.primaryPurple)
        .overlay(alignment: .top) {
            Divider()
        }
        .safeAreaPadding(.bottom, 4)
    }

    private func bookmarkButton(question: Question) -> some View {
        let uid = AuthService.shared.currentSession?.uid
        let isBookmarked = activityStore.isBookmarked(questionId: question.id, sourceId: payload.id, uid: uid)

        return Button {
            guard uid != nil else { return }
            activityStore.toggleBookmark(question: question, payload: payload, uid: uid)
            HapticManager.selection()
        } label: {
            Label(isBookmarked ? "Bookmarked" : "Bookmark question", systemImage: isBookmarked ? "bookmark.fill" : "bookmark")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(isBookmarked ? MedxTheme.primaryPurple : .secondary)
        .accessibilityValue(isBookmarked ? "Saved" : "Not saved")
    }

    private var horizontalQuestionGesture: some Gesture {
        DragGesture(minimumDistance: 32)
            .onEnded { value in
                let horizontal = abs(value.translation.width)
                let vertical = abs(value.translation.height)
                guard horizontal > 70, horizontal > vertical * 1.25 else { return }

                if value.translation.width < 0 {
                    guard let question = currentQuestion else { return }
                    let canAdvance = payload.mode == .exam || revealedQuestions[question.id] == true
                    guard canAdvance else {
                        HapticManager.error()
                        return
                    }
                    nextQuestion()
                } else if currentIndex > 0 {
                    currentIndex -= 1
                    resetTimerForQuestion()
                    HapticManager.light()
                }
            }
    }

    private var ambientBackground: some View {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
    }

    private func handlePickOption(question: Question, chosenId: Int) {
        let isCorrect = question.correctIds.contains(chosenId)
        let resp = QuestionResponse(questionId: question.id, chosenId: chosenId, correct: isCorrect)
        responses[question.id] = resp

        if payload.mode == .revision {
            revealedQuestions[question.id] = true
            if isCorrect {
                HapticManager.success()
            } else {
                HapticManager.error()
            }
        }
    }

    private func handleTimeout() {
        if payload.mode == .exam {
            finishSitting()
        } else if let q = currentQuestion {
            let resp = QuestionResponse(questionId: q.id, chosenId: nil, correct: false, timedOut: true)
            responses[q.id] = resp
            revealedQuestions[q.id] = true
            HapticManager.warning()
        }
    }

    private func nextQuestion() {
        if currentIndex + 1 < questions.count {
            currentIndex += 1
            resetTimerForQuestion()
        }
    }

    private func resetTimerForQuestion() {
        if payload.mode == .revision {
            remainingSeconds = 60
        }
    }

    private func finishSitting() {
        isFinished = true
        HapticManager.success()
        saveSittingAttempt()
    }

    private func saveSittingAttempt() {
        guard let session = AuthService.shared.currentSession else { return }
        let score = responses.values.filter { $0.correct }.count
        let attempted = responses.values.filter { $0.chosenId != nil }.count
        let duration = Int(Date().timeIntervalSince(startedAt))

        let attempt = SittingAttempt(
            id: nil,
            uid: session.uid,
            profile: AuthService.shared.currentProfile?.handle,
            kind: payload.kind,
            sourceId: payload.id,
            name: payload.name,
            subject: payload.subject,
            mode: payload.mode.rawValue,
            gradable: payload.gradable,
            total: questions.count,
            score: score,
            attempted: attempted,
            durationSeconds: duration,
            finishedAt: ISO8601DateFormatter().string(from: Date()),
            responses: Array(responses.values)
        )

        Task {
            do {
                let token = try await AuthService.shared.getValidIdToken()
                try await FirestoreService.shared.saveAttempt(attempt, idToken: token)
            } catch {
                // Saved locally
            }
        }
    }

    private func loadSittingQuestions() async {
        do {
            let token = try await AuthService.shared.getValidIdToken()
            if payload.kind == "qbank" {
                let mod = try await FirestoreService.shared.fetchQBankModule(moduleId: payload.id, idToken: token)
                self.questions = mod.questions ?? []
            } else {
                let qs = try await FirestoreService.shared.fetchTestQuestions(testId: payload.id, idToken: token)
                self.questions = qs
            }

            if payload.mode == .exam {
                self.remainingSeconds = max(questions.count * 60, 60)
            } else {
                self.remainingSeconds = 60
            }
            self.startedAt = Date()
            self.isLoading = false
        } catch {
            self.isLoading = false
        }
    }

    private func formatTime(_ secs: Int) -> String {
        let m = secs / 60
        let s = secs % 60
        return String(format: "%02d:%02d", m, s)
    }
}
