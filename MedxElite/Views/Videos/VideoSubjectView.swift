import SwiftUI

/// The classes inside one subject. Tap to play, swipe right to play, swipe left to save it
/// offline — the platform's own gestures, which the footer says once — and the download control
/// at the end of the row for everything else.
public struct VideoSubjectView: View {
    public let subjectGroup: VideoSubjectGroup

    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var downloads = VideoDownloadStore.shared
    @State private var activeVideo: RecordedVideo?
    @State private var confirmDeleteAll = false

    public init(subjectGroup: VideoSubjectGroup) {
        self.subjectGroup = subjectGroup
    }

    private var uid: String? { authService.currentSession?.uid }

    /// Classes in this subject that are not already saved on the device.
    private var pendingDownloads: [RecordedVideo] {
        subjectGroup.videos.filter { !downloads.isDownloaded($0.id) }
    }

    private var offlineCount: Int {
        subjectGroup.videos.count - pendingDownloads.count
    }

    private var subtitle: String {
        var text = "\(subjectGroup.totalClasses) classes · \(MedxFormat.duration(subjectGroup.totalSeconds))"
        if offlineCount > 0 { text += " · \(offlineCount) offline" }
        return text
    }

    public var body: some View {
        List {
            Section {
                ForEach(Array(subjectGroup.videos.enumerated()), id: \.element.id) { pair in
                    videoRow(pair.element, index: pair.offset)
                }
            } footer: {
                Text(MedxCopy.classGestures)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(subjectGroup.name.medxDisplayTitle)
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if pendingDownloads.isEmpty {
                        Section("Every class is saved offline") {
                            Button(role: .destructive) {
                                confirmDeleteAll = true
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
                }
                .accessibilityLabel("Save every class offline")
            }
        }
        .confirmationDialog(
            "Delete \(offlineCount) downloads?",
            isPresented: $confirmDeleteAll,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                HapticManager.warning()
                for video in subjectGroup.videos where downloads.isDownloaded(video.id) {
                    downloads.remove(video.id)
                }
            }
            Button("Keep them", role: .cancel) {}
        } message: {
            Text("The classes stay in the list and can be saved again any time.")
        }
        .fullScreenCover(item: $activeVideo) { video in
            VideoPlayerView(video: video) { activeVideo = nil }
        }
    }

    // MARK: - Row

    private func videoRow(_ video: RecordedVideo, index: Int) -> some View {
        let history = activityStore.entry(for: video.id, uid: uid)
        let item = downloads.items[video.id]
        let isDownloaded = item?.state == .completed

        return HStack(spacing: MedxSpace.m) {
            // A tap plays. The download control is a sibling rather than part of the label: a
            // `Menu` nested inside a `Button` label never receives the tap.
            Button {
                HapticManager.light()
                activeVideo = video
            } label: {
                HStack(spacing: MedxSpace.m) {
                    Text("\(index + 1)")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(MedxTheme.accent)
                        .frame(width: 32, height: 32)
                        .background(MedxTheme.accent.opacity(0.12), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(video.title.medxDisplayTitle)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Text(detailLine(video, isDownloaded: isDownloaded))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let history, history.progress > 0 {
                            ProgressView(value: history.progress)
                                .tint(history.isCompleted ? MedxOutcome.correct : MedxTheme.accent)
                                .padding(.top, 2)
                            Text(history.isCompleted ? "Watched" : "Resume at \(history.formattedResumeTime)")
                                .font(.caption)
                                .foregroundStyle(history.isCompleted ? MedxOutcome.correct : Color.secondary)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Play \(video.title.medxDisplayTitle)")
            .accessibilityValue(detailLine(video, isDownloaded: isDownloaded))

            VideoDownloadButton(video: video)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                HapticManager.light()
                activeVideo = video
            } label: {
                Label((history?.resumePosition ?? 0) > 0 ? "Resume" : "Play", systemImage: "play.fill")
            }
            .tint(MedxTheme.accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if isDownloaded {
                Button(role: .destructive) {
                    HapticManager.warning()
                    downloads.remove(video.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } else if item?.isActive == true {
                Button {
                    HapticManager.light()
                    downloads.pause(video.id)
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .tint(MedxOutcome.flagged)
            } else {
                Button {
                    HapticManager.success()
                    downloads.start(video, quality: .standard)
                } label: {
                    Label("Save", systemImage: "arrow.down.circle")
                }
                .tint(MedxOutcome.correct)
            }
        }
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

    private func detailLine(_ video: RecordedVideo, isDownloaded: Bool) -> String {
        var parts: [String] = []
        if let faculty = video.faculty, !faculty.isEmpty { parts.append(faculty) }
        if let seconds = video.durationSeconds, seconds > 0 { parts.append(MedxFormat.duration(seconds)) }
        if isDownloaded { parts.append("Saved offline") }
        return parts.joined(separator: " · ")
    }
}
