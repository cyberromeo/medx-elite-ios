import SwiftUI

/// The classes inside one subject. Play on tap, download from the trailing control, and
/// long-press for the quality menu without opening the player.
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                summaryRow

                ForEach(Array(subjectGroup.videos.enumerated()), id: \.element.id) { index, video in
                    videoRow(video, index: index)
                }
            }
            .padding(.horizontal, MedxSurface.gutter)
            .padding(.top, 6)
            .padding(.bottom, 32)
        }
        .background(MedxSurface.groupedBackground.ignoresSafeArea())
        .navigationTitle(subjectGroup.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
        }
        .fullScreenCover(item: $activeVideo) { video in
            VideoPlayerView(video: video) { activeVideo = nil }
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 8) {
            MedxChip("\(subjectGroup.totalClasses) classes", icon: "play.fill", tint: MedxTheme.primaryBlue)
            MedxChip(subjectGroup.formattedDuration, icon: "clock.fill", tint: MedxTheme.primaryPurple)
            if offlineCount > 0 {
                MedxChip("\(offlineCount) offline", icon: "arrow.down.circle.fill", tint: MedxTheme.successGreen)
            }
            Spacer(minLength: 0)
        }
    }

    private func videoRow(_ video: RecordedVideo, index: Int) -> some View {
        let history = activityStore.entry(for: video.id, uid: uid)
        let isDownloaded = downloads.items[video.id]?.state == .completed

        return HStack(spacing: 8) {
            Button {
                HapticManager.light()
                activeVideo = video
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 40, height: 40)
                        Text("\(index + 1)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(video.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)

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

                            if isDownloaded {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(MedxTheme.successGreen)
                                    .accessibilityLabel("Available offline")
                            }
                        }

                        if let history, history.progress > 0 {
                            HStack(spacing: 6) {
                                ProgressView(value: history.progress)
                                    .tint(history.isCompleted ? MedxTheme.successGreen : Color.accentColor)
                                    .frame(width: 64)
                                Text(history.isCompleted
                                     ? "Watched"
                                     : "Resume at \(history.formattedResumeTime) · \(Int(history.progress * 100))%")
                                    .font(.caption2)
                                    .foregroundStyle(history.isCompleted ? MedxTheme.successGreen : .secondary)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Play \(video.title)")

            // A `Menu` nested inside a `Button` label never receives taps, so the download
            // control lives beside the play button rather than inside it.
            VideoDownloadButton(video: video)
        }
        .padding(12)
        .frame(minHeight: 64)
        .medxCard()
        .contextMenu {
            Button {
                HapticManager.light()
                activeVideo = video
            } label: {
                Label((history?.resumePosition ?? 0) > 0 ? "Resume" : "Play", systemImage: "play.circle")
            }

            if isDownloaded {
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
}
