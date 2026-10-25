import SwiftUI

// MARK: - Watch History View

struct WatchHistoryView: View {
    let uid: String?
    @ObservedObject private var activityStore = ActivityStore.shared
    @State private var activeVideo: RecordedVideo?
    @State private var showClearConfirm = false

    private var entries: [WatchHistoryEntry] {
        activityStore.watchHistory(for: uid)
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Watch History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Videos you start watching will automatically track your progress and resume position here.")
                )
            } else {
                List {
                    ForEach(entries) { entry in
                        Button {
                            activeVideo = entry.video
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle()
                                        .fill(MedxTheme.primaryBlue.opacity(0.12))
                                        .frame(width: 44, height: 44)
                                    Image(systemName: "play.circle.fill")
                                        .font(.title2)
                                        .foregroundColor(MedxTheme.primaryBlue)
                                }

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.video.title.medxDisplayTitle)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)

                                    HStack(spacing: 6) {
                                        Text(entry.video.subject)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        if let faculty = entry.video.faculty, !faculty.isEmpty {
                                            Text("· \(faculty)")
                                                .font(.caption)
                                                .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                        }

                                        Spacer()

                                        Text(entry.formattedDate)
                                            .font(.caption)
                                            .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                    }

                                    ProgressView(value: entry.progress)
                                        .tint(entry.isCompleted ? MedxTheme.successGreen : MedxTheme.primaryBlue)

                                    HStack {
                                        if entry.isCompleted {
                                            Label("Completed", systemImage: "checkmark.circle.fill")
                                                .font(.caption.weight(.bold).monospacedDigit())
                                                .foregroundColor(MedxTheme.successGreen)
                                        } else {
                                            Label("Resume at \(entry.formattedResumeTime)", systemImage: "arrow.counterclockwise.circle.fill")
                                                .font(.caption.weight(.bold).monospacedDigit())
                                                .foregroundColor(MedxTheme.cyanAccent)
                                        }
                                        Spacer()
                                        Text("\(Int(entry.progress * 100))%")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                HapticManager.medium()
                                activityStore.removeWatchHistory(entry, uid: uid)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Watch History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Label("Clear All Watch History", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 44, height: 44)
                    }
                }
            }
        }
        .confirmationDialog(
            "Clear Watch History?",
            isPresented: $showClearConfirm
        ) {
            Button("Clear All", role: .destructive) {
                HapticManager.medium()
                activityStore.clearAllWatchHistory(uid: uid)
            }
        } message: {
            Text("This will clear your watch progress and resume positions for all videos locally and in the cloud.")
        }
        .fullScreenCover(item: $activeVideo) { video in
            VideoPlayerView(video: video) {
                activeVideo = nil
            }
        }
    }
}
