import SwiftUI

/// The classes inside one subject.
///
/// A `List` rather than a `LazyVStack`, and that is the whole point: swipe a row to save it
/// offline, swipe the other way to play or clear its progress. Those are the platform's own
/// gestures — full-swipe, rubber-band, and "Actions available" under VoiceOver — and none of it
/// is hand-rolled. Because the gesture is there, the row no longer carries a permanent download
/// button; that control only reappears while a download is actually in flight, where it is a
/// progress readout rather than a second way to start one.
public struct VideoSubjectView: View {
    public let subjectGroup: VideoSubjectGroup

    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var downloads = VideoDownloadStore.shared
    @State private var activeVideo: RecordedVideo?

    public init(subjectGroup: VideoSubjectGroup) {
        self.subjectGroup = subjectGroup
    }

    private var uid: String? { authService.currentSession?.uid }

    /// Classes in this subject that are not already saved on the device.
    private var pendingDownloads: [RecordedVideo] {
        subjectGroup.videos.filter { downloads.items[$0.id]?.state != .completed }
    }

    private var offlineCount: Int {
        subjectGroup.videos.count - pendingDownloads.count
    }

    public var body: some View {
        List {
            Section {
                summaryRow
                    .medxPlainRow(vertical: 2)
            }

            Section {
                ForEach(Array(subjectGroup.videos.enumerated()), id: \.element.id) { index, video in
                    videoRow(video, index: index)
                        .medxPlainRow(vertical: 5)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            downloadSwipeAction(video)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            playbackSwipeActions(video)
                        }
                }
            } footer: {
                Text("Swipe a class left to save it offline, right to play it. Long-press for the quality menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .medxPage(.videos)
        .navigationTitle(subjectGroup.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                bulkDownloadMenu
            }
        }
        .fullScreenCover(item: $activeVideo) { video in
            VideoPlayerView(video: video) { activeVideo = nil }
        }
    }

    // MARK: - Swipe actions

    /// Trailing swipe: the one thing you most often want from a class you are not watching yet.
    /// Full swipe commits it, exactly as full-swiping a mail archives it.
    @ViewBuilder
    private func downloadSwipeAction(_ video: RecordedVideo) -> some View {
        if downloads.items[video.id]?.state == .completed {
            Button(role: .destructive) {
                HapticManager.warning()
                downloads.remove(video.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } else {
            Button {
                HapticManager.success()
                downloads.start(video, quality: .standard)
            } label: {
                Label("Save", systemImage: "arrow.down.circle")
            }
            .tint(MedxDS.correct)
        }
    }

    /// Leading swipe: play, and — where there is something to forget — forget it.
    @ViewBuilder
    private func playbackSwipeActions(_ video: RecordedVideo) -> some View {
        let history = activityStore.entry(for: video.id, uid: uid)

        Button {
            HapticManager.light()
            activeVideo = video
        } label: {
            Label(
                (history?.resumePosition ?? 0) > 0 ? "Resume" : "Play",
                systemImage: "play.fill"
            )
        }
        .tint(MedxCandy.violet)

        if let history {
            Button {
                HapticManager.warning()
                activityStore.removeWatchHistory(history, uid: uid)
            } label: {
                Label("Clear", systemImage: "clock.badge.xmark")
            }
            .tint(MedxDS.warn)
        }
    }

    // MARK: - Chrome

    private var bulkDownloadMenu: some View {
        Menu {
            if pendingDownloads.isEmpty {
                Section("Every class is saved offline") {
                    Button(role: .destructive) {
                        HapticManager.warning()
                        for video in subjectGroup.videos {
                            downloads.remove(video.id)
                        }
                    } label: {
                        Label("Delete these downloads", systemImage: "trash")
                    }
                }
            } else {
                Section("Save \(pendingDownloads.count) classes offline") {
                    ForEach(DownloadQuality.allCases) { quality in
                        Button {
                            HapticManager.light()
                            downloads.startAll(pendingDownloads, quality: quality)
                        } label: {
                            Label(quality.label, systemImage: quality.icon)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: offlineCount > 0 ? "arrow.down.circle.fill" : "arrow.down.circle")
                .font(.system(size: 17, weight: .semibold))
        }
        .accessibilityLabel("Download all classes")
    }

    private var summaryRow: some View {
        HStack(spacing: 8) {
            MedxChip("\(subjectGroup.totalClasses) classes", icon: "play.fill", tint: MedxTheme.primaryBlue)
            MedxChip(subjectGroup.formattedDuration, icon: "clock.fill", tint: MedxTheme.primaryPurple)
            if offlineCount > 0 {
                MedxChip("\(offlineCount) offline", icon: "arrow.down.circle.fill", tint: MedxDS.correct)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Row

    private func videoRow(_ video: RecordedVideo, index: Int) -> some View {
        let history = activityStore.entry(for: video.id, uid: uid)
        let inFlight = downloads.items[video.id].flatMap { $0.state == .completed ? nil : $0 }

        return HStack(spacing: 12) {
            Button {
                HapticManager.light()
                activeVideo = video
            } label: {
                rowLabel(video, index: index, history: history)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Play \(video.title)")

            // Only while something is actually downloading: then it is the progress readout and
            // the pause control. Otherwise the swipe and the long-press menu are the affordance.
            if inFlight != nil {
                VideoDownloadButton(video: video)
            }
        }
        .padding(12)
        .frame(minHeight: 64)
        .medxCard()
        .contextMenu {
            rowContextMenu(video, history: history)
        }
    }

    private func rowLabel(
        _ video: RecordedVideo,
        index: Int,
        history: WatchHistoryEntry?
    ) -> some View {
        HStack(spacing: 14) {
            Text("\(index + 1)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(MedxTheme.accent)
                .medxInkCircle(diameter: 40, tint: MedxTheme.accent.opacity(0.18))

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                metaLine(video)

                if let history, history.progress > 0 {
                    progressLine(history)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func metaLine(_ video: RecordedVideo) -> some View {
        HStack(spacing: 8) {
            if let faculty = video.faculty, !faculty.isEmpty {
                Text(faculty)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let seconds = video.durationSeconds, seconds > 0 {
                Text(video.formattedDuration)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if downloads.items[video.id]?.state == .completed {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(MedxDS.correct)
                    .accessibilityLabel("Available offline")
            }
        }
    }

    private func progressLine(_ history: WatchHistoryEntry) -> some View {
        HStack(spacing: 6) {
            ProgressView(value: history.progress)
                .tint(history.isCompleted ? MedxDS.correct : MedxTheme.accent)
                .frame(width: 64)

            Text(history.isCompleted
                 ? "Watched"
                 : "Resume at \(history.formattedResumeTime) · \(Int(history.progress * 100))%")
                .font(.caption2)
                .foregroundStyle(history.isCompleted ? MedxDS.correct : .secondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func rowContextMenu(_ video: RecordedVideo, history: WatchHistoryEntry?) -> some View {
        Button {
            HapticManager.light()
            activeVideo = video
        } label: {
            Label((history?.resumePosition ?? 0) > 0 ? "Resume" : "Play", systemImage: "play.circle")
        }

        if downloads.items[video.id]?.state == .completed {
            Button(role: .destructive) {
                HapticManager.warning()
                downloads.remove(video.id)
            } label: {
                Label("Delete download", systemImage: "trash")
            }
        } else {
            ForEach(DownloadQuality.allCases) { quality in
                Button {
                    HapticManager.light()
                    downloads.start(video, quality: quality)
                } label: {
                    Label("Save · \(quality.label)", systemImage: quality.icon)
                }
            }
        }

        if let history {
            Button(role: .destructive) {
                activityStore.removeWatchHistory(history, uid: uid)
            } label: {
                Label("Clear watch progress", systemImage: "clock.badge.xmark")
            }
        }
    }
}

public extension View {
    /// A `List` row that keeps the app's own card geometry: no separator, no system fill, and
    /// the page's gutter rather than the list's inset. This is what lets a screen take the
    /// platform's swipe actions without giving up the aurora behind it.
    func medxPlainRow(vertical: CGFloat = 5) -> some View {
        self
            .listRowInsets(
                EdgeInsets(
                    top: vertical,
                    leading: MedxDS.gutter,
                    bottom: vertical,
                    trailing: MedxDS.gutter
                )
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
