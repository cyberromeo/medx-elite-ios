import SwiftUI

// MARK: - Watch history

/// Every class started, newest first, with where it was left. A row plays it from there.
struct WatchHistoryView: View {
    let uid: String?
    @ObservedObject private var activityStore = ActivityStore.shared
    @State private var activeVideo: RecordedVideo?
    @State private var showClearConfirm = false

    private var entries: [WatchHistoryEntry] {
        activityStore.watchHistory(for: uid)
    }

    private var subtitle: String {
        entries.count == 1 ? "1 class" : "\(MedxFormat.count(entries.count)) classes"
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                MedxEmptyState(
                    "No watch history",
                    symbol: MedxFeature.watchHistory.symbol,
                    message: "Classes you start watching keep their place here, on every device."
                )
            } else {
                List {
                    Section {
                        ForEach(entries) { entry in
                            row(entry)
                        }
                    } footer: {
                        Text("Tap a class to pick it up where you left it. Swipe left to remove an entry.")
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(MedxFeature.watchHistory.title)
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !entries.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Label("Clear watch history", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Manage watch history")
                }
            }
        }
        .confirmationDialog(
            "Clear watch history?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear \(entries.count) entries", role: .destructive) {
                HapticManager.medium()
                activityStore.clearAllWatchHistory(uid: uid)
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Every resume position goes, on this device and from your account.")
        }
        .fullScreenCover(item: $activeVideo) { video in
            VideoPlayerView(video: video) {
                activeVideo = nil
            }
        }
    }

    private func row(_ entry: WatchHistoryEntry) -> some View {
        Button {
            HapticManager.light()
            activeVideo = entry.video
        } label: {
            HStack(spacing: MedxSpace.m) {
                MedxSymbolTile(
                    entry.isCompleted ? "checkmark" : "play.fill",
                    hue: entry.isCompleted ? MedxOutcome.correct : MedxFeature.classes.color,
                    size: 36
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.video.title.medxDisplayTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text([entry.video.subject, entry.video.faculty ?? ""]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    ProgressView(value: entry.progress)
                        .tint(entry.isCompleted ? MedxOutcome.correct : MedxTheme.accent)
                        .padding(.top, 2)

                    Text((entry.isCompleted ? "Watched" : "Resume at \(entry.formattedResumeTime)") + " · \(entry.formattedDate)")
                        .font(.caption)
                        .foregroundStyle(entry.isCompleted ? MedxOutcome.correct : Color.secondary)
                }

                Spacer(minLength: MedxSpace.s)

                MedxRowChevron()
            }
            .padding(.vertical, 2)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                HapticManager.medium()
                activityStore.removeWatchHistory(entry, uid: uid)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.video.title.medxDisplayTitle)
        .accessibilityValue("\(Int(entry.progress * 100)) percent watched")
    }
}
