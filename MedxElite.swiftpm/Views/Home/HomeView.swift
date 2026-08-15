import SwiftUI

public struct HomeView: View {
    @ObservedObject var authService = AuthService.shared
    @State private var attempts: [SittingAttempt] = []
    @State private var trackerDoc: UserTrackerDoc?
    @State private var isLoading = true
    @State private var showSettings = false
    @State private var showTrackerSheet = false
    public var onSelectTab: (TabItem) -> Void

    public init(onSelectTab: @escaping (TabItem) -> Void) {
        self.onSelectTab = onSelectTab
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 5 { return "Still up" }
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Greeting Header
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(greetingText),")
                                    .font(MedxFont.rounded(15, weight: .medium))
                                    .foregroundColor(.secondary)

                                if let profile = authService.currentProfile {
                                    Text(profile.displayName)
                                        .font(MedxFont.rounded(28, weight: .black))
                                        .foregroundStyle(profile.gradient)
                                }
                            }

                            Spacer()

                            // Profile Avatar / Settings Button
                            Button {
                                HapticManager.light()
                                showSettings = true
                            } label: {
                                if let profile = authService.currentProfile {
                                    ZStack {
                                        Circle()
                                            .fill(profile.gradient)
                                            .frame(width: 44, height: 44)
                                        Text(String(profile.displayName.prefix(1)))
                                            .font(MedxFont.rounded(18, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                    .shadow(color: profile.accentColor.opacity(0.35), radius: 8, x: 0, y: 4)
                                } else {
                                    Image(systemName: "person.crop.circle.fill")
                                        .font(.system(size: 36))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)

                        // Countdown Banner
                        CountdownWidgetView()
                            .padding(.horizontal, 20)

                        // Syllabus Tracker Shortcut Card
                        Button {
                            HapticManager.light()
                            showTrackerSheet = true
                        } label: {
                            HStack {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(MedxTheme.primaryBlue.opacity(0.15))
                                            .frame(width: 44, height: 44)
                                        Image(systemName: "list.clipboard.fill")
                                            .font(.headline)
                                            .foregroundColor(MedxTheme.primaryBlue)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Syllabus Checklist Matrix")
                                            .font(MedxFont.rounded(15, weight: .bold))
                                            .foregroundColor(.primary)
                                        Text("Track videos, revision cycles & PYQs")
                                            .font(MedxFont.rounded(12, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(16)
                            .liquidGlassCard(cornerRadius: 20, glowColor: MedxTheme.primaryBlue)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 20)

                        // QBank Progress Card
                        QBankProgressCard(attempts: attempts) {
                            onSelectTab(.qbank)
                        }
                        .padding(.horizontal, 20)

                        // Question of the Day
                        QuestionOfTheDayCard()
                            .padding(.horizontal, 20)
                            .padding(.bottom, 90)
                    }
                    .padding(.top, 6)
                }
                .refreshable {
                    await loadHomeData()
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showTrackerSheet) {
            if let uid = authService.currentSession?.uid {
                SyllabusTrackerSheet(uid: uid, trackerDoc: $trackerDoc)
            }
        }
        .task {
            await loadHomeData()
        }
    }

    private func loadHomeData() async {
        guard let uid = authService.currentSession?.uid else { return }
        do {
            let token = try await authService.getValidIdToken()
            async let attemptsTask = FirestoreService.shared.fetchUserAttempts(uid: uid, idToken: token)
            async let trackerTask = FirestoreService.shared.fetchUserTracker(uid: uid, idToken: token)

            let (att, trk) = try await (attemptsTask, trackerTask)
            self.attempts = att
            self.trackerDoc = trk
            self.isLoading = false
        } catch {
            self.isLoading = false
        }
    }
}
