import SwiftUI

// MARK: - Download control

/// One compact control covering every download state: save, pause, resume, retry, delete.
/// Used at the end of a class row in a subject, the VOD feed and the offline library.
struct VideoDownloadButton: View {
    let video: RecordedVideo

    @ObservedObject private var downloads = VideoDownloadStore.shared

    private var item: DownloadedVideo? { downloads.items[video.id] }

    var body: some View {
        Menu {
            menuItems
        } label: {
            glyph
        }
        .accessibilityLabel("Offline download for \(video.title.medxDisplayTitle)")
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
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(width: 32, height: 32)

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
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            case .downloading:
                MedxRing(fraction: item.progress, tint: MedxTheme.accent, lineWidth: 2.5)
                    .frame(width: 20, height: 20)
                    .overlay {
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(MedxTheme.accent)
                            .frame(width: 6, height: 6)
                    }
            case .paused:
                Image(systemName: "play.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(MedxTheme.accent)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(MedxOutcome.flagged)
            case .completed:
                Image(systemName: "checkmark")
                    .font(.caption.weight(.black))
                    .foregroundStyle(MedxOutcome.correct)
            }
        } else {
            Image(systemName: "arrow.down.to.line")
                .font(.caption.weight(.bold))
                .foregroundStyle(MedxTheme.accent)
        }
    }
}

// MARK: - Offline library

/// Everything saved on this device. Files live in the app's own container — nothing is exported
/// to Files or Photos — and play inside the app with no signal.
struct DownloadsView: View {
    @ObservedObject private var downloads = VideoDownloadStore.shared
    @State private var activeVideo: RecordedVideo?
    @State private var confirmDeleteAll = false

    private var inProgress: [DownloadedVideo] { downloads.inProgressItems }
    private var finished: [DownloadedVideo] { downloads.completedItems }

    private var subtitle: String {
        guard !downloads.items.isEmpty else { return "" }
        return "\(finished.count) saved · \(MedxFormat.bytes(downloads.totalBytes))"
    }

    var body: some View {
        Group {
            if downloads.items.isEmpty {
                MedxEmptyState(
                    "No downloads yet",
                    symbol: MedxFeature.downloads.symbol,
                    message: "Swipe left on any class to save it here. Saved classes play inside the app with no signal."
                )
            } else {
                list
            }
        }
        .navigationTitle(MedxFeature.downloads.title)
        .navigationSubtitle(subtitle)
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
            Text("This frees \(MedxFormat.bytes(downloads.totalBytes)) on this device. You can download them again any time.")
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

    // MARK: - List

    private var list: some View {
        List {
            Section {
                MedxStatRow {
                    MedxStatTile(
                        MedxFormat.bytes(downloads.totalBytes),
                        label: "on device",
                        symbol: "internaldrive.fill",
                        hue: MedxFeature.downloads.color
                    )
                    MedxStatTile(
                        "\(finished.count)",
                        label: "ready",
                        symbol: "checkmark.circle.fill",
                        hue: MedxOutcome.correct
                    )
                    MedxStatTile(
                        "\(inProgress.count)",
                        label: "in queue",
                        symbol: "arrow.down.circle.fill",
                        hue: MedxOutcome.flagged
                    )
                }
                .padding(.vertical, MedxSpace.xs)
            } footer: {
                Text("Saved classes stay inside MedX Elite and are left out of device backups. Watch progress is shared with the streaming copy of the same class.")
            }

            if !inProgress.isEmpty {
                Section("Downloading") {
                    ForEach(inProgress) { row($0) }
                }
            }

            if !finished.isEmpty {
                Section {
                    ForEach(finished) { row($0) }
                } header: {
                    Text("Saved on this device")
                } footer: {
                    Text(MedxCopy.downloadGestures)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ item: DownloadedVideo) -> some View {
        HStack(spacing: MedxSpace.m) {
            Button {
                guard item.state == .completed else { return }
                HapticManager.light()
                activeVideo = item.video
            } label: {
                HStack(spacing: MedxSpace.m) {
                    MedxSymbolTile(
                        item.state == .completed ? "play.fill" : "arrow.down",
                        hue: statusColor(item),
                        size: 36
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.video.title.medxDisplayTitle)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(detail(for: item))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if item.state != .completed {
                            ProgressView(value: item.progress)
                                .tint(statusColor(item))
                                .padding(.top, 2)
                        }
                        Text(item.statusLabel)
                            .font(.caption)
                            .foregroundStyle(item.state == .failed ? MedxOutcome.flagged : Color.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(item.video.title.medxDisplayTitle)
            .accessibilityValue(item.statusLabel)
            .accessibilityHint(item.state == .completed ? "Plays this download" : "")

            VideoDownloadButton(video: item.video)
        }
        .padding(.vertical, 2)
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
                .tint(MedxOutcome.flagged)
            case .paused, .failed:
                Button {
                    HapticManager.light()
                    downloads.resume(item.id)
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .tint(MedxOutcome.correct)
            case .completed:
                Button {
                    HapticManager.light()
                    activeVideo = item.video
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .tint(MedxTheme.accent)
            }
        }
    }

    private func detail(for item: DownloadedVideo) -> String {
        var parts = [item.video.subject]
        if let faculty = item.video.faculty, !faculty.isEmpty { parts.append(faculty) }
        return parts.joined(separator: " · ")
    }

    private func statusColor(_ item: DownloadedVideo) -> Color {
        switch item.state {
        case .completed: return MedxOutcome.correct
        case .failed: return MedxOutcome.flagged
        case .paused: return MedxOutcome.pending
        case .queued, .downloading: return MedxTheme.accent
        }
    }
}
