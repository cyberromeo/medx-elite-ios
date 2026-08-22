import SwiftUI
import PhotosUI

public struct SettingsView: View {
    @ObservedObject var authService = AuthService.shared
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var avatars = AvatarStore.shared
    @ObservedObject private var downloads = VideoDownloadStore.shared
    @State private var attempts: [SittingAttempt] = []
    @State private var showSignOutConfirm = false
    @State private var showForgetCachedConfirm = false
    @State private var showDeleteDownloadsConfirm = false
    @State private var photoItem: PhotosPickerItem?
    @State private var cacheCleared = false
    @State private var cacheSize: String = "Calculating…"
    @State private var isManualSyncing = false
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                // MARK: - Current Profile
                if let profile = authService.currentProfile {
                    Section {
                        HStack(spacing: 16) {
                            ProfileAvatarView(profile: profile, size: 64)

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

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)

                        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                            Label {
                                Text(avatars.hasImage(for: profile.id) ? "Change Profile Photo" : "Add Profile Photo")
                                    .font(MedxFont.body(15))
                            } icon: {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .foregroundColor(MedxTheme.primaryBlue)
                            }
                            .frame(minHeight: 44)
                        }

                        if avatars.hasImage(for: profile.id) {
                            Button(role: .destructive) {
                                HapticManager.medium()
                                avatars.removeImage(for: profile.id)
                            } label: {
                                Label {
                                    Text("Remove Photo")
                                        .font(MedxFont.body(15))
                                } icon: {
                                    Image(systemName: "person.crop.circle.badge.xmark")
                                        .foregroundColor(MedxTheme.destructiveRed)
                                }
                                .frame(minHeight: 44)
                            }
                        }
                    } footer: {
                        Text("Your photo is stored only on this device.")
                            .font(MedxFont.caption(11))
                    }
                }

                // MARK: - Library & Study History
                Section("Library") {
                    NavigationLink {
                        DownloadsView()
                    } label: {
                        settingsRow(
                            title: "Offline Downloads",
                            icon: "arrow.down.circle.fill",
                            color: MedxTheme.successGreen,
                            value: "\(downloads.completedItems.count)"
                        )
                    }

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
                        ActivityLogView(
                            uid: authService.currentSession?.uid,
                            attempts: $attempts
                        )
                    } label: {
                        settingsRow(
                            title: "Activity Log",
                            icon: "list.bullet.rectangle.portrait.fill",
                            color: MedxTheme.cyanAccent,
                            value: "\(activityStore.watchHistory(for: authService.currentSession?.uid).count + attempts.count)"
                        )
                    }
                }

                // MARK: - Cloud Sync
                Section("Cloud Synchronization") {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Firebase Cloud Sync")
                                    .font(MedxFont.body(15))
                                if let lastSync = activityStore.lastSyncedAt {
                                    Text("Last synced \(RelativeDateTimeFormatter().localizedString(for: lastSync, relativeTo: Date()))")
                                        .font(MedxFont.caption(11))
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("Automatic sync on changes")
                                        .font(MedxFont.caption(11))
                                        .foregroundColor(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "cloud.fill")
                                .foregroundColor(MedxTheme.cyanAccent)
                        }

                        Spacer()

                        Button {
                            guard let uid = authService.currentSession?.uid else { return }
                            isManualSyncing = true
                            HapticManager.selection()
                            Task {
                                await activityStore.syncWithCloud(uid: uid)
                                await loadAttempts()
                                isManualSyncing = false
                                HapticManager.success()
                            }
                        } label: {
                            if isManualSyncing || activityStore.isSyncing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Sync Now")
                                    .font(MedxFont.label(12))
                                    .foregroundColor(MedxTheme.primaryBlue)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(MedxTheme.primaryBlue.opacity(0.12), in: Capsule())
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isManualSyncing || activityStore.isSyncing)
                    }
                }

                // MARK: - Storage
                Section("Storage") {
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Offline Videos")
                                    .font(MedxFont.body(15))
                                Text("\(downloads.completedItems.count) classes saved in the app")
                                    .font(MedxFont.caption(11))
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(MedxTheme.successGreen)
                        }
                        Spacer()
                        Text(downloads.formattedTotalSize)
                            .font(MedxFont.mono(13))
                            .foregroundColor(.secondary)
                    }

                    if !downloads.allItems.isEmpty {
                        Button(role: .destructive) {
                            showDeleteDownloadsConfirm = true
                        } label: {
                            Label {
                                Text("Delete All Downloads")
                                    .font(MedxFont.body(15))
                            } icon: {
                                Image(systemName: "trash")
                                    .foregroundColor(MedxTheme.destructiveRed)
                            }
                        }
                    }

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
                                Text("Clear Offline Cache")
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
                        Text("Swift Native iOS 17")
                            .font(MedxFont.caption(13))
                            .foregroundColor(.secondary)
                    }
                } footer: {
                    Text("MedX Elite · Built with SwiftUI & Apple HIG")
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
            .confirmationDialog("Delete All Downloads?", isPresented: $showDeleteDownloadsConfirm) {
                Button("Delete \(downloads.allItems.count) Downloads", role: .destructive) {
                    HapticManager.warning()
                    downloads.removeAll()
                }
            } message: {
                Text("This frees \(downloads.formattedTotalSize) on this device. Your watch progress is kept and you can download the classes again any time.")
            }
            .onChange(of: photoItem) { _, newItem in
                guard let newItem, let profileId = authService.currentProfile?.id else { return }
                Task { @MainActor in
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        AvatarStore.shared.setImage(data: data, for: profileId)
                        HapticManager.success()
                    }
                    photoItem = nil
                }
            }
            .task {
                if let uid = authService.currentSession?.uid {
                    await activityStore.syncWithCloud(uid: uid)
                }
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

// MARK: - Bookmarked Questions View

struct BookmarkedQuestionsView: View {
    let uid: String?
    @ObservedObject private var activityStore = ActivityStore.shared
    @State private var searchText = ""
    @State private var selectedSubject: String = "All"
    @State private var showClearAllConfirm = false
    @State private var practicePayload: RunnerPayload?

    init(uid: String?) {
        self.uid = uid
    }

    private var allBookmarks: [BookmarkedQuestion] {
        activityStore.bookmarks(for: uid)
    }

    private var availableSubjects: [String] {
        let list = Set(allBookmarks.map { $0.subject }.filter { !$0.isEmpty })
        return ["All"] + list.sorted()
    }

    private var filteredBookmarks: [BookmarkedQuestion] {
        allBookmarks.filter { bookmark in
            let matchesSubject = selectedSubject == "All" || bookmark.subject == selectedSubject
            let matchesSearch = searchText.isEmpty ||
                bookmark.previewText.localizedCaseInsensitiveContains(searchText) ||
                bookmark.sourceName.localizedCaseInsensitiveContains(searchText) ||
                bookmark.subject.localizedCaseInsensitiveContains(searchText)
            return matchesSubject && matchesSearch
        }
    }

    var body: some View {
        Group {
            if allBookmarks.isEmpty {
                ContentUnavailableView(
                    "No Bookmarks",
                    systemImage: "bookmark",
                    description: Text("Bookmark MCQs during a sitting session or review to revise them here.")
                )
            } else {
                List {
                    // Subject Filter Chips
                    if availableSubjects.count > 2 {
                        Section {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(availableSubjects, id: \.self) { subj in
                                        Button {
                                            HapticManager.selection()
                                            selectedSubject = subj
                                        } label: {
                                            Text(subj)
                                                .font(MedxFont.label(12))
                                                .foregroundColor(selectedSubject == subj ? .white : .primary)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(
                                                    selectedSubject == subj ? MedxTheme.primaryPurple : Color(uiColor: .tertiarySystemFill),
                                                    in: Capsule()
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }

                    Section {
                        ForEach(filteredBookmarks) { bookmark in
                            NavigationLink {
                                BookmarkedQuestionDetailView(bookmark: bookmark, uid: uid)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(bookmark.previewText)
                                        .font(.body)
                                        .lineLimit(3)

                                    HStack(spacing: 6) {
                                        if !bookmark.subject.isEmpty {
                                            Text(bookmark.subject)
                                                .font(MedxFont.mono(10, weight: .bold))
                                                .foregroundColor(MedxTheme.primaryPurple)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 2)
                                                .background(MedxTheme.primaryPurple.opacity(0.12), in: Capsule())
                                        }

                                        Text(bookmark.sourceName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)

                                        Spacer()

                                        Text(bookmark.formattedDate)
                                            .font(MedxFont.caption(11))
                                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    HapticManager.medium()
                                    activityStore.removeBookmark(bookmark, uid: uid)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text("\(filteredBookmarks.count) of \(allBookmarks.count) bookmarked questions")
                            .font(MedxFont.caption(12))
                    }
                }
                .searchable(text: $searchText, prompt: "Search bookmarks…")
            }
        }
        .navigationTitle("Bookmarks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !allBookmarks.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showClearAllConfirm = true
                        } label: {
                            Label("Clear All Bookmarks", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 44, height: 44)
                    }
                }
            }
        }
        .confirmationDialog(
            "Clear All Bookmarks?",
            isPresented: $showClearAllConfirm
        ) {
            Button("Clear All", role: .destructive) {
                HapticManager.medium()
                activityStore.clearAllBookmarks(uid: uid)
            }
        } message: {
            Text("This will remove all bookmarked questions locally and from your cloud account.")
        }
    }
}

// MARK: - Bookmarked Question Detail View

private struct BookmarkedQuestionDetailView: View {
    let bookmark: BookmarkedQuestion
    let uid: String?
    @ObservedObject private var activityStore = ActivityStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header meta badge
                HStack {
                    if !bookmark.subject.isEmpty {
                        Text(bookmark.subject)
                            .font(MedxFont.mono(11, weight: .bold))
                            .foregroundColor(MedxTheme.primaryPurple)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(MedxTheme.primaryPurple.opacity(0.12), in: Capsule())
                    }

                    Text(bookmark.sourceName)
                        .font(MedxFont.caption(12))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(bookmark.formattedDate)
                        .font(MedxFont.caption(11))
                        .foregroundColor(Color(uiColor: .tertiaryLabel))
                }

                // Question HTML display
                HTMLRichTextView(html: bookmark.question.displayText, fontSize: 17, weight: .semibold)

                // Images if any
                if let imgs = bookmark.question.images, !imgs.isEmpty {
                    ForEach(imgs, id: \.self) { imgUrl in
                        CachedAsyncImage(url: URL(string: imgUrl))
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                // Options with Answer Key
                VStack(spacing: 10) {
                    ForEach(bookmark.question.options) { option in
                        let isCorrect = bookmark.question.correctIds.contains(option.id) || option.correct == true

                        HStack(alignment: .center, spacing: 12) {
                            Text(option.label)
                                .font(MedxFont.mono(13, weight: .bold))
                                .foregroundColor(isCorrect ? .white : .primary)
                                .frame(width: 28, height: 28)
                                .background(isCorrect ? MedxTheme.successGreen : Color.primary.opacity(0.08))
                                .clipShape(Circle())

                            HTMLRichTextView(html: option.text, fontSize: 14, weight: .regular)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .layoutPriority(1)

                            Spacer(minLength: 0)

                            if isCorrect {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(MedxTheme.successGreen)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .center)
                        .background(isCorrect ? MedxTheme.successGreen.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(isCorrect ? MedxTheme.successGreen.opacity(0.4) : Color.clear, lineWidth: 1)
                        )
                    }
                }

                // Explanation
                if let explanation = bookmark.question.explanation, !explanation.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Explanation", systemImage: "lightbulb.fill")
                            .font(.headline)
                            .foregroundColor(MedxTheme.warningOrange)
                        HTMLRichTextView(html: explanation, fontSize: 15, weight: .regular, textColor: .secondary)
                    }
                    .padding(16)
                    .glassCard(cornerRadius: 16)
                }

                // Remove Bookmark Button
                Button(role: .destructive) {
                    HapticManager.medium()
                    activityStore.removeBookmark(bookmark, uid: uid)
                    dismiss()
                } label: {
                    Label("Remove Bookmark", systemImage: "bookmark.slash")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(MedxTheme.destructiveRed)
                .padding(.top, 10)
            }
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Question Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Watch History View

private struct WatchHistoryView: View {
    let uid: String?
    @ObservedObject private var activityStore = ActivityStore.shared
    @State private var activeVideo: RecordedVideo?
    @State private var showClearConfirm = false

    private var entries: [WatchHistoryEntry] {
        activityStore.watchHistory(for: uid)
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Watch History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Videos you start watching will automatically track your progress and resume position here.")
                )
            } else {
                List {
                    ForEach(entries) { entry in
                        Button {
                            activeVideo = entry.video
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(MedxTheme.primaryBlue.opacity(0.12))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(MedxTheme.primaryBlue)
                                }

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.video.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)

                                    HStack(spacing: 6) {
                                        Text(entry.video.subject)
                                            .font(MedxFont.caption(12))
                                            .foregroundStyle(.secondary)

                                        if let faculty = entry.video.faculty, !faculty.isEmpty {
                                            Text("· \(faculty)")
                                                .font(MedxFont.caption(12))
                                                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                        }

                                        Spacer()

                                        Text(entry.formattedDate)
                                            .font(MedxFont.caption(11))
                                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                    }

                                    ProgressView(value: entry.progress)
                                        .tint(entry.isCompleted ? MedxTheme.successGreen : MedxTheme.primaryBlue)

                                    HStack {
                                        if entry.isCompleted {
                                            Label("Completed", systemImage: "checkmark.circle.fill")
                                                .font(MedxFont.mono(11, weight: .bold))
                                                .foregroundColor(MedxTheme.successGreen)
                                        } else {
                                            Label("Resume at \(entry.formattedResumeTime)", systemImage: "arrow.counterclockwise.circle.fill")
                                                .font(MedxFont.mono(11, weight: .bold))
                                                .foregroundColor(MedxTheme.cyanAccent)
                                        }
                                        Spacer()
                                        Text("\(Int(entry.progress * 100))%")
                                            .font(MedxFont.mono(11))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                HapticManager.medium()
                                activityStore.removeWatchHistory(entry, uid: uid)
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
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Label("Clear All Watch History", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 44, height: 44)
                    }
                }
            }
        }
        .confirmationDialog(
            "Clear Watch History?",
            isPresented: $showClearConfirm
        ) {
            Button("Clear All", role: .destructive) {
                HapticManager.medium()
                activityStore.clearAllWatchHistory(uid: uid)
            }
        } message: {
            Text("This will clear your watch progress and resume positions for all videos locally and in the cloud.")
        }
        .fullScreenCover(item: $activeVideo) { video in
            VideoPlayerView(video: video) {
                activeVideo = nil
            }
        }
    }
}

// MARK: - Activity Log View (Unified Watch History & Test Attempts)

private struct ActivityLogView: View {
    let uid: String?
    @Binding var attempts: [SittingAttempt]
    @ObservedObject private var activityStore = ActivityStore.shared
    @State private var selectedFilter: LogFilter = .all
    @State private var searchText = ""
    @State private var pendingDeletion: ActivityLogItem?
    @State private var showClearOptions = false
    @State private var deletionError = false
    @State private var isDeleting = false

    enum LogFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case videos = "Videos"
        case qbank = "QBank"
        case tests = "Tests"

        var id: String { rawValue }
    }

    private var allItems: [ActivityLogItem] {
        let videoItems = activityStore.watchHistory(for: uid).map(ActivityLogItem.video)
        let attemptItems = attempts.map(ActivityLogItem.attempt)
        return (videoItems + attemptItems).sorted { $0.date > $1.date }
    }

    private var filteredItems: [ActivityLogItem] {
        allItems.filter { item in
            let matchesCategory: Bool
            switch selectedFilter {
            case .all:
                matchesCategory = true
            case .videos:
                if case .video = item { matchesCategory = true } else { matchesCategory = false }
            case .qbank:
                if case .attempt(let att) = item, att.kind != "test" { matchesCategory = true } else { matchesCategory = false }
            case .tests:
                if case .attempt(let att) = item, att.kind == "test" { matchesCategory = true } else { matchesCategory = false }
            }

            let matchesSearch = searchText.isEmpty ||
                item.title.localizedCaseInsensitiveContains(searchText) ||
                item.subtitle.localizedCaseInsensitiveContains(searchText)

            return matchesCategory && matchesSearch
        }
    }

    var body: some View {
        Group {
            if allItems.isEmpty {
                ContentUnavailableView(
                    "No Activity Log",
                    systemImage: "list.bullet.rectangle.portrait",
                    description: Text("Your video watch history and QBank/test attempts will appear in this unified log.")
                )
            } else {
                List {
                    // Filter picker
                    Section {
                        Picker("Filter Activity", selection: $selectedFilter) {
                            ForEach(LogFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 2)
                    }

                    Section {
                        ForEach(filteredItems) { item in
                            HStack(spacing: 14) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(item.color)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.headline)
                                        .lineLimit(2)

                                    Text(item.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    Text(item.formattedDate)
                                        .font(MedxFont.caption(11))
                                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                }

                                Spacer()

                                Button(role: .destructive) {
                                    pendingDeletion = item
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.secondary)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Delete \(item.title)")
                            }
                            .padding(.vertical, 4)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    pendingDeletion = item
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text("\(filteredItems.count) activity entries")
                            .font(MedxFont.caption(12))
                    }
                }
                .searchable(text: $searchText, prompt: "Search activity log…")
            }
        }
        .navigationTitle("Activity Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !allItems.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            activityStore.clearAllWatchHistory(uid: uid)
                        } label: {
                            Label("Clear Watch History", systemImage: "play.slash")
                        }

                        Button(role: .destructive) {
                            Task {
                                await clearAllAttempts()
                            }
                        } label: {
                            Label("Clear All Test Attempts", systemImage: "doc.badge.gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 44, height: 44)
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete Activity Entry?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { item in
            Button("Delete", role: .destructive) {
                deleteItem(item)
            }
        } message: { item in
            Text(item.deleteMessage)
        }
        .alert("Failed to Delete", isPresented: $deletionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Could not delete from cloud. Please check your internet connection and try again.")
        }
    }

    private func deleteItem(_ item: ActivityLogItem) {
        switch item {
        case .video(let entry):
            activityStore.removeWatchHistory(entry, uid: uid)
            HapticManager.success()

        case .attempt(let attempt):
            Task {
                do {
                    let token = try await AuthService.shared.getValidIdToken()
                    try await FirestoreService.shared.deleteAttempt(attempt, idToken: token)
                    withAnimation {
                        attempts.removeAll { $0.id == attempt.id || ($0.sourceId == attempt.sourceId && $0.finishedAt == attempt.finishedAt) }
                    }
                    HapticManager.success()
                } catch {
                    deletionError = true
                }
            }
        }
        pendingDeletion = nil
    }

    private func clearAllAttempts() async {
        guard let token = try? await AuthService.shared.getValidIdToken() else { return }
        for att in attempts {
            try? await FirestoreService.shared.deleteAttempt(att, idToken: token)
        }
        withAnimation {
            attempts.removeAll()
        }
        HapticManager.success()
    }
}

// MARK: - Activity Log Item Wrapper

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
            let status = entry.isCompleted ? "Watched" : "Resume at \(entry.formattedResumeTime)"
            return "\(entry.video.subject) · \(status) (\(Int(entry.progress * 100))%)"
        case .attempt(let attempt):
            let kind = attempt.kind == "test" ? "Test" : "QBank"
            let mode = attempt.mode == "exam" ? "Exam" : "Revision"
            return "\(kind) (\(mode)) · Score: \(attempt.score)/\(attempt.total) (\(attempt.totalPercentage)%)"
        }
    }

    var formattedDate: String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    var deleteMessage: String {
        switch self {
        case .video: return "Deleting this log entry will delete the watch history and clear its resume position both locally and in Firebase."
        case .attempt: return "Deleting this log entry will permanently remove the test/QBank attempt record locally and in Firebase."
        }
    }
}
