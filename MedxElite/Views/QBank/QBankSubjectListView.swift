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
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading Question Bank...")
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                // Summary
                Section {
                    let totalQ = subjects.reduce(0) { $0 + ($1.questionCount ?? 0) }
                    Text("\(totalQ.formatted()) questions · \(subjects.count) subjects")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                // Subject List
                Section {
                    ForEach(filteredSubjects) { subject in
                        NavigationLink {
                            QBankChapterView(
                                subject: subject,
                                attempts: attempts
                            ) { module, mode in
                                startSession(moduleId: module.id, subjectName: subject.name, moduleName: module.name, mode: mode)
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "book.closed.fill")
                                    .font(.title3)
                                    .foregroundColor(.accentColor)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(subject.name)
                                        .font(.headline)

                                    Text("\(subject.moduleCount) modules · \((subject.questionCount ?? 0).formatted()) questions")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                let attempted = attemptedSubjectsCount[subject.subjectId] ?? 0
                                if attempted > 0 {
                                    Text("\(attempted)")
                                        .font(.caption.bold())
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.green.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Question Bank")
        .searchable(text: $searchText, prompt: "Search subjects")
        .refreshable {
            await loadData()
        }
        .task {
            await loadData()
        }
        .fullScreenCover(item: $activeRunnerPayload) { payload in
            QuizRunnerView(payload: payload) {
                Task { await loadData() }
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
