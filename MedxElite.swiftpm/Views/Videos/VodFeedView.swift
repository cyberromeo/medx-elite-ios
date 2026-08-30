import SwiftUI

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

    @State private var items: [MedxVodItem] = []
    @State private var cursor: String?
    @State private var isDone = false
    @State private var isLoading = true
    @State private var failure: String?
    @State private var query = ""
    @State private var onlyCC = false
    @State private var autoPages = 0
    @State private var playing: RecordedVideo?
    /// Frozen when the screen appears so the "new" flashes do not disappear as the page marks
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

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                metaCard
                tools

                if let failure {
                    errorNote(failure)
                }

                ForEach(days) { day in
                    daySection(day)
                }

                footer
            }
            .padding(.horizontal, MedxSurface.gutter)
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
        .background(MedxSurface.groupedBackground.ignoresSafeArea())
        .navigationTitle("VOD feed")
        .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Header and meta

    private var header: some View {
        MedxPageHeader(
            section: .vod,
            title: "VOD feed",
            lead: "Every recording in the ARISE bucket, newest upload first. Scroll down to go "
                + "back in time.",
            sticker: "satellite"
        )
    }

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Latest drop")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(latestDropLine)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 8)
                MedxSticker("satellite", size: 40, tilt: 8)
            }

            MedxMetricsRow {
                MedxMetric(
                    icon: "square.stack.3d.down.right.fill",
                    value: "\(items.count.formatted())\(isDone ? "" : "+")",
                    label: "loaded here",
                    color: MedxCandy.blue
                )
                MedxMetric(
                    icon: "clock.arrow.circlepath",
                    value: watcher.meta?.updatedAt?.formatted(.relative(presentation: .numeric)) ?? "—",
                    label: "bucket scanned",
                    color: MedxTheme.indigoAccent
                )
                MedxMetric(
                    icon: "plus.circle.fill",
                    value: (watcher.meta?.count ?? 0).formatted(),
                    label: "added by sync",
                    color: MedxTheme.tealAccent
                )
            }

            if freshCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption2.weight(.bold))
                    Text(freshCount == 1
                         ? "1 new since you last opened this"
                         : "\(freshCount) new since you last opened this")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(MedxCandy.onSoft(MedxCandy.blue))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .medxCard()
    }

    private var latestDropLine: String {
        let newest = items.first?.uploadedAt ?? watcher.meta?.lastUploadedAt
        guard let newest else { return "—" }
        return newest.formatted(.dateTime.day().month(.wide).year())
    }

    // MARK: - Tools

    private var tools: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("File key, folder or name", text: $query)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .submitLabel(.search)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(MedxSurface.fieldFill, in: Capsule())

                Button {
                    HapticManager.selection()
                    onlyCC.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "captions.bubble")
                            .font(.caption.weight(.bold))
                        Text("CC")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(onlyCC ? MedxCandy.onSoft(MedxCandy.blue) : .secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(onlyCC ? MedxCandy.blueSoft : MedxSurface.fieldFill, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Only recordings with subtitles")
                .accessibilityAddTraits(onlyCC ? [.isButton, .isSelected] : .isButton)
            }

            if !query.isEmpty {
                // Said out loud, because a filter that silently only covers part of a collection
                // is worse than no filter: the bucket has no text index, so `folder` is the only
                // field a server-side search could use and it needs an exact code.
                Text("Searching the \(items.count.formatted()) loaded so far — the bucket has no "
                     + "text index, so load more to widen it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Rows

    private func daySection(_ day: MedxVodDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MedxRuleHeader(day.label, count: day.items.count)

            ForEach(day.items) { item in
                row(item)
            }
        }
        .medxScrollReveal()
    }

    private func row(_ item: MedxVodItem) -> some View {
        let label = item.display
        let watched = activityStore.entry(for: item.id, uid: uid)
        let isNew = seenAtAppear.map { (item.uploadedAtRaw ?? "") > $0 } ?? false

        return Button {
            guard !item.streamUrl.isEmpty else {
                HapticManager.error()
                return
            }
            HapticManager.light()
            playing = item.asRecordedVideo
        } label: {
            HStack(spacing: 12) {
                // No poster. The bucket's thumbnails are a mix of missing, wrong-aspect and
                // identical grey frames, so 48 of them per page read as noise — a stream mark
                // says "this is a live HLS link" in a fifth of the width and never mis-loads.
                Image(systemName: watched?.isCompleted == true ? "checkmark" : "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(watched?.isCompleted == true
                                     ? MedxTheme.successGreen
                                     : MedxCandy.onSoft(MedxCandy.blue))
                    .frame(width: 36, height: 36)
                    .background(
                        watched?.isCompleted == true
                            ? MedxTheme.successGreen.opacity(0.16)
                            : MedxCandy.blueSoft,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(label.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text([label.sub, item.formattedDuration, item.streamUrl.isEmpty ? "no stream" : nil]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: " · "))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    if let watched, !watched.isCompleted, watched.progress > 0.02 {
                        ProgressView(value: watched.progress)
                            .tint(MedxCandy.blue)
                            .frame(maxWidth: 120)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    if isNew {
                        MedxPill("new", hue: MedxCandy.blue, weight: .solid)
                    }
                    if item.hasSubtitles {
                        Image(systemName: "captions.bubble")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(12)
            .frame(minHeight: 58)
            .medxCard()
            .contentShape(RoundedRectangle(cornerRadius: MedxSurface.cardRadius, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
        .disabled(item.streamUrl.isEmpty)
        .accessibilityLabel(label.title)
        .accessibilityValue([label.sub, item.formattedDuration, isNew ? "new" : ""]
            .filter { !$0.isEmpty }
            .joined(separator: ", "))
    }

    // MARK: - Footer, states, paging

    @ViewBuilder
    private var footer: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else if shown.isEmpty {
            emptyState
        }

        if !isDone, !isLoading {
            // The sentinel. `onAppear` is the SwiftUI equivalent of the web version's
            // intersection observer, and it is capped for the same reason.
            Color.clear
                .frame(height: 1)
                .onAppear {
                    guard autoPages < Self.autoPageLimit, query.isEmpty else { return }
                    Task { await loadMore(auto: true) }
                }

            Button {
                HapticManager.light()
                Task { await loadMore(auto: false) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down")
                        .font(.footnote.weight(.bold))
                    Text("Older uploads")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }

        if isDone, !items.isEmpty {
            Text("That is the whole bucket — \(items.count.formatted()) recordings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                query.isEmpty && !onlyCC ? "The bucket index is empty" : "Nothing loaded matches",
                systemImage: query.isEmpty && !onlyCC ? "antenna.radiowaves.left.and.right.slash" : "magnifyingglass"
            )
        } description: {
            Text(query.isEmpty && !onlyCC
                 ? "medx_vod has no documents with an uploadedAt to order by."
                 : "Load another page, or clear the filter.")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func errorNote(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(MedxTheme.warningOrange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Retry") {
                Task { await loadMore(auto: false) }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(12)
        .medxCard()
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
            failure = "Sign in again to read the bucket."
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
            // has landed, and the flashes read `seenAtAppear`, which was frozen before it.
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
