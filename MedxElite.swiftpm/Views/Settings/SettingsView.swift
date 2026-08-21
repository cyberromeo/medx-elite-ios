import SwiftUI

public struct SettingsView: View {
    @ObservedObject var authService = AuthService.shared
    @ObservedObject private var activityStore = ActivityStore.shared
    @State private var attempts: [SittingAttempt] = []
    @State private var showSignOutConfirm = false
    @State private var showForgetCachedConfirm = false
    @State private var cacheCleared = false
    @State private var cacheSize: String = "Calculating…"
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                // MARK: - Current Profile
                if let profile = authService.currentProfile {
                    Section {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .strokeBorder(profile.gradient, lineWidth: 2)
                                    .frame(width: 64, height: 64)

                                Circle()
                                    .fill(profile.gradient)
                                    .frame(width: 56, height: 56)

                                Text(String(profile.displayName.prefix(1)))
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundColor(.white)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.displayName)
                                    .font(MedxFont.headline(18))
                                Text("@\(profile.handle)")
                                    .font(MedxFont.caption(14))
                                    .foregroundColor(.secondary)
                                Text(profile.email)
                                    .font(MedxFont.caption(12))
                                    .foregroundColor(Color(uiColor: .tertiaryLabel))
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section("Library") {
                    NavigationLink {
                        BookmarkedQuestionsView(uid: authService.currentSession?.uid)
                    } label: {
                        settingsRow(
                            title: "Bookmarked Questions",
                            icon: "bookmark.fill",
                            color: MedxTheme.primaryPurple,
                            value: "\(activityStore.bookmarks(for: authService.currentSession?.uid).count)"
                        )
                    }

                    NavigationLink {
                        WatchHistoryView(uid: authService.currentSession?.uid)
                    } label: {
                        settingsRow(
                            title: "Watch History",
                            icon: "clock.arrow.circlepath",
                            color: MedxTheme.primaryBlue,
                            value: "\(activityStore.watchHistory(for: authService.currentSession?.uid).count)"
                        )
                    }

                    NavigationLink {
                        ActivityLogView(uid: authService.currentSession?.uid, attempts: attempts)
                    } label: {
                        settingsRow(
                            title: "Activity Log",
                            icon: "list.bullet.rectangle.portrait.fill",
                            color: MedxTheme.cyanAccent,
                            value: "\(activityStore.watchHistory(for: authService.currentSession?.uid).count + attempts.count)"
                        )
                    }
                }

                // MARK: - Storage
                Section("Storage") {
                    HStack {
                        Label {
                            Text("Offline Cache")
                                .font(MedxFont.body(15))
                        } icon: {
                            Image(systemName: "internaldrive.fill")
                                .foregroundColor(MedxTheme.primaryBlue)
                        }
                        Spacer()
                        Text(cacheSize)
                            .font(MedxFont.mono(13))
                            .foregroundColor(.secondary)
                    }

                    Button {
                        Task {
                            await CacheManager.shared.clearAll()
                            HapticManager.success()
                            withAnimation {
                                cacheCleared = true
                                cacheSize = "0 KB"
                            }
                        }
                    } label: {
                        HStack {
                            Label {
                                Text("Clear Cache")
                                    .font(MedxFont.body(15))
                            } icon: {
                                Image(systemName: "trash")
                                    .foregroundColor(MedxTheme.warningOrange)
                            }
                            Spacer()
                            if cacheCleared {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(MedxTheme.successGreen)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                }

                // MARK: - Account Actions
                Section("Account") {
                    Button(role: .destructive) {
                        showSignOutConfirm = true
                    } label: {
                        Label {
                            Text("Sign Out")
                                .font(MedxFont.body(15))
                        } icon: {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(MedxTheme.destructiveRed)
                        }
                    }

                    if let profile = authService.currentProfile, authService.hasSavedPassword(for: profile.id) {
                        Button(role: .destructive) {
                            showForgetCachedConfirm = true
                        } label: {
                            Label {
                                Text("Sign Out & Forget Password")
                                    .font(MedxFont.body(15))
                            } icon: {
                                Image(systemName: "key.slash")
                                    .foregroundColor(MedxTheme.destructiveRed)
                            }
                        }
                    }
                }

                // MARK: - App Info
                Section {
                    HStack {
                        Label {
                            Text("Version")
                                .font(MedxFont.body(15))
                        } icon: {
                            Image(systemName: "info.circle.fill")
                                .foregroundColor(MedxTheme.cyanAccent)
                        }
                        Spacer()
                        Text("1.0.0")
                            .font(MedxFont.mono(13))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label {
                            Text("Platform")
                                .font(MedxFont.body(15))
                        } icon: {
                            Image(systemName: "swift")
                                .foregroundColor(MedxTheme.warningOrange)
                        }
                        Spacer()
                        Text("Swift Native")
                            .font(MedxFont.caption(13))
                            .foregroundColor(.secondary)
                    }
                } footer: {
                    Text("MedX Elite · Built with SwiftUI")
                        .font(MedxFont.caption(11))
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(MedxFont.headline(16))
                }
            }
            .confirmationDialog("Sign Out?", isPresented: $showSignOutConfirm) {
                Button("Sign Out", role: .destructive) {
                    HapticManager.light()
                    authService.signOut()
                    dismiss()
                }
            } message: {
                Text("You can sign back in easily using your saved profile.")
            }
            .confirmationDialog("Forget Saved Password?", isPresented: $showForgetCachedConfirm) {
                Button("Forget & Sign Out", role: .destructive) {
                    if let pid = authService.currentProfile?.id {
                        authService.forgetPassword(for: pid)
                    }
                    authService.signOut()
                    dismiss()
                }
            } message: {
                Text("This will remove your saved password from this device's Keychain.")
            }
            .task {
                await loadAttempts()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    private func settingsRow(title: String, icon: String, color: Color, value: String) -> some View {
        HStack {
            Label {
                Text(title)
                    .font(MedxFont.body(15))
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(color)
            }
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(minHeight: 44)
    }

    private func loadAttempts() async {
        guard let uid = authService.currentSession?.uid else { return }
        do {
            let token = try await authService.getValidIdToken()
            attempts = try await FirestoreService.shared.fetchUserAttempts(uid: uid, idToken: token)
        } catch {
            attempts = []
        }
    }
}

private struct BookmarkedQuestionsView: View {
    let uid: String?
    @ObservedObject private var activityStore = ActivityStore.shared

    private var bookmarks: [BookmarkedQuestion] {
        activityStore.bookmarks(for: uid).sorted { $0.bookmarkedAt > $1.bookmarkedAt }
    }

    var body: some View {
        Group {
            if bookmarks.isEmpty {
                ContentUnavailableView(
                    "No Bookmarks",
                    systemImage: "bookmark",
                    description: Text("Bookmark an MCQ from the question runner to find it here.")
                )
            } else {
                List {
                    ForEach(bookmarks) { bookmark in
                        NavigationLink {
                            BookmarkedQuestionDetailView(bookmark: bookmark)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(bookmark.previewText)
                                    .font(.body)
                                    .lineLimit(3)
                                Text([bookmark.subject, bookmark.sourceName].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 5)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                activityStore.removeBookmark(bookmark)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Bookmarks")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BookmarkedQuestionDetailView: View {
    let bookmark: BookmarkedQuestion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(bookmark.sourceName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HTMLRichTextView(html: bookmark.question.displayText, fontSize: 17, weight: .semibold)

                ForEach(bookmark.question.options) { option in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: bookmark.question.correctIds.contains(option.id) || option.correct == true ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(bookmark.question.correctIds.contains(option.id) || option.correct == true ? MedxTheme.successGreen : Color.secondary)
                        Text("\(option.label). \(option.text)")
                            .font(.body)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if let explanation = bookmark.question.explanation, !explanation.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Explanation", systemImage: "lightbulb.fill")
                            .font(.headline)
                        HTMLRichTextView(html: explanation, fontSize: 15, weight: .regular, textColor: .secondary)
                    }
                    .padding(16)
                    .glassCard(cornerRadius: 16)
                }
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Question")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WatchHistoryView: View {
    let uid: String?
    @ObservedObject private var activityStore = ActivityStore.shared
    @State private var activeVideo: RecordedVideo?

    private var entries: [WatchHistoryEntry] {
        activityStore.watchHistory(for: uid)
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Watch History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Videos you start watching will appear here.")
                )
            } else {
                List {
                    ForEach(entries) { entry in
                        Button {
                            activeVideo = entry.video
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.video.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                        Text(entry.video.subject)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(MedxTheme.primaryBlue)
                                }
                                ProgressView(value: entry.progress)
                                    .tint(MedxTheme.primaryBlue)
                                Text(entry.progress >= 0.98 ? "Watched" : "Resume at \(formatTime(entry.positionSeconds))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                activityStore.removeWatchHistory(entry)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Watch History")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $activeVideo) { video in
            VideoPlayerView(video: video) {
                activeVideo = nil
            }
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = max(Int(seconds), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct ActivityLogView: View {
    let uid: String?
    @State private var attempts: [SittingAttempt]
    @ObservedObject private var activityStore = ActivityStore.shared
    @State private var pendingDeletion: ActivityLogItem?
    @State private var deletionError = false

    init(uid: String?, attempts: [SittingAttempt]) {
        self.uid = uid
        _attempts = State(initialValue: attempts)
    }

    private var items: [ActivityLogItem] {
        let videoItems = activityStore.watchHistory(for: uid).map(ActivityLogItem.video)
        let attemptItems = attempts.map(ActivityLogItem.attempt)
        return (videoItems + attemptItems).sorted { $0.date > $1.date }
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView("No Activity", systemImage: "list.bullet.rectangle.portrait")
            } else {
                List {
                    ForEach(items) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .foregroundStyle(item.color)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.body)
                                    .lineLimit(2)
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                pendingDeletion = item
                            } label: {
                                Image(systemName: "trash")
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete activity")
                        }
                        .frame(minHeight: 52)
                    }
                }
            }
        }
        .navigationTitle("Activity Log")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete Activity?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { item in
            Button("Delete", role: .destructive) {
                delete(item)
            }
        } message: { item in
            Text(item.deleteMessage)
        }
        .alert("Couldn’t Delete Activity", isPresented: $deletionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection and try again.")
        }
    }

    private func delete(_ item: ActivityLogItem) {
        switch item {
        case .video(let entry):
            activityStore.removeWatchHistory(entry)
            HapticManager.success()
        case .attempt(let attempt):
            Task {
                do {
                    let token = try await AuthService.shared.getValidIdToken()
                    try await FirestoreService.shared.deleteAttempt(attempt, idToken: token)
                    attempts.removeAll { $0.id == attempt.id }
                    HapticManager.success()
                } catch {
                    deletionError = true
                }
            }
        }
        pendingDeletion = nil
    }
}

private enum ActivityLogItem: Identifiable, Hashable {
    case video(WatchHistoryEntry)
    case attempt(SittingAttempt)

    var id: String {
        switch self {
        case .video(let entry): return "video-\(entry.ownerId)-\(entry.id)"
        case .attempt(let attempt): return "attempt-\(attempt.id ?? attempt.sourceId + (attempt.finishedAt ?? ""))"
        }
    }

    var date: Date {
        switch self {
        case .video(let entry): return entry.watchedAt
        case .attempt(let attempt): return attempt.finishedAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? .distantPast
        }
    }

    var icon: String {
        switch self {
        case .video: return "play.rectangle.fill"
        case .attempt(let attempt): return attempt.kind == "test" ? "doc.text.fill" : "questionmark.square.fill"
        }
    }

    var color: Color {
        switch self {
        case .video: return MedxTheme.primaryBlue
        case .attempt(let attempt): return attempt.kind == "test" ? MedxTheme.primaryPurple : MedxTheme.cyanAccent
        }
    }

    var title: String {
        switch self {
        case .video(let entry): return entry.video.title
        case .attempt(let attempt): return attempt.name
        }
    }

    var subtitle: String {
        switch self {
        case .video(let entry):
            return "Video · \(Int(entry.progress * 100))% watched"
        case .attempt(let attempt):
            let kind = attempt.kind == "test" ? "Test attempt" : "QBank attempt"
            return "\(kind) · \(attempt.attempted)/\(attempt.total) answered"
        }
    }

    var deleteMessage: String {
        switch self {
        case .video: return "This removes the video from Watch History and clears its resume position."
        case .attempt: return "This permanently deletes the saved QBank or test attempt."
        }
    }
}
