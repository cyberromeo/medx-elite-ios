import SwiftUI
import UIKit

/// The ARISE VOD bucket, listed.
///
/// This is a *feed*, not a library: roughly 2,900 recordings ordered purely by upload date,
/// newest first, grouped under day headers so scrolling down is scrolling back in time. It pages
/// 48 at a time because pulling the whole collection would be a 2,900-document read every visit.
///
/// The bucket has no titles — only file keys — so names are humanised from the key and the raw
/// key stays visible on the row. `medx_videos` is the curated library; this is what is behind it.
public struct VodFeedView: View {
    @ObservedObject private var watcher = MedxVodWatcher.shared
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var downloads = VideoDownloadStore.shared

    @State private var items: [MedxVodItem] = []
    @State private var cursor: String?
    @State private var isDone = false
    @State private var isLoading = true
    @State private var failure: String?
    @State private var query = ""
    @State private var onlyCC = false
    @State private var autoPages = 0
    @State private var playing: RecordedVideo?
    /// Frozen when the screen appears so the "new" marks do not disappear as the page marks
    /// itself seen underneath the reader.
    @State private var seenAtAppear: String?

    public init() {}

    private static let pageSize = 48

    /// Auto-paging stops after three pages.
    ///
    /// An uncapped sentinel is a trap: it sits just under the last row, so every page it loads
    /// puts it back in range and it walks the entire bucket in one visit — thousands of reads and
    /// a list that stops answering taps. Three pages is about two screens of flicking, which is
    /// as far as anyone goes before deciding. Past that, paging is a tap.
    private static let autoPageLimit = 3

    private var uid: String? { authService.currentSession?.uid }

