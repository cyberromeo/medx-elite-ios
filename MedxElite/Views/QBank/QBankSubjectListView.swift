import SwiftUI

public struct QBankSubjectListView: View {
    @ObservedObject var authService = AuthService.shared
    @State private var subjects: [QBankSubject] = []
    @State private var attempts: [SittingAttempt] = []
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var activeRunnerPayload: RunnerPayload?
    @ObservedObject private var activityStore = ActivityStore.shared

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

                        MedxMetricsRow {
                            MedxMetric(icon: "books.vertical.fill", value: "\(subjects.count)", label: "subjects", color: MedxTheme.primaryBlue)
                            MedxMetric(icon: "square.grid.2x2.fill", value: "\(totalModules)", label: "modules", color: MedxTheme.primaryPurple)
                            MedxMetric(icon: "questionmark.circle.fill", value: totalQ.formatted(), label: "questions", color: MedxTheme.cyanAccent)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 6)

                        NavigationLink {
                            BookmarkedQuestionsView(uid: authService.currentSession?.uid)
                        } label: {
                            HStack {
                                Label("Bookmarked Questions", systemImage: "bookmark.fill")
                                Spacer()
                                Text("\(activityStore.bookmarks(for: authService.currentSession?.uid).count)")
                                    .font(.subheadline.monospacedDigit().weight(.semibold))
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(MedxTheme.primaryPurple)
                        .padding(.horizontal, 20)

                        if filteredSubjects.isEmpty {
                            ContentUnavailableView {
                                Label("No Subjects", systemImage: "magnifyingglass")
                            } description: {
                                Text(searchText.isEmpty ? "Subjects will appear here when available." : "Try a different search.")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 36)
                        }

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
                        .padding(.bottom, 24)
                    }
                }
                .refreshable {
                    await loadData()
                }
            }
        }
        .navigationTitle("Question Bank")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ProfileSettingsButton()
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search subjects")
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
                    .lineLimit(2)

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
        .glassCard(cornerRadius: 20, shadowLevel: 1)
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
