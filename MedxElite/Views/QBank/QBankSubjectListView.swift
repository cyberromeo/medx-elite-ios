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
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading Question Bank...")
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Subheader Summary
                            let totalQ = subjects.reduce(0) { $0 + ($1.questionCount ?? 0) }
                            HStack {
                                Text("\(totalQ.formatted()) questions · \(subjects.count) subjects")
                                    .font(MedxFont.rounded(13, weight: .medium))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

                            // Search Bar
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                TextField("Search subjects...", text: $searchText)
                                    .font(MedxFont.rounded(15, weight: .regular))
                                if !searchText.isEmpty {
                                    Button {
                                        searchText = ""
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(12)
                            .liquidGlassCard(cornerRadius: 14)
                            .padding(.horizontal, 20)

                            // Subject Cards
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
                                        SubjectRowCard(
                                            subject: subject,
                                            attemptedCount: attemptedSubjectsCount[subject.subjectId] ?? 0
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
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
            .task {
                await loadData()
            }
            .fullScreenCover(item: $activeRunnerPayload) { payload in
                QuizRunnerView(payload: payload) {
                    Task { await loadData() }
                }
            }
        }
    }

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

public struct RunnerPayload: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: String // "qbank" or "test"
    public let name: String
    public let subject: String
    public let mode: SittingMode
    public let gradable: Bool

    public init(kind: String, id: String, name: String, subject: String, mode: SittingMode, gradable: Bool = true) {
        self.kind = kind
        self.id = id
        self.name = name
        self.subject = subject
        self.mode = mode
        self.gradable = gradable
    }
}

private struct SubjectRowCard: View {
    let subject: QBankSubject
    let attemptedCount: Int

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(MedxTheme.primaryBlue.opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: "book.closed.fill")
                    .font(.headline)
                    .foregroundColor(MedxTheme.primaryBlue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(subject.name)
                    .font(MedxFont.rounded(16, weight: .bold))
                    .foregroundColor(.primary)

                Text("\(subject.moduleCount) modules · \((subject.questionCount ?? 0).formatted()) questions")
                    .font(MedxFont.rounded(13, weight: .regular))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if attemptedCount > 0 {
                Text("\(attemptedCount)")
                    .font(MedxFont.monospacedDigits(12, weight: .bold))
                    .foregroundColor(MedxTheme.successGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(MedxTheme.successGreen.opacity(0.15))
                    .clipShape(Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(16)
        .liquidGlassCard(cornerRadius: 18)
    }
}