    private var shown: [MedxVodItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            if onlyCC, !item.hasSubtitles { return false }
            guard !needle.isEmpty else { return true }
            return item.display.title.localizedCaseInsensitiveContains(needle)
                || item.rawKey.localizedCaseInsensitiveContains(needle)
                || item.folder.localizedCaseInsensitiveContains(needle)
        }
    }

    /// Day buckets in insertion order — the query already came back newest-first.
    private var days: [MedxVodDay] {
        var order: [String] = []
        var buckets: [String: (label: String, items: [MedxVodItem])] = [:]
        let calendar = Calendar.current

        for item in shown {
            let key: String
            let label: String
            if let date = item.uploadedAt {
                let day = calendar.startOfDay(for: date)
                key = String(day.timeIntervalSince1970)
                label = day.formatted(.dateTime.weekday(.abbreviated).day().month(.wide).year())
            } else {
                key = "undated"
                label = "Undated"
            }
            if buckets[key] == nil {
                buckets[key] = (label, [])
                order.append(key)
            }
            buckets[key]?.items.append(item)
        }

        return order.compactMap { key in
            guard let bucket = buckets[key] else { return nil }
            return MedxVodDay(id: key, label: bucket.label, items: bucket.items)
        }
    }

    private var freshCount: Int {
        guard let seenAtAppear else { return 0 }
        return items.reduce(0) { total, item in
            guard let raw = item.uploadedAtRaw else { return total }
            return raw > seenAtAppear ? total + 1 : total
        }
    }

    /// Bucket recordings saved on this device, counted against what is loaded rather than against
    /// the whole download list — the Downloads screen is where the total lives.
    private var savedHere: Int {
        items.reduce(0) { $0 + (downloads.isDownloaded($1.id) ? 1 : 0) }
    }

    private var subtitle: String {
        let newest = items.first?.uploadedAt ?? watcher.meta?.lastUploadedAt
        guard let newest else { return "Every recording, newest first" }
        return "Latest drop \(newest.formatted(.dateTime.day().month(.abbreviated).year()))"
    }

    private var footerLine: String {
        var parts: [String] = []
        if freshCount > 0 {
            parts.append(freshCount == 1 ? "1 new since you last opened this." : "\(freshCount) new since you last opened this.")
        }
        if !query.isEmpty {
            // Said out loud, because a filter that silently only covers part of a collection is
            // worse than no filter: the bucket has no text index.
            parts.append("Searching the \(MedxFormat.count(items.count)) recordings loaded so far. Load more to search further back.")
        }
        parts.append(MedxCopy.classGestures)
        return parts.joined(separator: " ")
    }

    public var body: some View {
        List {
            Section {
                MedxStatRow {
                    MedxStatTile(
                        "\(MedxFormat.count(items.count))\(isDone ? "" : "+")",
                        label: "loaded here",
                        symbol: "square.stack.3d.down.right.fill",
                        hue: MedxFeature.vod.color
                    )
                    MedxStatTile(
                        MedxFormat.count(watcher.meta?.count ?? 0),
                        label: "added by sync",
                        symbol: "plus.circle.fill",
                        hue: MedxFeature.importClasses.color
                    )
                    MedxStatTile(
                        "\(savedHere)",
                        label: "saved here",
                        symbol: "arrow.down.circle.fill",
                        hue: MedxFeature.downloads.color
                    )
                }
                .padding(.vertical, MedxSpace.xs)
            } footer: {
                Text(footerLine)
            }

            if let failure {
                Section {
                    HStack(spacing: MedxSpace.m) {
                        Label(failure, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: MedxSpace.s)
                        Button("Retry") {
                            Task { await loadMore(auto: false) }
                        }
                        .medxSecondary(size: .small)
                    }
                }
            }

            if isLoading, items.isEmpty {
                Section {
                    MedxPlaceholderRows(count: 8)
                }
            } else if shown.isEmpty {
                Section {
                    MedxEmptyState(
                        query.isEmpty && !onlyCC ? "No recordings yet" : "Nothing loaded matches",
                        symbol: query.isEmpty && !onlyCC ? "antenna.radiowaves.left.and.right.slash" : "magnifyingglass",
                        message: query.isEmpty && !onlyCC
                            ? "Nothing has been uploaded yet."
                            : "Load another page, or clear the filter."
                    )
                }
            } else {
                ForEach(days) { day in
                    Section {
                        ForEach(day.items) { item in
                            row(item)
                        }
                    } header: {
                        Text(day.label)
                    }
                }
            }

            pagingSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(MedxFeature.vod.title)
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: "File key, folder or name")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Toggle(isOn: $onlyCC) {
                    Label("Subtitled only", systemImage: "captions.bubble")
                }
                .toggleStyle(.button)
                .accessibilityLabel("Only recordings with subtitles")
            }
        }
        .refreshable { await reload() }
        .task {
            if seenAtAppear == nil { seenAtAppear = watcher.seenWatermark }
            guard items.isEmpty else { return }
            await loadMore(auto: false)
        }
        .fullScreenCover(item: $playing) { video in
            VideoPlayerView(video: video) { playing = nil }
        }
    }

    // MARK: - Rows

    private func row(_ item: MedxVodItem) -> some View {
        let label = item.display
        let watched = activityStore.entry(for: item.id, uid: uid)
        let isNew = seenAtAppear.map { (item.uploadedAtRaw ?? "") > $0 } ?? false
        let video = item.asRecordedVideo
        let saved = downloads.isDownloaded(item.id)
        let playable = !item.streamUrl.isEmpty

        return HStack(spacing: MedxSpace.m) {
            Button {
                guard playable else {
                    HapticManager.error()
                    return
                }
                HapticManager.light()
                playing = video
            } label: {
                HStack(spacing: MedxSpace.m) {
                    // No poster. The bucket's thumbnails are a mix of missing, wrong-aspect and
                    // identical grey frames, so 48 of them per page read as noise.
                    MedxSymbolTile(
                        rowGlyph(watched: watched, saved: saved),
                        hue: rowHue(watched: watched, saved: saved),
                        size: 36
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(label.title.medxDisplayTitle)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text(detailLine(item, label: label))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let watched, !watched.isCompleted, watched.progress > 0.02 {
                            ProgressView(value: watched.progress)
                                .padding(.top, 2)
                        }
                    }

                    Spacer(minLength: 0)

                    if isNew {
                        Text("New")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(MedxTheme.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!playable)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label.title.medxDisplayTitle)
            .accessibilityValue([label.sub, item.formattedDuration, isNew ? "new" : "", saved ? "saved offline" : ""]
                .filter { !$0.isEmpty }
                .joined(separator: ", "))

            // A bucket recording is an HLS stream like any class, so the same downloader takes
            // it. The control is a sibling of the play button, not inside it: a `Menu` nested in
            // a `Button` label never receives the tap.
            if playable {
                VideoDownloadButton(video: video)
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if playable {
                Button {
                    HapticManager.light()
                    playing = video
                } label: {
                    Label((watched?.resumePosition ?? 0) > 0 ? "Resume" : "Play", systemImage: "play.fill")
                }
                .tint(MedxTheme.accent)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if playable {
                if saved {
                    Button(role: .destructive) {
                        HapticManager.warning()
                        downloads.remove(item.id)
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
                    .tint(MedxOutcome.correct)
                }
            }
        }
        .contextMenu {
            if playable {
                Button {
                    HapticManager.light()
                    playing = video
                } label: {
                    Label((watched?.resumePosition ?? 0) > 0 ? "Resume" : "Play", systemImage: "play.circle")
                }

                if saved {
                    Button(role: .destructive) {
                        HapticManager.warning()
                        downloads.remove(item.id)
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
            }

            Button {
                UIPasteboard.general.string = item.rawKey
            } label: {
                Label("Copy file key", systemImage: "doc.on.doc")
            }
        }
    }

    private func detailLine(_ item: MedxVodItem, label: (title: String, sub: String, opaque: Bool)) -> String {
        var parts: [String] = []
        if !label.sub.isEmpty { parts.append(label.sub) }
        if !item.formattedDuration.isEmpty { parts.append(item.formattedDuration) }
        if item.hasSubtitles { parts.append("Subtitled") }
        if item.streamUrl.isEmpty { parts.append("No stream") }
        return parts.joined(separator: " · ")
    }

    /// Offline beats watched beats plain, because "is this on the device" is the thing you are
    /// scanning for on a feed you cannot search.
    private func rowGlyph(watched: WatchHistoryEntry?, saved: Bool) -> String {
        if saved { return "arrow.down.circle.fill" }
        if watched?.isCompleted == true { return "checkmark" }
        return "antenna.radiowaves.left.and.right"
    }

    private func rowHue(watched: WatchHistoryEntry?, saved: Bool) -> Color {
        if saved { return MedxFeature.downloads.color }
        if watched?.isCompleted == true { return MedxOutcome.correct }
        return MedxFeature.vod.color
    }

    // MARK: - Paging

    @ViewBuilder
    private var pagingSection: some View {
        if !items.isEmpty {
            Section {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if !isDone {
                    // The row itself is the sentinel: when it scrolls into view, the next page
                    // loads — capped, for the reason above.
                    Button {
                        HapticManager.light()
                        Task { await loadMore(auto: false) }
                    } label: {
                        Label("Older uploads", systemImage: "arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .onAppear {
                        guard autoPages < Self.autoPageLimit, query.isEmpty else { return }
                        Task { await loadMore(auto: true) }
                    }
                } else {
                    Text("That is everything, \(MedxFormat.count(items.count)) recordings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Data

    private func reload() async {
        cursor = nil
        isDone = false
        autoPages = 0
        items = []
        await loadMore(auto: false)
    }

    private func loadMore(auto: Bool) async {
        guard !isDone else { return }
        isLoading = true
        failure = nil
        defer { isLoading = false }

        guard let token = try? await authService.getValidIdToken() else {
            failure = "Sign in again to load recordings."
            return
        }

        do {
            let page = try await FirestoreService.shared.fetchVodPage(
                pageSize: Self.pageSize,
                cursor: cursor,
                idToken: token
            )
            let seen = Set(items.map(\.id))
            items.append(contentsOf: page.items.filter { !seen.contains($0.id) })
            cursor = page.cursor
            isDone = page.done
            if auto { autoPages += 1 }

            // The newest upload on the first page is what "seen" means. Written after the page
            // has landed, and the marks read `seenAtAppear`, which was frozen before it.
            watcher.markSeen(newestUploadedAt: items.first?.uploadedAtRaw)
        } catch {
            failure = "That page did not load. Check your connection and try again."
        }
    }
}

/// One day's uploads.
struct MedxVodDay: Identifiable, Hashable {
    let id: String
    let label: String
    let items: [MedxVodItem]
}
