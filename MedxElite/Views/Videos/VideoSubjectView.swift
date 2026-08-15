import SwiftUI

public struct VideoSubjectView: View {
    public let subjectGroup: VideoSubjectGroup
    @State private var activePlayingVideo: RecordedVideo?

    public init(subjectGroup: VideoSubjectGroup) {
        self.subjectGroup = subjectGroup
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header Info
                HStack {
                    Text("\(subjectGroup.totalClasses) classes · \(subjectGroup.formattedDuration)")
                        .font(MedxFont.rounded(13, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)

                // Video List
                LazyVStack(spacing: 12) {
                    ForEach(subjectGroup.videos) { video in
                        Button {
                            HapticManager.light()
                            activePlayingVideo = video
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(MedxTheme.primaryBlue.opacity(0.12))
                                        .frame(width: 46, height: 46)
                                    Image(systemName: "play.fill")
                                        .font(.headline)
                                        .foregroundColor(MedxTheme.primaryBlue)
                                        .offset(x: 1)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(video.title)
                                        .font(MedxFont.rounded(15, weight: .bold))
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)

                                    HStack(spacing: 8) {
                                        if let faculty = video.faculty, !faculty.isEmpty {
                                            Text(faculty)
                                                .font(MedxFont.rounded(12, weight: .medium))
                                                .foregroundColor(.secondary)
                                        }

                                        if let dur = video.durationSeconds, dur > 0 {
                                            Text("·")
                                                .foregroundColor(.secondary)
                                            Text(video.formattedDuration)
                                                .font(MedxFont.monospacedDigits(12, weight: .semibold))
                                                .foregroundColor(MedxTheme.primaryBlue)
                                        }
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(16)
                            .liquidGlassCard(cornerRadius: 18)
                        }
                        .buttonStyle(BouncyButtonStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(subjectGroup.name)
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(item: $activePlayingVideo) { video in
            NavigationStack {
                VideoPlayerView(
                    streamUrl: video.streamUrl,
                    title: video.title,
                    subtitle: video.faculty
                )
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") {
                            activePlayingVideo = nil
                        }
                        .foregroundColor(.white)
                    }
                }
            }
        }
    }
}
