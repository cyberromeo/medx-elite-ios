import SwiftUI

public struct VideosBatchListView: View {
    @ObservedObject var authService = AuthService.shared
    @State private var videos: [RecordedVideo] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var expandedBatches: Set<String> = []
    @State private var activeVideo: RecordedVideo?
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var downloads = VideoDownloadStore.shared

    public init() {}

    private var batchGroups: [VideoBatchGroup] {
        var batchMap: [String: (name: String, totalSeconds: Int, count: Int, subjects: [String: (name: String, totalSeconds: Int, videos: [RecordedVideo])])] = [:]

        let filteredVideos = searchText.isEmpty ? videos : videos.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.subject.localizedCaseInsensitiveContains(searchText) ||
            ($0.faculty ?? "").localizedCaseInsensitiveContains(searchText)
        }

        for v in filteredVideos {
            let bId = v.batchId ?? "default"
            let bName = v.batch ?? "Batch"
            let sId = v.subjectId ?? "sub"
            let sName = v.subject
            let dur = v.durationSeconds ?? 0

            var batchEntry = batchMap[bId] ?? (name: bName, totalSeconds: 0, count: 0, subjects: [:])
            batchEntry.totalSeconds += dur
            batchEntry.count += 1

            var subEntry = batchEntry.subjects[sId] ?? (name: sName, totalSeconds: 0, videos: [])
            subEntry.totalSeconds += dur
            subEntry.videos.append(v)
            batchEntry.subjects[sId] = subEntry

            batchMap[bId] = batchEntry
        }

