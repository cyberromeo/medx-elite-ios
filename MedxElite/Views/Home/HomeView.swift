import SwiftUI

public struct HomeView: View {
    @ObservedObject var authService = AuthService.shared
    @State private var attempts: [SittingAttempt] = []
    @State private var trackerDoc: UserTrackerDoc?
    @State private var isLoading = true
    @State private var showSettings = false
    @State private var showTrackerSheet = false
    @State private var hasAppeared = false

    public init() {}

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 5 { return "Still up" }
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    public var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // MARK: - Greeting Header
                greetingHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 10)

                // MARK: - Countdown Widget
                CountdownWidgetView()
                    .padding(.horizontal, 20)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 15)

                // MARK: - Syllabus Tracker
                syllabusTrackerCard
                    .padding(.horizontal, 20)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 20)

                // MARK: - QBank Progress
                QBankProgressCard(attempts: attempts) {}
                    .padding(.horizontal, 20)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 25)

                // MARK: - Question of the Day
                QuestionOfTheDayCard()
                    .padding(.horizontal, 20)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 30)

                Spacer(minLength: 40)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Home")
        .refreshable {
            await loadHomeData()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showTrackerSheet) {
            if let uid = authService.currentSession?.uid {
                SyllabusTrackerSheet(uid: uid, trackerDoc: $trackerDoc)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                profileButton
            }
        }
        .task {
            await loadHomeData()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Greeting Header

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(greetingText),")
                .font(MedxFont.body(16))
                .foregroundColor(.secondary)

            if let profile = authService.currentProfile {
                Text(profile.displayName)
                    .font(MedxFont.hero(32))
                    .foregroundStyle(profile.gradient)
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Profile Button

    private var profileButton: some View {
        Button {
            showSettings = true
        } label: {
            if let profile = authService.currentProfile {
                ZStack {
                    Circle()
                        .fill(profile.gradient)
                        .frame(width: 34, height: 34)
                    Text(String(profile.displayName.prefix(1)))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Syllabus Tracker Card

    private var syllabusTrackerCard: some View {
        Button {
            showTrackerSheet = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(MedxTheme.primaryBlue.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "list.clipboard.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(MedxTheme.primaryBlue)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Syllabus Checklist Matrix")
                        .font(MedxFont.headline(16))
                        .foregroundColor(.primary)
                    Text("Track videos, revision cycles & PYQs")
                        .font(MedxFont.caption(13))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(16)
            .liquidGlassCard(cornerRadius: 18)
        }
        .buttonStyle(BouncyButtonStyle())
    }

    // MARK: - Data Loading

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
