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
                    Label("Couldn't Load Classes", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") {
                        HapticManager.light()
                        loadState = .loading
                        Task { await loadVideos() }
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                }
            case .loaded:
                if videos.isEmpty {
                    ContentUnavailableView(
                        "No Classes",
                        systemImage: "play.tv",
                        description: Text("Recorded classes will appear here once they are published.")
                    )
                } else {
                    content
                }
            }
        }
        .background(MedxSurface.groupedBackground.ignoresSafeArea())
        .navigationTitle("Classes")
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
                ProfileSettingsButton()
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                MedxMetricsRow {
                    MedxMetric(
                        icon: "play.rectangle.fill",
                        value: "\(videos.count)",
                        label: "classes",
                        color: MedxTheme.primaryBlue
                    )
                    MedxMetric(
                        icon: "clock.fill",
                        value: totalDurationFormatted,
                        label: "total runtime",
                        color: MedxTheme.primaryPurple
                    )
                    MedxMetric(
                        icon: "arrow.down.circle.fill",
                        value: "\(downloads.completedItems.count)",
                        label: "offline",
                        color: MedxTheme.successGreen
                    )
                }

                continueWatchingSection

                if groups.isEmpty {
                    ContentUnavailableView {
                        Label("No Matches", systemImage: "magnifyingglass")
                    } description: {
                        Text("No class matches “\(searchText)”.")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                } else {
                    ForEach(groups) { batch in
                        batchSection(batch)
                    }
                }
            }
            .padding(.horizontal, MedxSurface.gutter)
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
        .refreshable {
            await loadVideos()
        }
    }

    private func batchSection(_ batch: VideoBatchGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MedxSectionHeader(batch.name, subtitle: "\(batch.totalClasses) classes")

            ForEach(batch.subjects) { subject in
                NavigationLink {
                    VideoSubjectView(subjectGroup: subject)
                } label: {
                    subjectRow(subject)
                }
                .buttonStyle(.plain)
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
        }
    }

    private func subjectRow(_ subject: VideoSubjectGroup) -> some View {
        let offline = subject.videos.filter { downloads.items[$0.id]?.state == .completed }.count

        return HStack(spacing: 14) {
            Image(systemName: "play.rectangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MedxTheme.primaryBlue)
                .frame(width: 38, height: 38)
                .background(MedxTheme.primaryBlue.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(subject.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Text("\(subject.totalClasses) classes · \(subject.formattedDuration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if offline > 0 {
                        Text("· \(offline) offline")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MedxTheme.successGreen)
                    }
                }
            }

            Spacer(minLength: 0)

            MedxDisclosure()
        }
        .padding(14)
        .frame(minHeight: 64)
        .medxCard()
        .contentShape(RoundedRectangle(cornerRadius: MedxSurface.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subject.name)
        .accessibilityValue("\(subject.totalClasses) classes, \(subject.formattedDuration)")
    }

    @ViewBuilder
    private var continueWatchingSection: some View {
        let entries = Array(activityStore.watchHistory(for: uid).prefix(6))
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                MedxSectionHeader("Continue watching")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(entries) { entry in
                            continueCard(entry)
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
                .scrollClipDisabled()
            }
        }
    }

    private func continueCard(_ entry: WatchHistoryEntry) -> some View {
        Button {
            HapticManager.light()
            activeVideo = entry.video
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(entry.isCompleted ? MedxTheme.successGreen : Color.accentColor)

                    Spacer(minLength: 0)

                    if downloads.items[entry.video.id]?.state == .completed {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption)
                            .foregroundStyle(MedxTheme.successGreen)
                            .accessibilityLabel("Available offline")
                    }
                }

                Text(entry.video.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                ProgressView(value: entry.progress)
                    .tint(entry.isCompleted ? MedxTheme.successGreen : Color.accentColor)

                Text(entry.isCompleted ? "Completed" : "Resume at \(entry.formattedResumeTime)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(14)
            .frame(width: 196, height: 152, alignment: .topLeading)
            .medxCard(cornerRadius: 14)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                activityStore.removeWatchHistory(entry, uid: uid)
            } label: {
                Label("Remove from history", systemImage: "trash")
            }
        }
        .accessibilityLabel(entry.video.title)
        .accessibilityValue("\(Int(entry.progress * 100)) percent watched")
    }

    /// Toolbar entry point for the offline library. The dot appears while anything is still fetching.
    private var downloadsToolbarIcon: some View {
        Image(systemName: downloads.completedItems.isEmpty ? "arrow.down.circle" : "arrow.down.circle.fill")
            .font(.system(size: 17, weight: .semibold))
            .overlay(alignment: .topTrailing) {
                if downloads.activeCount > 0 {
                    Circle()
                        .fill(MedxTheme.warningOrange)
                        .frame(width: 8, height: 8)
                        .offset(x: 3, y: -1)
                }
            }
            .frame(width: 40, height: 40)
    }

    private var loadingState: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { _ in
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.07))
                            .frame(width: 38, height: 38)

                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.primary.opacity(0.07))
                                .frame(height: 14)
                                .frame(maxWidth: 190)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                                .frame(height: 10)
                                .frame(maxWidth: 120)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .medxCard()
                }
            }
            .padding(.horizontal, MedxSurface.gutter)
            .padding(.top, 8)
        }
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
                .fill(MedxSurface.fieldFill)
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
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: max(0.03, item.progress))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                }
                .frame(width: diameter - 9, height: diameter - 9)
                .animation(.easeOut(duration: 0.25), value: item.progress)
            case .paused:
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Color.accentColor)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MedxTheme.warningOrange)
            case .completed:
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(MedxTheme.successGreen)
            }
        } else {
            Image(systemName: "arrow.down.to.line")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.accentColor)
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
                        MedxMetricsRow {
                            MedxMetric(
                                icon: "internaldrive.fill",
                                value: downloads.formattedTotalSize,
                                label: "on device",
                                color: MedxTheme.primaryBlue
                            )
                            MedxMetric(
                                icon: "checkmark.circle.fill",
                                value: "\(finished.count)",
                                label: "ready",
                                color: MedxTheme.successGreen
                            )
                            MedxMetric(
                                icon: "arrow.down.circle.fill",
                                value: "\(inProgress.count)",
                                label: "in queue",
                                color: MedxTheme.warningOrange
                            )
                        }
                        .padding(.vertical, 4)
                    } footer: {
                        Text("Saved classes stay inside MedX Elite and are excluded from device backups. Watch progress is shared with the streaming copy of the same class.")
                    }

                    if !inProgress.isEmpty {
                        Section("Downloading") {
                            ForEach(inProgress) { row($0) }
                        }
                    }

                    if !finished.isEmpty {
                        Section("Saved on this device") {
                            ForEach(finished) { row($0) }
                        }
                    }
                }
                .listStyle(.insetGrouped)
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
                .background(statusColor(item).opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

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
                    .foregroundStyle(item.state == .failed ? MedxTheme.warningOrange : .secondary)
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
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                downloads.remove(item.id)
            } label: {
                Label("Delete", systemImage: "trash")
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
        case .completed: return MedxTheme.successGreen
        case .failed: return MedxTheme.warningOrange
        case .paused: return MedxTheme.primaryPurple
        case .queued, .downloading: return Color.accentColor
        }
    }
}

