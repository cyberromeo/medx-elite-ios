import SwiftUI

public struct VideosBatchListView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var downloads = VideoDownloadStore.shared

    @State private var videos: [RecordedVideo] = []
    @State private var groups: [VideoBatchGroup] = []
    @State private var loadState: MedxLoadState = .loading
    @State private var searchText = ""
    @State private var activeVideo: RecordedVideo?

    public init() {}

    private var uid: String? { authService.currentSession?.uid }

    public var body: some View {
        Group {
            switch loadState {
            case .loading:
                loadingState
            case .failed(let message):
                ContentUnavailableView {
                    Label {
                        Text("Couldn't Load Classes")
                    } icon: {
                        Image(systemName: "play.rectangle")
                    }
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") {
                        HapticManager.light()
                        loadState = .loading
                        Task { await loadVideos() }
                    }
                    .medxFilledButton()
                    .buttonBorderShape(.capsule)
                }
            case .loaded:
                if videos.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("No Classes")
                        } icon: {
                            Image(systemName: "play.rectangle")
                        }
                    } description: {
                        Text("Recorded classes will appear here once they are published.")
                    }
                } else {
                    content
                }
            }
        }
                .navigationTitle("Classes")
        // Large, and the only "Classes" on the page — there used to be an inline title *and* a
        // `MedxPageHeader` under it saying the same word.
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    DownloadsView()
                } label: {
                    downloadsToolbarIcon
                }
                .accessibilityLabel("Downloads")
            }

            ToolbarItem(placement: .topBarTrailing) {
                MedxSettingsMonogram()
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search classes"
        )
        .task {
            guard case .loading = loadState else { return }
            await loadVideos()
        }
        .onChange(of: searchText) { _, _ in
            regroup()
        }
        .fullScreenCover(item: $activeVideo) { video in
            VideoPlayerView(video: video) { activeVideo = nil }
        }
    }

    // MARK: - Content

    private var content: some View {
        List {
            heroSection
            continueWatchingSection

            if groups.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Matches", systemImage: "magnifyingglass")
                    } description: {
                        Text("No class matches “\(searchText)”.")
                    }
                    .medxPlainRow()
                }
            } else {
                ForEach(groups) { batch in
                    batchSection(batch)
                }
            }
        }
        .medxList()
        .refreshable {
            await loadVideos()
        }
    }

    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(videos.count)")
                    .font(MedxType.display)
                    .contentTransition(.numericText())

                Text("recorded classes · \(totalDurationFormatted) · \(downloads.completedItems.count) offline")
                    .medxTag()
            }
            .medxPlainRow()
        }
    }

    private func batchSection(_ batch: VideoBatchGroup) -> some View {
        Section {
            ForEach(batch.subjects) { subject in
                NavigationLink {
                    VideoSubjectView(subjectGroup: subject)
                } label: {
                    subjectRow(subject)
                }
                .medxListRow()
                .contextMenu {
                    ForEach(DownloadQuality.allCases) { quality in
                        Button {
                            HapticManager.light()
                            downloads.startAll(subject.videos, quality: quality)
                        } label: {
                            Label("Save all · \(quality.label)", systemImage: quality.icon)
                        }
                    }
                }
            }
        } header: {
            MedxHeader(batch.name, count: batch.totalClasses)
        }
    }

    private func subjectRow(_ subject: VideoSubjectGroup) -> some View {
        let offline = subject.videos.filter { downloads.items[$0.id]?.state == .completed }.count

        return MedxRow(
            lead: "\(subject.totalClasses)",
            title: subject.name,
            tag: offline > 0 ? "\(offline) offline" : nil,
            detail: subject.formattedDuration
        )
        .accessibilityValue("\(subject.totalClasses) classes, \(subject.formattedDuration)")
    }

    /// Three rows, not a shelf of six cards.
    ///
    /// This was a horizontal `ScrollView` of 196×152 cards, which is a second scroll direction inside a
    /// vertical one and six more live subtrees to keep alive. Three rows in a section carry the same
    /// information — what you were watching, how far in — and a `List` can reuse them.
    @ViewBuilder
    private var continueWatchingSection: some View {
        let entries = Array(activityStore.watchHistory(for: uid).prefix(3))
        if !entries.isEmpty {
            Section {
                ForEach(entries) { entry in
                    continueRow(entry)
                }
            } header: {
                MedxHeader("Continue watching")
            }
        }
    }

    private func continueRow(_ entry: WatchHistoryEntry) -> some View {
        Button {
            HapticManager.light()
            activeVideo = entry.video
        } label: {
            MedxRow(
                lead: entry.isCompleted ? "✓" : "▶",
                title: entry.video.title,
                tag: downloads.items[entry.video.id]?.state == .completed ? "offline" : nil,
                detail: entry.isCompleted ? "Completed" : "Resume at \(entry.formattedResumeTime)"
            ) {
                MedxAnswerSheet(
                    fraction: entry.progress,
                    label: "\(Int(entry.progress * 100)) percent watched"
                )
            }
        }
        .buttonStyle(.plain)
        .medxListRow()
        .contextMenu {
            Button(role: .destructive) {
                activityStore.removeWatchHistory(entry, uid: uid)
            } label: {
                Label("Remove from history", systemImage: "trash")
            }
        }
    }

    /// Toolbar entry point for the offline library. The dot appears while anything is still fetching.
    private var downloadsToolbarIcon: some View {
        Image(systemName: downloads.completedItems.isEmpty ? "arrow.down.circle" : "arrow.down.circle.fill")
            .font(.system(size: 17, weight: .semibold))
            .overlay(alignment: .topTrailing) {
                if downloads.activeCount > 0 {
                    Circle()
                        .fill(MedxDS.warn)
                        .frame(width: 8, height: 8)
                        .offset(x: 3, y: -1)
                }
            }
            .frame(width: 40, height: 40)
    }

    private var loadingState: some View {
        List {
            ForEach(0..<7, id: \.self) { _ in
                MedxRow(lead: "12", title: "Subject name", detail: "12 classes · 8h 40m")
                    .medxListRow()
            }
        }
        .medxList()
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityLabel("Loading classes")
    }

    private var totalDurationFormatted: String {
        let total = videos.compactMap(\.durationSeconds).reduce(0, +)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }

    // MARK: - Data

    private func loadVideos() async {
        do {
            let token = try await authService.getValidIdToken()
            videos = try await FirestoreService.shared.fetchVideos(idToken: token)
            regroup()
            loadState = .loaded
        } catch {
            loadState = videos.isEmpty
                ? .failed("Check your connection and try again.")
                : .loaded
        }
    }

    /// Grouping walks every class, so it runs when the data or the query changes rather
    /// than on every `body` evaluation.
    private func regroup() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = query.isEmpty ? videos : videos.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.subject.localizedCaseInsensitiveContains(query)
                || ($0.faculty ?? "").localizedCaseInsensitiveContains(query)
                || ($0.batch ?? "").localizedCaseInsensitiveContains(query)
        }

        var batchOrder: [String] = []
        var batchNames: [String: String] = [:]
        var subjectOrder: [String: [String]] = [:]
        var subjectNames: [String: String] = [:]
        var bucket: [String: [RecordedVideo]] = [:]

        for video in matching {
            let batchId = video.batchId ?? "default"
            let subjectId = video.subjectId ?? video.subject
            let key = "\(batchId)|\(subjectId)"

            if batchNames[batchId] == nil {
                batchNames[batchId] = video.batch ?? "Batch"
                batchOrder.append(batchId)
            }
            if subjectNames[key] == nil {
                subjectNames[key] = video.subject
                subjectOrder[batchId, default: []].append(subjectId)
            }
            bucket[key, default: []].append(video)
        }

        groups = batchOrder.map { batchId in
            let subjects = (subjectOrder[batchId] ?? []).compactMap { subjectId -> VideoSubjectGroup? in
                let key = "\(batchId)|\(subjectId)"
                guard let items = bucket[key] else { return nil }
                return VideoSubjectGroup(
                    subjectId: subjectId,
                    name: subjectNames[key] ?? items.first?.subject ?? "Subject",
                    totalSeconds: items.compactMap(\.durationSeconds).reduce(0, +),
                    totalClasses: items.count,
                    videos: items
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            return VideoBatchGroup(
                batchId: batchId,
                name: batchNames[batchId] ?? "Batch",
                totalSeconds: subjects.reduce(0) { $0 + $1.totalSeconds },
                totalClasses: subjects.reduce(0) { $0 + $1.totalClasses },
                subjects: subjects
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Download control

/// One compact control covering every download state: save, pause, resume, retry, delete.
/// Used in the subject list, the offline library, and anywhere else a class row appears.
struct VideoDownloadButton: View {
    let video: RecordedVideo
    var diameter: CGFloat = 32

    @ObservedObject private var downloads = VideoDownloadStore.shared

    private var item: DownloadedVideo? { downloads.items[video.id] }

    var body: some View {
        Menu {
            menuItems
        } label: {
            glyph
        }
        .accessibilityLabel("Offline download for \(video.title)")
        .accessibilityValue(item?.statusLabel ?? "Not downloaded")
    }

    @ViewBuilder
    private var menuItems: some View {
        if let item {
            Section(item.statusLabel) {
                switch item.state {
                case .queued, .downloading:
                    Button {
                        HapticManager.light()
                        downloads.pause(video.id)
                    } label: {
                        Label("Pause", systemImage: "pause.circle")
                    }
                    Button(role: .destructive) {
                        downloads.remove(video.id)
                    } label: {
                        Label("Cancel download", systemImage: "xmark.circle")
                    }
                case .paused:
                    Button {
                        HapticManager.light()
                        downloads.resume(video.id)
                    } label: {
                        Label("Resume", systemImage: "play.circle")
                    }
                    Button(role: .destructive) {
                        downloads.remove(video.id)
                    } label: {
                        Label("Discard partial download", systemImage: "trash")
                    }
                case .failed:
                    Button {
                        HapticManager.light()
                        downloads.resume(video.id)
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        downloads.remove(video.id)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                case .completed:
                    Button(role: .destructive) {
                        HapticManager.warning()
                        downloads.remove(video.id)
                    } label: {
                        Label("Delete download", systemImage: "trash")
                    }
                }
            }
        } else {
            Section("Save on this device") {
                ForEach(DownloadQuality.allCases) { quality in
                    Button {
                        HapticManager.light()
                        downloads.start(video, quality: quality)
                    } label: {
                        Label(quality.label, systemImage: quality.icon)
                    }
                }
            }
        }
    }

    private var glyph: some View {
        ZStack {
            Circle()
                .fill(MedxDS.sunken)
                .frame(width: diameter, height: diameter)

            stateGlyph
        }
        .frame(width: 44, height: 44)
        .contentShape(Circle())
    }

    @ViewBuilder
    private var stateGlyph: some View {
        if let item {
            switch item.state {
            case .queued:
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
            case .downloading:
                ZStack {
                    Circle()
                        .stroke(MedxTheme.accent.opacity(0.2), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: max(0.03, item.progress))
                        .stroke(MedxTheme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(MedxTheme.accent)
                        .frame(width: 7, height: 7)
                }
                .frame(width: diameter - 9, height: diameter - 9)
                .animation(.easeOut(duration: 0.25), value: item.progress)
            case .paused:
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(MedxTheme.accent)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MedxDS.warn)
            case .completed:
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(MedxDS.correct)
            }
        } else {
            Image(systemName: "arrow.down.to.line")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(MedxTheme.accent)
        }
    }
}

// MARK: - Offline library

/// Browse and manage everything saved on this device. Files live in the app's own
/// container — nothing is exported to Files or Photos.
struct DownloadsView: View {
    @ObservedObject private var downloads = VideoDownloadStore.shared
    @State private var activeVideo: RecordedVideo?
    @State private var confirmDeleteAll = false

    private var inProgress: [DownloadedVideo] { downloads.inProgressItems }
    private var finished: [DownloadedVideo] { downloads.completedItems }

    var body: some View {
        Group {
            if downloads.items.isEmpty {
                ContentUnavailableView {
                    Label("No Downloads Yet", systemImage: "arrow.down.circle")
                } description: {
                    Text("Tap the download icon on any class to keep it on this device. Downloads play inside the app, even with no signal.")
                }
            } else {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(downloads.formattedTotalSize)
                                .font(MedxType.display)
                                .contentTransition(.numericText())

                            HStack(alignment: .top, spacing: 10) {
                                MedxStat("\(finished.count)", label: "ready", tint: MedxDS.correct)
                                MedxStat("\(inProgress.count)", label: "in queue")
                            }
                        }
                        .medxPlainRow()
                    } footer: {
                        Text("Saved classes stay inside MedX Elite and are excluded from device backups. Watch progress is shared with the streaming copy of the same class.")
                    }

                    if !inProgress.isEmpty {
                        Section {
                            ForEach(inProgress) { row($0) }
                        } header: {
                            MedxHeader("Downloading", count: inProgress.count)
                        }
                    }

                    if !finished.isEmpty {
                        Section {
                            ForEach(finished) { row($0) }
                        } header: {
                            MedxHeader("Saved on this device", count: finished.count)
                        }
                    }
                }
                .medxList()
            }
        }
                .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !downloads.items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            confirmDeleteAll = true
                        } label: {
                            Label("Delete all downloads", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Manage downloads")
                }
            }
        }
        .confirmationDialog(
            "Delete all downloads?",
            isPresented: $confirmDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Delete \(downloads.allItems.count) downloads", role: .destructive) {
                HapticManager.warning()
                downloads.removeAll()
            }
            Button("Keep them", role: .cancel) {}
        } message: {
            Text("This frees \(downloads.formattedTotalSize) on this device. You can download them again any time.")
        }
        .fullScreenCover(item: $activeVideo) { video in
            VideoPlayerView(video: video) { activeVideo = nil }
        }
    }

    private func row(_ item: DownloadedVideo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.state == .completed ? "play.fill" : "arrow.down")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(statusColor(item))
                .frame(width: 38, height: 38)
                .background(statusColor(item).opacity(0.14), in: MedxDS.shape(MedxDS.control))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.video.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(subtitle(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if item.state != .completed {
                    ProgressView(value: item.progress)
                        .tint(statusColor(item))
                }

                Text(item.statusLabel)
                    .font(.caption)
                    .foregroundStyle(item.state == .failed ? MedxDS.warn : .secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            VideoDownloadButton(video: item.video)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            guard item.state == .completed else { return }
            HapticManager.light()
            activeVideo = item.video
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                HapticManager.warning()
                downloads.remove(item.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            // A queue is the one place pausing is worth a gesture: it is the thing you reach for
            // when a download is eating the connection you are trying to watch something on.
            switch item.state {
            case .queued, .downloading:
                Button {
                    HapticManager.light()
                    downloads.pause(item.id)
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .tint(MedxDS.warn)
            case .paused, .failed:
                Button {
                    HapticManager.light()
                    downloads.resume(item.id)
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .tint(MedxDS.correct)
            case .completed:
                Button {
                    HapticManager.light()
                    activeVideo = item.video
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .tint(MedxCandy.violet)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.state == .completed ? "Plays this download" : "")
    }

    private func subtitle(for item: DownloadedVideo) -> String {
        var parts = [item.video.subject]
        if let faculty = item.video.faculty, !faculty.isEmpty { parts.append(faculty) }
        return parts.joined(separator: " · ")
    }

    private func statusColor(_ item: DownloadedVideo) -> Color {
        switch item.state {
        case .completed: return MedxDS.correct
        case .failed: return MedxDS.warn
        case .paused: return MedxTheme.primaryPurple
        case .queued, .downloading: return MedxTheme.accent
        }
    }
}

