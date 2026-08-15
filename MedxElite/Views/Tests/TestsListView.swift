import SwiftUI

public struct TestsListView: View {
    @ObservedObject var authService = AuthService.shared
    @State private var tests: [BatchTest] = []
    @State private var attempts: [SittingAttempt] = []
    @State private var isLoading = true
    @State private var activeRunnerPayload: RunnerPayload?

    public init() {}

    private var gradableTests: [BatchTest] {
        tests.filter { $0.gradable }
    }

    private var practiceTests: [BatchTest] {
        tests.filter { !$0.gradable }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

                if isLoading {
                    ProgressView("Loading Batch Tests...")
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            HStack {
                                Text("\(tests.count) batch tests · ARISE")
                                    .font(MedxFont.rounded(13, weight: .medium))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 6)

                            // Scored Tests Section
                            if !gradableTests.isEmpty {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("Scored Tests")
                                        .font(MedxFont.rounded(16, weight: .bold))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 20)

                                    ForEach(gradableTests) { test in
                                        TestDetailCard(
                                            test: test,
                                            attempts: attempts
                                        ) { mode in
                                            startTestSitting(test: test, mode: mode)
                                        }
                                        .padding(.horizontal, 20)
                                    }
                                }
                            }

                            // Practice Tests Section
                            if !practiceTests.isEmpty {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("Practice · No Official Key")
                                        .font(MedxFont.rounded(16, weight: .bold))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 20)

                                    ForEach(practiceTests) { test in
                                        TestDetailCard(
                                            test: test,
                                            attempts: attempts
                                        ) { mode in
                                            startTestSitting(test: test, mode: mode)
                                        }
                                        .padding(.horizontal, 20)
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 90)
                    }
                    .refreshable {
                        await loadTestsData()
                    }
                }
            }
            .navigationTitle("Tests")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await loadTestsData()
            }
            .fullScreenCover(item: $activeRunnerPayload) { payload in
                QuizRunnerView(payload: payload) {
                    Task { await loadTestsData() }
                }
            }
        }
    }

    private func loadTestsData() async {
        guard let uid = authService.currentSession?.uid else { return }
        do {
            let token = try await authService.getValidIdToken()
            async let testsTask = FirestoreService.shared.fetchTests(idToken: token)
            async let attemptsTask = FirestoreService.shared.fetchUserAttempts(uid: uid, idToken: token)

            let (t, a) = try await (testsTask, attemptsTask)
            self.tests = t
            self.attempts = a.filter { $0.kind == "test" }
            self.isLoading = false
        } catch {
            self.isLoading = false
        }
    }

    private func startTestSitting(test: BatchTest, mode: SittingMode) {
        self.activeRunnerPayload = RunnerPayload(
            kind: "test",
            id: test.testId,
            name: test.name,
            subject: test.subject,
            mode: mode,
            gradable: test.gradable
        )
    }
}
