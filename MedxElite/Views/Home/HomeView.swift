import SwiftUI

public struct HomeView: View {
    @ObservedObject var authService = AuthService.shared
    @State private var attempts: [SittingAttempt] = []
    @State private var trackerDoc: UserTrackerDoc?
    @State private var isLoading = true
    @State private var showSettings = false
    @State private var showTrackerSheet = false

    public init() {}

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 5 { return "Still up" }
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    public var body: some View {
        List {
            // Greeting header
            Section {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(greetingText),")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if let profile = authService.currentProfile {
                            Text(profile.displayName)
                                .font(.system(.title, design: .rounded, weight: .bold))
                                .foregroundStyle(profile.gradient)
                        }
                    }

                    Spacer()

                    Button {
                        showSettings = true
                    } label: {
                        if let profile = authService.currentProfile {
                            ZStack {
                                Circle()
                                    .fill(profile.gradient)
                                    .frame(width: 40, height: 40)
                                Text(String(profile.displayName.prefix(1)))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
            }

            // Countdown
            Section {
                CountdownWidgetView()
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            // Syllabus Tracker
            Section {
                Button {
                    showTrackerSheet = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Syllabus Checklist Matrix")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("Track videos, revision cycles & PYQs")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "list.clipboard.fill")
                            .foregroundColor(.accentColor)
                    }
                }
            }

            // QBank Progress
            Section {
                QBankProgressCard(attempts: attempts) {}
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            // Question of the Day
            Section {
                QuestionOfTheDayCard()
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
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
