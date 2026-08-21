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
        ZStack {
            ambientBackground

            if isLoading {
                ProgressView("Loading Batch Tests…")
                    .controlSize(.large)
            } else {
                ScrollView {
                    VStack(spacing: 22) {
                        // Header summary
                        MedxMetricsRow {
                            MedxMetric(icon: "checkmark.seal.fill", value: "\(gradableTests.count)", label: "scored tests", color: MedxTheme.successGreen)
                            MedxMetric(icon: "doc.text.fill", value: "\(practiceTests.count)", label: "practice", color: MedxTheme.warningOrange)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 6)

                        // Scored Tests Section
                        if !gradableTests.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Text("Scored Tests")
                                        .font(MedxFont.headline(16))
                                    Spacer()
                                    Text("Official Answer Key")
                                        .font(MedxFont.mono(10, weight: .bold))
                                        .foregroundColor(MedxTheme.successGreen)
                                }
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
                                HStack {
                                    Text("Practice Papers")
                                        .font(MedxFont.headline(16))
                                    Spacer()
                                    Text("No Official Key")
                                        .font(MedxFont.mono(10, weight: .bold))
                                        .foregroundColor(MedxTheme.warningOrange)
                                }
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
                    .padding(.bottom, 24)
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
        .fullScreenCover(item: $activeRunnerPayload) { (payload: RunnerPayload) in
            QuizRunnerView(payload: payload) {
                Task { await loadTestsData() }
            }
        }
    }

    private var ambientBackground: some View {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
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
        HapticManager.medium()
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
