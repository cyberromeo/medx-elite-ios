import SwiftUI

// MARK: - Download control

/// One compact control covering every download state: save, pause, resume, retry, delete.
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

    private var glyph: some View {
        ZStack {
            Circle()
                .fill(MedxSurface.fieldFill)
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
                        .stroke(MedxTheme.accent.opacity(0.2), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: max(0.03, item.progress))
                        .stroke(MedxTheme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    RoundedRectangle(cornerRadius: 1, style: .continuous)
                        .fill(MedxTheme.accent)
                        .frame(width: 7, height: 7)
                }
                .frame(width: diameter - 9, height: diameter - 9)
                .animation(.easeOut(duration: 0.25), value: item.progress)
            case .paused:
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(MedxTheme.accent)
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
                .foregroundStyle(MedxTheme.accent)
        }
    }
}

// MARK: - Offline library

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
                ContentUnavailableView {
                    Label("No Downloads Yet", systemImage: "arrow.down.circle")
                } description: {
                    Text("Tap the download icon on any class to keep it on this device. Downloads play inside the app, even with no signal.")
                }
            } else {
                List {
                    Section {
                        MedxMetricsRow {
                            MedxMetric(
                                icon: "internaldrive.fill",
                                value: downloads.formattedTotalSize,
                                label: "on device",
                                color: MedxIconHue.blue
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
                        Text("Saved classes stay inside MedX Elite and are excluded from device backups. Watch progress is shared with the streaming copy of the same class.")
                    }

                    if !inProgress.isEmpty {
                        Section("Downloading") {
                            ForEach(inProgress) { row($0) }
                        }
                    }

                    if !finished.isEmpty {
                        Section("Saved on this device") {
                            ForEach(finished) { row($0) }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .medxBackdrop(.videos, intensity: 0.8)
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
            VideoPlayerView(video: video) { activeVideo = nil }
        }
        #if DEBUG
        // Screenshot runs only (`-medxScreen player-offline`): plays the saved test class.
        .task {
            guard MedxDemoMode.isOn,
                  UserDefaults.standard.string(forKey: "medxScreen") == "player-offline" else { return }
            try? await Task.sleep(nanoseconds: 800_000_000)
            activeVideo = finished.first(where: { $0.id == MedxOfflineFixture.videoId })?.video
        }
        #endif
    }

    private func row(_ item: DownloadedVideo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.state == .completed ? "play.fill" : "arrow.down")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(statusColor(item))
                .frame(width: 38, height: 38)
                .background(statusColor(item).opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.video.title.medxDisplayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(subtitle(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if item.state != .completed {
                    ProgressView(value: item.progress)
                        .tint(statusColor(item))
                }

                Text(item.statusLabel)
                    .font(.caption)
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
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                HapticManager.warning()
                downloads.remove(item.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            // A queue is the one place pausing is worth a gesture: it is the thing you reach for
            // when a download is eating the connection you are trying to watch something on.
            switch item.state {
            case .queued, .downloading:
                Button {
                    HapticManager.light()
                    downloads.pause(item.id)
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .tint(MedxTheme.warningOrange)
            case .paused, .failed:
                Button {
                    HapticManager.light()
                    downloads.resume(item.id)
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .tint(MedxTheme.successGreen)
            case .completed:
                Button {
                    HapticManager.light()
                    activeVideo = item.video
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .tint(MedxCandy.violet)
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
        case .queued, .downloading: return MedxTheme.accent
        }
    }
}