        return batchMap.map { (bId, bData) in
            let subjectGroups = bData.subjects.map { (sId, sData) in
                VideoSubjectGroup(
                    subjectId: sId,
                    name: sData.name,
                    totalSeconds: sData.totalSeconds,
                    totalClasses: sData.videos.count,
                    videos: sData.videos
                )
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            return VideoBatchGroup(
                batchId: bId,
                name: bData.name,
                totalSeconds: bData.totalSeconds,
                totalClasses: bData.count,
                subjects: subjectGroups
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public var body: some View {
        ZStack {
            ambientBackground

            if isLoading {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(0..<4, id: \.self) { _ in
                            skeletonCard
                        }
                    }
                    .padding(20)
                }
            } else if videos.isEmpty {
                ContentUnavailableView(
                    "No Videos",
                    systemImage: "play.tv",
                    description: Text("Videos will appear here once loaded.")
                )
            } else {
                ScrollView {
                    VStack(spacing: 24) {
                        // Stats header
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
                                label: "total",
                                color: MedxTheme.primaryPurple
                            )

                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 6)

                        continueWatchingSection

                        // Batch groups
                        ForEach(batchGroups) { batch in
                            batchSection(batch)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .refreshable {
                    await loadVideos()
                }
            }
        }
        .navigationTitle("Videos")
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
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search videos")
        .task {
            await loadVideos()
        }
        .fullScreenCover(item: $activeVideo) { video in
            VideoPlayerView(video: video) {
                activeVideo = nil
            }
        }
    }

    // MARK: - Batch Section

    private func batchSection(_ batch: VideoBatchGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Batch header
            HStack {
                Text(batch.name)
                    .font(MedxFont.headline(18))

                Spacer()

                Text("\(batch.totalClasses) classes")
                    .font(MedxFont.caption(12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)

            LazyVStack(spacing: 10) {
                ForEach(batch.subjects) { subject in
                    NavigationLink {
                        VideoSubjectView(subjectGroup: subject)
                    } label: {
                        subjectRow(subject)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private var continueWatchingSection: some View {
        let entries = Array(activityStore.watchHistory(for: authService.currentSession?.uid).prefix(5))
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Continue Watching", systemImage: "play.circle.fill")
                        .font(MedxFont.headline(16))
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("Resume")
                        .font(MedxFont.caption(12))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(entries) { entry in
                            Button {
                                HapticManager.light()
                                activeVideo = entry.video
                            } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "play.circle.fill")
                                        .font(.title2)
                                        .foregroundStyle(entry.isCompleted ? MedxTheme.successGreen : MedxTheme.primaryBlue)
                                    Text(entry.video.title)
                                        .font(MedxFont.headline(13))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .frame(width: 170, alignment: .leading)
                                    ProgressView(value: entry.progress)
                                        .tint(entry.isCompleted ? MedxTheme.successGreen : MedxTheme.primaryBlue)
                                    Text(entry.isCompleted ? "Completed" : "Resume at \(entry.formattedResumeTime)")
                                        .font(MedxFont.caption(11))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(14)
                                .frame(width: 198, alignment: .leading)
                                .glassCard(cornerRadius: 16, shadowLevel: 1)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(entry.video.title), \(Int(entry.progress * 100)) percent watched")
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
    }

    // MARK: - Subject Row

    private func subjectRow(_ subject: VideoSubjectGroup) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [MedxTheme.primaryBlue.opacity(0.2), MedxTheme.cyanAccent.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)

                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(MedxTheme.primaryBlue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(subject.name)
                    .font(MedxFont.headline(16))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text("\(subject.totalClasses) classes")
                        .font(MedxFont.caption(12))
                        .foregroundColor(.secondary)

                    Text("·")
                        .foregroundColor(Color(uiColor: .quaternaryLabel))

                    Text(subject.formattedDuration)
                        .font(MedxFont.mono(12, weight: .semibold))
                        .foregroundColor(MedxTheme.primaryBlue)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(uiColor: .tertiaryLabel))
        }
        .padding(14)
        .frame(minHeight: 68)
        .glassCard(cornerRadius: 18, shadowLevel: 1)
    }

    private var skeletonCard: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 14)
                    .frame(maxWidth: 180)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .frame(height: 10)
                    .frame(maxWidth: 120)
            }
            Spacer()
        }
        .padding(16)
        .liquidGlassCard(cornerRadius: 18)
        .redacted(reason: .placeholder)
    }

    private var ambientBackground: some View {
        Color(uiColor: .systemGroupedBackground)
            .ignoresSafeArea()
    }

    /// Toolbar entry point for the offline library. The dot appears while anything is still fetching.
    private var downloadsToolbarIcon: some View {
        Image(systemName: downloads.completedItems.isEmpty ? "arrow.down.circle" : "arrow.down.circle.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(MedxTheme.primaryBlue)
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

    private var totalDurationFormatted: String {
        let total = videos.compactMap { $0.durationSeconds }.reduce(0, +)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    private func loadVideos() async {
        do {
            let token = try await authService.getValidIdToken()
            self.videos = try await FirestoreService.shared.fetchVideos(idToken: token)
            self.isLoading = false
        } catch {
            self.isLoading = false
        }
    }
}

// MARK: - Download Control

/// One compact control that covers every download state: save, pause, resume, retry, delete.
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

    // MARK: Menu

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

    // MARK: Glyph

    private var glyph: some View {
        ZStack {
            Circle()
                .fill(Color(uiColor: .tertiarySystemFill))
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
                        .stroke(MedxTheme.primaryBlue.opacity(0.2), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: max(0.03, item.progress))
                        .stroke(MedxTheme.primaryBlue, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(MedxTheme.primaryBlue)
                        .frame(width: 7, height: 7)
                }
                .frame(width: diameter - 9, height: diameter - 9)
                .animation(.easeOut(duration: 0.25), value: item.progress)
            case .paused:
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(MedxTheme.primaryBlue)
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
                .foregroundStyle(MedxTheme.primaryBlue)
        }
    }
}

// MARK: - Offline Library

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
                emptyState
            } else {
                List {
                    summarySection

                    if !inProgress.isEmpty {
                        Section("Downloading") {
                            ForEach(inProgress) { item in
                                row(item)
                            }
                        }
                    }

                    if !finished.isEmpty {
                        Section("Saved on this device") {
                            ForEach(finished) { item in
                                row(item)
                            }
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
            VideoPlayerView(video: video) {
                activeVideo = nil
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Downloads Yet", systemImage: "arrow.down.circle")
        } description: {
            Text("Tap the download icon on any class to keep it on this device. Downloads play inside the app, even with no signal.")
        }
    }

    // MARK: Summary

    private var summarySection: some View {
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
            Text("Saved videos stay inside MedX Elite and are excluded from device backups.")
        }
    }

    // MARK: Row

    private func row(_ item: DownloadedVideo) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(statusColor(item).opacity(0.14))
                    .frame(width: 42, height: 42)

                Image(systemName: item.state == .completed ? "play.fill" : "arrow.down")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(statusColor(item))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.video.title)
                    .font(MedxFont.headline(15))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(subtitle(for: item))
                    .font(MedxFont.caption(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if item.state != .completed {
                    ProgressView(value: item.progress)
                        .tint(statusColor(item))
                }

                Text(item.statusLabel)
                    .font(MedxFont.caption(11))
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
        case .queued, .downloading: return MedxTheme.primaryBlue
        }
    }
}
