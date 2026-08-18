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
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 18) {
                    // MARK: - iOS Native Date & Greeting Hero Header
                    greetingHeroHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 2)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 8)

                    // MARK: - Countdown Widget (Liquid Glass)
                    CountdownWidgetView()
                        .padding(.horizontal, 20)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 12)

                    // MARK: - Syllabus Tracker (Liquid Glass Card)
                    syllabusTrackerCard
                        .padding(.horizontal, 20)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 16)

                    // MARK: - Performance Analytics (Swift Charts + Liquid Glass)
                    AnalyticsCard(attempts: attempts)
                        .padding(.horizontal, 20)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 20)

                    // MARK: - QBank Progress (Liquid Glass Card)
                    QBankProgressCard(attempts: attempts) {}
                        .padding(.horizontal, 20)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 24)

                    // MARK: - Question of the Day (Liquid Glass Card)
                    QuestionOfTheDayCard()
                        .padding(.horizontal, 20)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 28)

                    Spacer(minLength: 40)
                }
            }
        }
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                profileButton
            }
        }
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
        .task {
            await loadHomeData()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Ambient Fluid Background Canvas

    private var ambientBackgroundCanvas: some View {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
    }

    // MARK: - Greeting Hero Header (Native iOS Style)

    private var greetingHeroHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                    .font(MedxFont.mono(11, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(0.8)

                HStack(spacing: 6) {
                    Text(greetingText + ",")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)

                    if let profile = authService.currentProfile {
                        Text(profile.displayName)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
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
                            .fill(Color(uiColor: .tertiarySystemFill))
                            .frame(width: 36, height: 36)
                            .overlay(Circle().strokeBorder(Color(uiColor: .separator), lineWidth: 0.6))

                        Text(String(profile.displayName.prefix(1)).uppercased())
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(profile.accentColor)
                    }
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("Profile settings")
        .accessibilityHint("Opens account and app settings")
    }

    // MARK: - Syllabus Tracker Card

    private var syllabusTrackerCard: some View {
        Button {
            showTrackerSheet = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(MedxTheme.primaryBlue.opacity(0.14))
                        .frame(width: 46, height: 46)
                    Image(systemName: "list.clipboard.fill")
                        .font(.system(size: 19, weight: .semibold))
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
                    .foregroundColor(Color(uiColor: .tertiaryLabel))
            }
            .padding(16)
            .medxNavigationGlass(cornerRadius: 20, tint: MedxTheme.primaryBlue)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityLabel("Open syllabus checklist")
        .accessibilityHint("Tracks videos, revision cycles, and previous-year questions")
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
