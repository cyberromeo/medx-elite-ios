import SwiftUI

public struct QBankSubjectListView: View {
    @ObservedObject var authService = AuthService.shared
    @State private var subjects: [QBankSubject] = []
    @State private var attempts: [SittingAttempt] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var activeRunnerPayload: RunnerPayload?

    public init() {}

    private var filteredSubjects: [QBankSubject] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return subjects
        }
        return subjects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var attemptedSubjectsCount: [Int: Int] {
        var map: [Int: Int] = [:]
        let doneModuleIds = Set(attempts.filter { $0.kind == "qbank" }.map { $0.sourceId })
        for s in subjects {
            var count = 0
            for c in s.chapters ?? [] {
                for m in c.modules ?? [] {
                    if doneModuleIds.contains(m.id) { count += 1 }
                }
            }
            map[s.subjectId] = count
        }
        return map
    }

    public var body: some View {
        ZStack {
            // Ambient Canvas
            ambientBackground

            if isLoading {
                ProgressView("Loading Question Bank…")
                    .controlSize(.large)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Summary Stats Card
                        let totalQ = subjects.reduce(0) { $0 + ($1.questionCount ?? 0) }
                        let totalModules = subjects.reduce(0) { $0 + $1.moduleCount }

                        HStack(spacing: 14) {
                            statPill(icon: "books.vertical.fill", value: "\(subjects.count)", label: "subjects", color: MedxTheme.primaryBlue)
                            statPill(icon: "square.grid.2x2.fill", value: "\(totalModules)", label: "modules", color: MedxTheme.primaryPurple)
                            statPill(icon: "questionmark.circle.fill", value: totalQ.formatted(), label: "questions", color: MedxTheme.cyanAccent)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 6)

                        // Subjects List
                        LazyVStack(spacing: 12) {
                            ForEach(filteredSubjects) { subject in
                                NavigationLink {
                                    QBankChapterView(
                                        subject: subject,
                                        attempts: attempts
                                    ) { module, mode in
                                        startSession(moduleId: module.id, subjectName: subject.name, moduleName: module.name, mode: mode)
                                    }
                                } label: {
                                    subjectRow(subject)
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(
                                    TapGesture().onEnded {
                                        HapticManager.light()
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 90)
                    }
                }
                .refreshable {
                    await loadData()
                }
            }
        }
        .navigationTitle("Question Bank")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search subjects…")
        .task {
            await loadData()
        }
        .fullScreenCover(item: $activeRunnerPayload) { (payload: RunnerPayload) in
            QuizRunnerView(payload: payload) {
                Task { await loadData() }
            }
        }
    }

    // MARK: - Subject Row

    private func subjectRow(_ subject: QBankSubject) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [MedxTheme.primaryBlue.opacity(0.18), MedxTheme.cyanAccent.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: "book.closed.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(MedxTheme.primaryBlue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(subject.name)
                    .font(MedxFont.headline(16))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("\(subject.moduleCount) modules · \((subject.questionCount ?? 0).formatted()) questions")
                    .font(MedxFont.caption(12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            let attempted = attemptedSubjectsCount[subject.subjectId] ?? 0
            if attempted > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                    Text("\(attempted) done")
                        .font(MedxFont.mono(11, weight: .bold))
                }
                .foregroundColor(MedxTheme.successGreen)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(MedxTheme.successGreen.opacity(0.12), in: Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(uiColor: .tertiaryLabel))
        }
        .padding(16)
        .liquidGlassCard(cornerRadius: 20)
    }

        private func statPill(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(color)
                Text(value)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .allowsTightening(true)
            }
            Text(label.capitalized)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(color.opacity(0.08), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    private var ambientBackground: some View {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
    }

    // MARK: - Actions & Data

    private func loadData() async {
        guard let uid = authService.currentSession?.uid else { return }
        do {
            let token = try await authService.getValidIdToken()
            async let subjectsTask = FirestoreService.shared.fetchQBankSubjects(idToken: token)
            async let attemptsTask = FirestoreService.shared.fetchUserAttempts(uid: uid, idToken: token)

            let (s, a) = try await (subjectsTask, attemptsTask)
            self.subjects = s
            self.attempts = a
            self.isLoading = false
        } catch {
            self.isLoading = false
        }
    }

    private func startSession(moduleId: String, subjectName: String, moduleName: String, mode: SittingMode) {
        self.activeRunnerPayload = RunnerPayload(
            kind: "qbank",
            id: moduleId,
            name: moduleName,
            subject: subjectName,
            mode: mode,
            gradable: true
        )
    }
}
