import SwiftUI

/// The Library tab: everything that is not one of the four daily tabs, as a grouped list of
/// doors. Four sections say what kind of thing each door is — study, watch, play, yours — and
/// every door pushes, so Back always means the same thing. Settings is the profile button's and
/// the batch papers live under Tests, so neither is here.
///
/// Quick sitting is the one door that is a sheet: it is a builder that ends in a sitting, and
/// `AppState.startSitting` knows to wait for a sheet to go before the runner comes up.
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
        List {
            Section("Study") {
                door(.flashcards) { FlashcardsSubjectListView() }
                door(.customModules, badge: countBadge(customModules.modules.count)) { CustomModulesView() }
                routeDoor(.quickSitting, route: .quickSitting)
                door(.search) { MedxQuestionSearchView() }
            }

            Section("Watch") {
                door(.vod, badge: vod.unseenCount > 0 ? "\(vod.unseenCount) new" : nil) { VodFeedView() }
                door(.importClasses) { VodImportView() }
            }

            Section("Play") {
                door(.faceoff, badge: waitingBadge) { FaceoffLobbyView() }
            }

            Section("Yours") {
                door(.bookmarks, badge: countBadge(activityStore.bookmarks(for: uid).count)) {
                    BookmarkedQuestionsView(uid: uid)
                }
                door(.downloads, badge: downloadBadge) { DownloadsView() }
                door(.watchHistory, badge: countBadge(activityStore.watchHistory(for: uid).count)) {
                    WatchHistoryView(uid: uid)
                }
                door(.activityLog) { MedxActivityLogHost(uid: uid) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(MedxFeature.library.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                MedxProfileButton()
            }
        }
        // A door opened from outside — a notification, Spotlight, Siri, a widget, the iPad
        // sidebar — pushes through here rather than through a row.
        .navigationDestination(item: $appState.libraryDestination) { destination in
            switch destination {
            case .flashcards: FlashcardsSubjectListView()
            case .vodFeed: VodFeedView()
            case .importVod: VodImportView()
            case .batchPapers: BatchPapersView()
            case .customModules: CustomModulesView()
            case .bookmarks: BookmarkedQuestionsView(uid: uid)
            case .downloads: DownloadsView()
            case .watchHistory: WatchHistoryView(uid: uid)
            case .activityLog: MedxActivityLogHost(uid: uid)
            case .search(let seed): MedxQuestionSearchView(seed: seed ?? "")
            case .faceoff: FaceoffLobbyView()
            }
        }
        .task {
            await customModules.loadIfNeeded(uid: uid)
            _ = await vod.refreshFromForeground()
            lobbyWatcher.start()
        }
    }

    // MARK: - Doors

    /// A door that pushes.
    private func door<Destination: View>(
        _ feature: MedxFeature,
        badge: String? = nil,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            doorLabel(feature, badge: badge)
        }
        .accessibilityLabel(feature.title)
        .accessibilityValue(badge ?? "")
    }

    /// A door that goes through `AppState` — the quick-sitting sheet.
    private func routeDoor(_ feature: MedxFeature, route: MedxRoute, badge: String? = nil) -> some View {
        Button {
            HapticManager.light()
            appState.open(route: route)
        } label: {
            HStack(spacing: MedxSpace.s) {
                doorLabel(feature, badge: badge)
                MedxRowChevron()
            }
            .foregroundStyle(Color.primary)
        }
        .accessibilityLabel(feature.title)
        .accessibilityValue(badge ?? "")
    }

    private func doorLabel(_ feature: MedxFeature, badge: String?) -> some View {
        HStack(spacing: MedxSpace.m) {
            MedxTileLabel(feature.title, symbol: feature.symbol, hue: feature.color)
            Spacer(minLength: MedxSpace.s)
            if let badge {
                Text(badge)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Badges

    private func countBadge(_ count: Int) -> String? {
        count > 0 ? MedxFormat.count(count) : nil
    }

    private var waitingBadge: String? {
        let waiting = lobbyWatcher.theirs.count
        return waiting > 0 ? "\(waiting) waiting" : nil
    }

    /// In-flight downloads are the more urgent number, so they win the badge when there are any.
    private var downloadBadge: String? {
        let active = downloads.activeCount
        if active > 0 { return "\(active) active" }
        return countBadge(downloads.completedItems.count)
    }
}
