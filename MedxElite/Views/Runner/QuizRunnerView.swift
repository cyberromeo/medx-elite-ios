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
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

            if isLoading {
                ProgressView("Loading sitting...")
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
                    // Top Progress & Timer Bar
                    HStack {
                        Button {
                            showExitAlert = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Question Index Indicator
                        Text("\(currentIndex + 1) / \(questions.count)")
                            .font(MedxFont.monospacedDigits(16, weight: .bold))
                            .foregroundColor(.primary)

                        Spacer()

                        // Timer Badge
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                                .font(.caption)
                            Text(formatTime(remainingSeconds))
                                .font(MedxFont.monospacedDigits(14, weight: .bold))
                        }
                        .foregroundColor(remainingSeconds <= 10 ? MedxTheme.destructiveRed : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(remainingSeconds <= 10 ? MedxTheme.destructiveRed.opacity(0.15) : Color.primary.opacity(0.08))
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                    // Linear Progress Bar
                    GeometryReader { geo in
                        let progress = Double(currentIndex + 1) / Double(max(questions.count, 1))
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 4)
                            Rectangle()
                                .fill(payload.mode == .exam ? MedxTheme.primaryBlue : MedxTheme.primaryPurple)
                                .frame(width: geo.size.width * CGFloat(progress), height: 4)
                                .animation(.spring(), value: progress)
                        }
                    }
                    .frame(height: 4)

                    // Main Scrollable Question Content
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            // Mode & Subject Tags
                            HStack(spacing: 8) {
                                Text(payload.mode.displayName)
                                    .font(MedxFont.rounded(11, weight: .bold))
                                    .foregroundColor(payload.mode == .exam ? MedxTheme.primaryBlue : MedxTheme.primaryPurple)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background((payload.mode == .exam ? MedxTheme.primaryBlue : MedxTheme.primaryPurple).opacity(0.12))
                                    .clipShape(Capsule())

                                if !payload.subject.isEmpty {
                                    Text(payload.subject)
                                        .font(MedxFont.rounded(11, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.primary.opacity(0.06))
                                        .clipShape(Capsule())
                                }

                                if !payload.gradable {
                                    Text("Practice Only")
                                        .font(MedxFont.rounded(11, weight: .bold))
                                        .foregroundColor(MedxTheme.warningOrange)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(MedxTheme.warningOrange.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.top, 12)

                            // Question Text
                            HTMLRichTextView(html: question.displayText, font: MedxFont.rounded(17, weight: .semibold))

                            // Question Images
                            if let imgs = question.images, !imgs.isEmpty {
                                ForEach(imgs, id: \.self) { imgUrl in
                                    CachedAsyncImage(url: URL(string: imgUrl))
                                        .frame(maxHeight: 240)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

                            // Revision Instant Explanation Card
                            if isRevealed {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        if currentResp?.timedOut == true {
                                            Label("Time Up · Unattempted", systemImage: "clock.badge.xmark")
                                                .font(MedxFont.rounded(12, weight: .bold))
                                                .foregroundColor(MedxTheme.warningOrange)
                                        } else if currentResp?.correct == true {
                                            Label("Correct Answer", systemImage: "checkmark.circle.fill")
                                                .font(MedxFont.rounded(12, weight: .bold))
                                                .foregroundColor(MedxTheme.successGreen)
                                        } else {
                                            Label("Incorrect Answer", systemImage: "xmark.circle.fill")
                                                .font(MedxFont.rounded(12, weight: .bold))
                                                .foregroundColor(MedxTheme.destructiveRed)
                                        }
                                    }

                                    if let expl = question.explanation, !expl.isEmpty {
                                        HTMLRichTextView(html: expl, font: MedxFont.rounded(14, weight: .regular), textColor: .secondary)
                                    } else {
                                        Text("No explanation provided.")
                                            .font(MedxFont.rounded(13, weight: .regular))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(16)
                                .liquidGlassCard(cornerRadius: 18, glowColor: currentResp?.correct == true ? MedxTheme.successGreen : MedxTheme.destructiveRed)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 100)
                    }

                    // Bottom Navigation Bar
                    HStack(spacing: 16) {
                        // Back Button
                        Button {
                            if currentIndex > 0 {
                                HapticManager.light()
                                currentIndex -= 1
                                resetTimerForQuestion()
                            }
                        } label: {
                            Text("Back")
                                .font(MedxFont.rounded(15, weight: .bold))
                                .foregroundColor(currentIndex > 0 ? .primary : .secondary.opacity(0.4))
                                .frame(height: 50)
                                .padding(.horizontal, 20)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .disabled(currentIndex == 0)

                        // Exam Skip Button
                        if payload.mode == .exam && responses[question.id] == nil {
                            Button {
                                HapticManager.light()
                                nextQuestion()
                            } label: {
                                Text("Skip")
                                    .font(MedxFont.rounded(15, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .frame(height: 50)
                                    .padding(.horizontal, 20)
                                    .background(Color.primary.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }

                        // Next / Finish Button
                        let isLast = currentIndex + 1 >= questions.count
                        let canAdvance = payload.mode == .exam || isRevealed

                        Button {
                            HapticManager.medium()
                            if isLast {
                                finishSitting()
                            } else {
                                nextQuestion()
                            }
                        } label: {
                            Text(isLast ? "Finish Sitting" : "Next")
                                .font(MedxFont.rounded(16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(canAdvance ? (payload.mode == .exam ? MedxTheme.primaryBlue : MedxTheme.primaryPurple) : Color.gray.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .disabled(!canAdvance)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)
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
                // In revision mode, stop countdown once answered
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
                // Saved locally if network fails
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
