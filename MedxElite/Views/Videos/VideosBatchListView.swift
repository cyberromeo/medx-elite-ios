import SwiftUI

/// The Classes tab: every recorded ARISE lecture, by batch and then by subject, with whatever
/// was left half-watched at the top. One row a subject; the classes themselves are a push away.
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

    private var isLoading: Bool { loadState == .loading && videos.isEmpty }

    private var subtitle: String {
        guard !videos.isEmpty else { return "Every recorded ARISE lecture" }
        let seconds = videos.compactMap(\.durationSeconds).reduce(0, +)
        return "\(MedxFormat.count(videos.count)) classes · \(MedxFormat.duration(seconds))"
    }

    public var body: some View {
        Group {
            if case .failed(let message) = loadState, videos.isEmpty {
                MedxEmptyState(
                    "Couldn't load classes",
                    symbol: "wifi.exclamationmark",
                    message: message,
                    actionTitle: "Try again"
                ) {
                    HapticManager.light()
                    loadState = .loading
                    Task { await loadVideos() }
                }
            } else if loadState == .loaded, videos.isEmpty {
                MedxEmptyState(
                    "No classes yet",
                    symbol: MedxFeature.classes.symbol,
                    message: "Recorded classes appear here once they are published."
                )
            } else {
                list
            }
        }
        .navigationTitle(MedxFeature.classes.title)
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                MedxProfileButton()
            }
        }
        .searchable(text: $searchText, prompt: "Search classes")
        .searchToolbarBehavior(.minimize)
        .task {
            guard case .loading = loadState else { return }
            await medxLoadRevalidating { await loadVideos() }
        }
        .onChange(of: searchText) { _, _ in
            regroup()
        }
        .onReceive(NotificationCenter.default.publisher(for: .medxContentShouldRefresh)) { _ in
            Task { await loadVideos() }
        }
        .fullScreenCover(item: $activeVideo) { video in
            VideoPlayerView(video: video) { activeVideo = nil }
        }
        #if DEBUG
        // Screenshot runs only (`-medxScreen videosubject`): opens the first subject once loaded.
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
    }

    // MARK: - List

    private var list: some View {
        List {
            continueSection

            if isLoading {
                Section {
                    MedxPlaceholderRows(count: 8)
                }
            } else if groups.isEmpty {
                Section {
                    MedxEmptyState(
                        "No matches",
                        symbol: "magnifyingglass",
                        message: "No class matches “\(searchText)”."
                    )
                }
            } else {
                ForEach(groups) { batch in
                    Section {
                        ForEach(batch.subjects) { subject in
                            subjectLink(subject)
                        }
                    } header: {
                        Text(batch.name)
                    } footer: {
                        Text("\(batch.totalClasses) classes · \(MedxFormat.duration(batch.totalSeconds))")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            // A pull always reaches the backend: cached copies are kept for offline, never
            // served in place of a fresh read the student asked for.
            await CacheManager.shared.markAllStale()
            await loadVideos()
        }
    }

    // MARK: - Continue watching

    @ViewBuilder
    private var continueSection: some View {
        let entries = Array(
            activityStore.watchHistory(for: uid)
                .filter { !$0.isCompleted && $0.resumePosition > 0 }
                .prefix(3)
        )
        if !entries.isEmpty {
            Section("Continue watching") {
                ForEach(entries) { entry in
                    continueRow(entry)
                }
            }
        }
    }

    private func continueRow(_ entry: WatchHistoryEntry) -> some View {
        Button {
            HapticManager.light()
            activeVideo = entry.video
        } label: {
            HStack(spacing: MedxSpace.m) {
                MedxSymbolTile("play.fill", hue: MedxFeature.classes.color, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.video.title.medxDisplayTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(entry.video.subject) · resume at \(entry.formattedResumeTime)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ProgressView(value: entry.progress)
                        .padding(.top, 2)
                }

                Spacer(minLength: MedxSpace.s)

                if downloads.isDownloaded(entry.video.id) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(MedxOutcome.correct)
                        .accessibilityLabel("Saved offline")
                }
            }
            .padding(.vertical, 2)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                activityStore.removeWatchHistory(entry, uid: uid)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Resume \(entry.video.title.medxDisplayTitle)")
        .accessibilityValue("\(Int(entry.progress * 100)) percent watched")
    }

    // MARK: - Subjects

    private func subjectLink(_ subject: VideoSubjectGroup) -> some View {
        NavigationLink {
            VideoSubjectView(subjectGroup: subject)
        } label: {
            subjectRow(subject)
        }
        // Hold a subject to save the whole thing for no signal.
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

    private func subjectRow(_ subject: VideoSubjectGroup) -> some View {
        let offline = subject.videos.filter { downloads.isDownloaded($0.id) }.count
        var detail = "\(subject.totalClasses) classes · \(MedxFormat.duration(subject.totalSeconds))"
        if offline > 0 { detail += " · \(offline) offline" }

        return HStack(spacing: MedxSpace.m) {
            MedxSymbolTile(MedxSubjectArt.symbol(for: subject.name), hue: MedxFeature.classes.color, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(subject.name.medxDisplayTitle)
                    .lineLimit(2)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: MedxSpace.s)

            if offline > 0 {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(MedxOutcome.correct)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subject.name)
        .accessibilityValue(detail)
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
