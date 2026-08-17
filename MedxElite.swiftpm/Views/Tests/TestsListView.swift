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
                        HStack(spacing: 12) {
                            statPill(icon: "checkmark.seal.fill", value: "\(gradableTests.count)", label: "scored tests", color: MedxTheme.successGreen)
                            statPill(icon: "doc.text.fill", value: "\(practiceTests.count)", label: "practice", color: MedxTheme.warningOrange)
                            Spacer()
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
        .fullScreenCover(item: $activeRunnerPayload) { (payload: RunnerPayload) in
            QuizRunnerView(payload: payload) {
                Task { await loadTestsData() }
            }
        }
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
        ZStack {
            Color(uiColor: .systemGroupedBackground)

            Circle()
                .fill(MedxTheme.successGreen.opacity(0.06))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(x: 100, y: -200)

            Circle()
                .fill(MedxTheme.primaryBlue.opacity(0.06))
                .frame(width: 350, height: 350)
                .blur(radius: 90)
                .offset(x: -120, y: 300)
        }
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
