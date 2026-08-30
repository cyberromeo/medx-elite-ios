import SwiftUI

/// The Library tab — everything that is not a study surface in its own right.
///
/// `Videos` used to be the fifth tab. Adding Faceoff, the custom modules and the raw VOD feed
/// would have made eight destinations for five slots, so the ones that are *libraries* rather
/// than daily habits moved in here: the class library and the bucket feed behind it, the four
/// ARISE batch papers, the duel, the saved papers, and the saved questions.
///
/// Classes is deliberately the first and largest row. It is the one thing here that was a tab
/// yesterday, and burying it would be the cost of this rearrangement rather than its point.
public struct LibraryView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var downloads = VideoDownloadStore.shared
    @ObservedObject private var customModules = MedxCustomModuleStore.shared
    @ObservedObject private var vod = MedxVodWatcher.shared
    @ObservedObject private var lobbyWatcher = MedxLobbyWatcher.shared

    public init() {}

    private var uid: String? { authService.currentSession?.uid }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                MedxPageHeader(
                    section: .library,
                    title: "Library",
                    lead: "The class library and the raw bucket behind it, the batch papers, "
                        + "Faceoff, and everything either of you has saved.",
                    sticker: "filebox"
                )

                classesCard

                watchGroup
                playGroup
                buildGroup
                savedGroup

                settingsRow
            }
            .padding(.horizontal, MedxSurface.gutter)
            .padding(.top, 6)
            .padding(.bottom, 28)
        }
        .background(MedxSurface.groupedBackground.ignoresSafeArea())
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ProfileSettingsButton()
            }
        }
        .navigationDestination(item: $appState.libraryDestination) { destination in
            switch destination {
            case .classes: VideosBatchListView()
            case .vodFeed: VodFeedView()
            case .batchPapers: BatchPapersView()
            }
        }
        .task {
            await customModules.loadIfNeeded(uid: uid)
            await vod.refreshFromForeground()
            lobbyWatcher.start()
        }
    }

    // MARK: - Classes

    /// The one row that gets a card of its own, because it used to be a tab.
    private var classesCard: some View {
        Button {
            HapticManager.light()
            appState.open(route: .classes)
        } label: {
            HStack(spacing: 14) {
                MedxSticker("clapper", size: 40, tilt: -8)
                    .frame(width: 54, height: 54)
                    .background(MedxCandy.violetSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Classes")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Recorded ARISE lectures by batch and subject")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)

                    if activeDownloads > 0 {
                        MedxPill(
                            activeDownloads == 1 ? "1 downloading" : "\(activeDownloads) downloading",
                            hue: MedxCandy.violet,
                            icon: "arrow.down"
                        )
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 0)

                MedxDisclosure()
            }
            .padding(16)
            .medxCard(raised: true)
            .contentShape(RoundedRectangle(cornerRadius: MedxSurface.cardRadius, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
        .accessibilityLabel("Classes")
        .accessibilityHint("Recorded lectures by batch and subject")
    }

    private var activeDownloads: Int {
        downloads.items.values.reduce(0) { total, item in
            switch item.state {
            case .queued, .downloading, .paused: return total + 1
            case .completed, .failed: return total
            }
        }
    }

    // MARK: - Groups

    private var watchGroup: some View {
        group("Watch") {
            row(
                sticker: "satellite",
                hue: MedxCandy.blue,
                title: "VOD feed",
                detail: "Every recording in the ARISE bucket, newest first",
                badge: vod.unseenCount > 0 ? "\(vod.unseenCount) new" : nil
            ) {
                appState.open(route: .vodFeed)
            }

            row(
                sticker: "phone",
                hue: MedxCandy.violet,
                title: "Downloads",
                detail: "Classes saved for no signal",
                badge: completedDownloads > 0 ? "\(completedDownloads)" : nil
            ) {
                appState.showDownloads = true
            }
        }
    }

    private var playGroup: some View {
        group("Play") {
            row(
                sticker: "bolt",
                hue: MedxCandy.pink,
                title: "Faceoff",
                detail: "One question, one minute, two of you",
                badge: waitingLobbies == 0 ? nil : "\(waitingLobbies) waiting"
            ) {
                appState.open(route: .faceoff)
            }

            row(
                sticker: "flag",
                hue: MedxCandy.tangerine,
                title: "Batch papers",
                detail: "The batch's own four, keyed and unkeyed",
                badge: nil
            ) {
                appState.open(route: .batchPapers)
            }
        }
    }

    private var buildGroup: some View {
        group("Build") {
            row(
                sticker: "memo",
                hue: MedxCandy.butter,
                title: "Custom modules",
                detail: "Papers either of you has saved, run as one sitting",
                badge: customModules.modules.isEmpty ? nil : "\(customModules.modules.count)"
            ) {
                appState.open(route: .customModules)
            }

            row(
                sticker: "crystal",
                hue: MedxCandy.mint,
                title: "Quick sitting",
                detail: "Filter by subject, scope and length, then go",
                badge: nil
            ) {
                appState.open(route: .quickSitting)
            }

            row(
                sticker: "search",
                hue: MedxCandy.lime,
                title: "Search questions",
                detail: "Full text across everything indexed",
                badge: nil
            ) {
                appState.open(route: .search(nil))
            }
        }
    }

    private var savedGroup: some View {
        group("Saved") {
            row(
                sticker: "bulb",
                hue: MedxCandy.butter,
                title: "Bookmarks",
                detail: "Questions you double-tapped in the runner",
                badge: bookmarkCount > 0 ? "\(bookmarkCount)" : nil
            ) {
                appState.showBookmarks = true
            }

            NavigationLink {
                MedxActivityLogHost(uid: uid)
            } label: {
                rowLabel(
                    sticker: "bars",
                    hue: MedxCandy.mint,
                    title: "Activity log",
                    detail: "Every sitting and every class, newest first",
                    badge: nil
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var settingsRow: some View {
        Button {
            HapticManager.light()
            appState.showSettings = true
        } label: {
            rowLabel(
                sticker: "gear",
                hue: MedxCandy.sky,
                title: "Settings",
                detail: "Accent, reminders, the question index, diagnostics",
                badge: nil
            )
        }
        .buttonStyle(.plain)
    }

    private var bookmarkCount: Int { activityStore.bookmarks(for: uid).count }

    private var waitingLobbies: Int { lobbyWatcher.theirs.count }

    private var completedDownloads: Int {
        downloads.items.values.reduce(0) { $1.state == .completed ? $0 + 1 : $0 }
    }

    // MARK: - Row plumbing

    private func group<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MedxSectionHeader(title)
            VStack(spacing: 8) {
                content()
            }
        }
        .medxScrollReveal()
    }

    private func row(
        sticker: String,
        hue: Color,
        title: String,
        detail: String,
        badge: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.light()
            action()
        } label: {
            rowLabel(sticker: sticker, hue: hue, title: title, detail: detail, badge: badge)
        }
        .buttonStyle(.plain)
    }

    private func rowLabel(
        sticker: String,
        hue: Color,
        title: String,
        detail: String,
        badge: String?
    ) -> some View {
        HStack(spacing: 14) {
            MedxSticker(sticker, size: 28, tilt: -6)
                .frame(width: 38, height: 38)
                .background(hue.opacity(0.18), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)

            if let badge {
                MedxPill(badge, hue: hue, weight: .solid)
            }

            MedxDisclosure()
        }
        .padding(14)
        .frame(minHeight: 62)
        .medxCard()
        .contentShape(RoundedRectangle(cornerRadius: MedxSurface.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(badge ?? "")
        .accessibilityHint(detail)
    }
}

// MARK: - Activity log, from here

/// `ActivityLogView` takes a binding so a deletion inside it updates the count on the Settings
/// row that owns the array. Library has no such array, so this owns one and fetches it — which
/// also means opening the log from here is a fresh read rather than whatever Settings last saw.
struct MedxActivityLogHost: View {
    let uid: String?

    @State private var attempts: [SittingAttempt] = []
    @State private var isLoading = true

    var body: some View {
        ActivityLogView(uid: uid, attempts: $attempts)
            .overlay {
                if isLoading, attempts.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .task {
                guard isLoading, let uid else {
                    isLoading = false
                    return
                }
                if let token = try? await AuthService.shared.getValidIdToken() {
                    attempts = (try? await FirestoreService.shared.fetchUserAttempts(
                        uid: uid,
                        idToken: token
                    )) ?? []
                }
                isLoading = false
            }
    }
}
