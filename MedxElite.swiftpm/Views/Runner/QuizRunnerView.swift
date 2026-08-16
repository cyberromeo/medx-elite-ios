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
        HStack(alignment: .center) {
            Button {
                showExitAlert = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))
            }

            Spacer()

            Text("\(currentIndex + 1) / \(questions.count)")
                .font(MedxFont.mono(15, weight: .bold))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8))

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 11, weight: .semibold))
                Text(formatTime(remainingSeconds))
                    .font(MedxFont.mono(13, weight: .bold))
            }
            .foregroundColor(remainingSeconds <= 10 ? MedxTheme.destructiveRed : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                (remainingSeconds <= 10 ? MedxTheme.destructiveRed.opacity(0.15) : Color.primary.opacity(0.06)),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    remainingSeconds <= 10 ? MedxTheme.destructiveRed.opacity(0.4) : Color.white.opacity(0.12),
                    lineWidth: 0.8
                )
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.06), radius: 10, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
        )
    }

    // MARK: - Bottom Floating Bar

    private func bottomBar(question: Question, isRevealed: Bool) -> some View {
        HStack(spacing: 14) {
            // Back Button
            Button {
                if currentIndex > 0 {
                    HapticManager.light()
                    currentIndex -= 1
                    resetTimerForQuestion()
                }
            } label: {
                Text("Back")
                    .font(MedxFont.headline(15))
                    .foregroundColor(currentIndex > 0 ? .primary : .secondary.opacity(0.4))
                    .frame(height: 48)
                    .padding(.horizontal, 18)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(currentIndex == 0)

            // Exam Skip Button
            if payload.mode == .exam && responses[question.id] == nil {
                Button {
                    HapticManager.light()
                    nextQuestion()
                } label: {
                    Text("Skip")
                        .font(MedxFont.headline(15))
                        .foregroundColor(.secondary)
                        .frame(height: 48)
                        .padding(.horizontal, 18)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    .font(MedxFont.headline(15))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        canAdvance
                            ? (payload.mode == .exam ? MedxTheme.primaryBlue : MedxTheme.primaryPurple)
                            : Color.gray.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .shadow(
                        color: canAdvance
                            ? (payload.mode == .exam ? MedxTheme.primaryBlue : MedxTheme.primaryPurple).opacity(0.3)
                            : Color.clear,
                        radius: 8,
                        y: 3
                    )
            }
            .disabled(!canAdvance)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.12), radius: 16, y: -4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var ambientBackground: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)

            Circle()
                .fill((payload.mode == .exam ? MedxTheme.primaryBlue : MedxTheme.primaryPurple).opacity(0.08))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: -120, y: -200)

            Circle()
                .fill(MedxTheme.cyanAccent.opacity(0.05))
                .frame(width: 350, height: 350)
                .blur(radius: 90)
                .offset(x: 120, y: 300)
        }
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
