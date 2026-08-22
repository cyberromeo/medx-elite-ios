import SwiftUI

public struct VideoSubjectView: View {
    public let subjectGroup: VideoSubjectGroup
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var downloads = VideoDownloadStore.shared
    @State private var activePlayingVideo: RecordedVideo?
    @State private var hasAppeared = false

    public init(subjectGroup: VideoSubjectGroup) {
        self.subjectGroup = subjectGroup
    }

    /// Classes in this subject that are not already saved on the device.
    private var pendingDownloads: [RecordedVideo] {
        subjectGroup.videos.filter { downloads.items[$0.id]?.state != .completed }
    }

    private var offlineCount: Int {
        subjectGroup.videos.filter { downloads.items[$0.id]?.state == .completed }.count
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header stats
                HStack(spacing: 12) {
                    statBadge(
                        icon: "play.fill",
                        text: "\(subjectGroup.totalClasses) classes",
                        color: MedxTheme.primaryBlue
                    )

                    statBadge(
                        icon: "clock.fill",
                        text: subjectGroup.formattedDuration,
                        color: MedxTheme.primaryPurple
                    )

                    if offlineCount > 0 {
                        statBadge(
                            icon: "arrow.down.circle.fill",
                            text: "\(offlineCount) offline",
                            color: MedxTheme.successGreen
                        )
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)

                // Video List
                LazyVStack(spacing: 10) {
                    ForEach(Array(subjectGroup.videos.enumerated()), id: \.element.id) { index, video in
                        videoRow(video, index: index)
                            .opacity(hasAppeared ? 1 : 0)
                            .offset(y: hasAppeared ? 0 : 12)
                            .animation(
                                .spring(response: 0.5, dampingFraction: 0.8)
                                    .delay(Double(index) * 0.03),
                                value: hasAppeared
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
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
                        .foregroundStyle(MedxTheme.primaryBlue)
                }
                .accessibilityLabel("Download all classes")
            }
        }
        .fullScreenCover(item: $activePlayingVideo) { video in
            VideoPlayerView(
                video: video,
                onDismiss: {
                    activePlayingVideo = nil
                }
            )
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
                hasAppeared = true
            }
        }
    }

    // MARK: - Video Row

    private func videoRow(_ video: RecordedVideo, index: Int) -> some View {
        HStack(spacing: 4) {
            Button {
                HapticManager.light()
                activePlayingVideo = video
            } label: {
                rowLabel(video, index: index)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Play \(video.title)")
            .accessibilityHint("Opens the video player")

            VideoDownloadButton(video: video)
        }
        .padding(14)
        .frame(minHeight: 68)
        .liquidGlassCard(cornerRadius: 16)
    }

    /// Split out of `videoRow` so the download menu can live beside the play button
    /// instead of inside it — a `Menu` nested in a `Button` label never receives taps.
    private func rowLabel(_ video: RecordedVideo, index: Int) -> some View {
        HStack(spacing: 14) {
                // Index + Play icon
                ZStack {
                    Circle()
                        .fill(activePlayingVideo?.id == video.id
                              ? MedxTheme.primaryBlue
                              : MedxTheme.primaryBlue.opacity(0.1))
                        .frame(width: 44, height: 44)

                    if activePlayingVideo?.id == video.id {
                        // Playing indicator
                        Image(systemName: "waveform")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating)
                    } else {
                        Text("\(index + 1)")
                            .font(MedxFont.mono(14, weight: .bold))
                            .foregroundColor(MedxTheme.primaryBlue)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(MedxFont.headline(15))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        if let faculty = video.faculty, !faculty.isEmpty {
                            HStack(spacing: 4) {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 9))
                                Text(faculty)
                                    .font(MedxFont.caption(12))
                            }
                            .foregroundColor(.secondary)
                        }

                        if let dur = video.durationSeconds, dur > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.fill")
                                    .font(.system(size: 9))
                                Text(video.formattedDuration)
                                    .font(MedxFont.mono(12, weight: .semibold))
                            }
                            .foregroundColor(MedxTheme.primaryBlue.opacity(0.8))
                        }
                    }

                    if let history = activityStore.entry(for: video.id, uid: authService.currentSession?.uid), history.progress > 0 {
                        HStack(spacing: 6) {
                            ProgressView(value: history.progress)
                                .tint(MedxTheme.primaryBlue)
                                .frame(width: 56)
                            if history.isCompleted {
                                Text("Watched")
                                    .font(MedxFont.mono(11, weight: .bold))
                                    .foregroundColor(MedxTheme.successGreen)
                            } else {
                                Text("Resume at \(history.formattedResumeTime) (\(Int(history.progress * 100))%)")
                                    .font(MedxFont.caption(11))
                                    .foregroundColor(MedxTheme.cyanAccent)
                            }
                        }
                    }
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(MedxTheme.primaryBlue.opacity(0.6))
            }
        }

    // MARK: - Stat Badge

    private func statBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color)

            Text(text)
                .font(MedxFont.label(12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.08), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
