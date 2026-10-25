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
    #if DEBUG
    @State private var debugPick: VideoSubjectGroup?
    #endif

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
                        MedxSticker("clapper", size: 44)
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
                            MedxSticker("clapper", size: 44)
                        }
                    } description: {
                        Text("Recorded classes will appear here once they are published.")
                    }
                } else {
                    content
                }
            }
        }
        .medxBackdrop(.videos)
        .medxScrollEdge()
        .navigationTitle("Classes")
        #if DEBUG
        // Screenshot runs only (`-medxScreen videosubject`): opens the first item once loaded.
        .navigationDestination(item: $debugPick) { item in
            VideoSubjectView(subjectGroup: item)
        }
        .onChange(of: groups.count) { _, count in
            guard count > 0, debugPick == nil,
                  UserDefaults.standard.string(forKey: "medxScreen") == "videosubject" else { return }
            let all = groups.flatMap { $0.subjects }
            debugPick = all.first(where: { $0.name.localizedCaseInsensitiveContains("micro") }) ?? all.first
        }
        #endif
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
                MedxProfileButton()
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search classes"
        )
        .task {
            guard case .loading = loadState else { return }
            await medxLoadRevalidating { await loadVideos() }
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
                MedxPageHeader(
                    section: .videos,
                    lead: "Every recorded ARISE lecture, by batch and then by subject. "
                        + "Hold a subject to save the whole thing for no signal."
                )

                MedxMetricsRow {
                    MedxMetric(
                        icon: "play.rectangle.fill",
                        value: "\(videos.count)",
                        label: "classes",
                        color: MedxIconHue.violet
                    )
                    MedxMetric(
                        icon: "clock.fill",
                        value: totalDurationFormatted,
                        label: "total runtime",
                        color: MedxIconHue.sky
                    )
                    MedxMetric(
                        icon: "arrow.down.circle.fill",
                        value: "\(downloads.completedItems.count)",
                        label: "offline",
                        color: MedxCandy.mint
                    )
                }

                continueWatchingSection

                if groups.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("No Matches")
                        } icon: {
                            MedxSticker("search", size: 40)
                        }
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
            // A pull always reaches the backend: cached copies are kept for offline, never
            // served in place of a fresh read the student asked for.
            await CacheManager.shared.markAllStale()
            await loadVideos()
        }
        .onReceive(NotificationCenter.default.publisher(for: .medxContentShouldRefresh)) { _ in
            Task { await loadVideos() }
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
            MedxSymbolMark(MedxSubjectArt.symbol(for: subject.name), hue: MedxCandy.violet, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(subject.name.medxDisplayTitle)
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
                        .foregroundStyle(entry.isCompleted ? MedxTheme.successGreen : MedxTheme.accent)

                    Spacer(minLength: 0)

                    if downloads.items[entry.video.id]?.state == .completed {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption)
                            .foregroundStyle(MedxTheme.successGreen)
                            .accessibilityLabel("Available offline")
                    }
                }

                Text(entry.video.title.medxDisplayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)

                ProgressView(value: entry.progress)
                    .tint(entry.isCompleted ? MedxTheme.successGreen : MedxTheme.accent)

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
        .accessibilityLabel(entry.video.title.medxDisplayTitle)
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
