import SwiftUI

/// The Library tab — every destination that is not one of the four browsables.
///
/// It is also the *only* way to those doors. Home used to offer Faceoff, Quick sitting and Custom
/// modules as launcher tiles as well, which meant three of the eleven below were the second copy of
/// something. Home is a dashboard and this is the launcher; nothing appears in both.
///
/// It was a grid of eleven tiles, each one a card with a hue-washed symbol, a title, a two-line detail
/// and a 132pt floor — a wall of colour with no order in it. Eleven labelled rows in three sections
/// read faster and draw at a fraction of the cost: a row is one fill and some text, a tile was a card
/// plus a mark plus a pill.
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
            ForEach(LibraryGroup.allCases) { group in
                Section {
                    ForEach(doors(in: group)) { door in
                        doorRow(door)
                    }
                } header: {
                    MedxHeader(group.title)
                }
            }
        }
        .medxList()
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                MedxSettingsMonogram()
            }
        }
        .navigationDestination(item: $appState.libraryDestination) { destination in
            switch destination {
            case .flashcards: FlashcardsSubjectListView()
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

    private func doorRow(_ door: LibraryDoor) -> some View {
        Button {
            HapticManager.light()
            door.action()
        } label: {
            // No lead figure: a door does not have one. Faceoff is not a number. Where there *is* a
            // figure worth showing it is a live count, and that belongs on the trailing edge as a badge.
            MedxRow(title: door.title, detail: door.detail) {
                HStack(spacing: 8) {
                    if let badge = door.badge {
                        MedxBadge(badge, tint: door.isUrgent ? MedxDS.correct : nil)
                    }
                    MedxChevron()
                }
            }
        }
        .buttonStyle(.plain)
        .medxListRow()
        .accessibilityLabel(door.title)
        .accessibilityValue(door.badge ?? "")
        .accessibilityHint(door.detail)
    }

    // MARK: - The doors

    private func doors(in group: LibraryGroup) -> [LibraryDoor] {
        doors.filter { $0.group == group }
    }

    private var doors: [LibraryDoor] {
        [
            LibraryDoor(
                id: "faceoff",
                group: .play,
                title: "Faceoff",
                detail: "One question, one minute, two of you",
                badge: waitingLobbies == 0 ? nil : "\(waitingLobbies) waiting",
                isUrgent: waitingLobbies > 0
            ) { appState.open(route: .faceoff) },

            LibraryDoor(
                id: "cards",
                group: .study,
                title: "Flashcards",
                detail: "Tap to flip, swipe for the next"
            ) { appState.open(route: .flashcards) },

            LibraryDoor(
                id: "vod",
                group: .study,
                title: "VOD feed",
                detail: "The raw bucket, newest first",
                badge: vod.unseenCount > 0 ? "\(vod.unseenCount) new" : nil,
                isUrgent: vod.unseenCount > 0
            ) { appState.open(route: .vodFeed) },

            LibraryDoor(
                id: "batch",
                group: .study,
                title: "Batch papers",
                detail: "The batch's own four"
            ) { appState.open(route: .batchPapers) },

            LibraryDoor(
                id: "custom",
                group: .study,
                title: "Custom modules",
                detail: "Papers either of you saved",
                badge: customModules.modules.isEmpty ? nil : "\(customModules.modules.count)"
            ) { appState.open(route: .customModules) },

            LibraryDoor(
                id: "quick",
                group: .study,
                title: "Quick sitting",
                detail: "Scope, length, mode, go"
            ) { appState.open(route: .quickSitting) },

            LibraryDoor(
                id: "search",
                group: .study,
                title: "Search",
                detail: "Full text across both banks"
            ) { appState.open(route: .search(nil)) },

            LibraryDoor(
                id: "bookmarks",
                group: .yours,
                title: "Bookmarks",
                detail: "Questions you kept",
                badge: bookmarkCount > 0 ? "\(bookmarkCount)" : nil
            ) { appState.showBookmarks = true },

            LibraryDoor(
                id: "downloads",
                group: .yours,
                title: "Downloads",
                detail: "Saved for no signal",
                badge: downloadBadge
            ) { appState.showDownloads = true },

            LibraryDoor(
                id: "log",
                group: .yours,
                title: "Activity log",
                detail: "Every sitting and class"
            ) { appState.showActivityLog = true },

            LibraryDoor(
                id: "settings",
                group: .yours,
                title: "Settings",
                detail: "Accent, reminders, the index"
            ) { appState.showSettings = true }
        ]
    }

    private var bookmarkCount: Int { activityStore.bookmarks(for: uid).count }

    private var waitingLobbies: Int { lobbyWatcher.theirs.count }

    /// In-flight downloads are the more urgent number, so they win the badge when there are any.
    private var downloadBadge: String? {
        let active = downloads.items.values.reduce(0) { total, item in
            switch item.state {
            case .queued, .downloading, .paused: return total + 1
            case .completed, .failed: return total
            }
        }
        if active > 0 { return "\(active) active" }
        let done = downloads.items.values.reduce(0) { $1.state == .completed ? $0 + 1 : $0 }
        return done > 0 ? "\(done)" : nil
    }
}

// MARK: - One door

/// Which third of the page a door belongs to.
enum LibraryGroup: String, CaseIterable, Identifiable {
    case play, study, yours

    var id: String { rawValue }

    var title: String {
        switch self {
        case .play: return "Play"
        case .study: return "Study"
        case .yours: return "Yours"
        }
    }
}

/// A door's content, kept as a value so the list is one `ForEach` over data rather than eleven
/// hand-placed rows — which is what let the old version drift into four near-identical row helpers.
///
/// No symbol and no hue, which is the whole change. Eleven hue-washed marks were the app's biggest
/// single block of decoration: a Faceoff bolt in pink told you nothing the word "Faceoff" did not, and
/// colour in this app now means outcome rather than location.
struct LibraryDoor: Identifiable {
    let id: String
    let group: LibraryGroup
    let title: String
    let detail: String
    let badge: String?
    /// Tints the badge. Only for something *waiting* — a dealt game, a new drop — never for a tally.
    let isUrgent: Bool
    let action: () -> Void

    init(
        id: String,
        group: LibraryGroup,
        title: String,
        detail: String,
        badge: String? = nil,
        isUrgent: Bool = false,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.group = group
        self.title = title
        self.detail = detail
        self.badge = badge
        self.isUrgent = isUrgent
        self.action = action
    }
}

// MARK: - Activity log, from here

/// `ActivityLogView` takes a binding so a deletion inside it updates the count on the Settings row that
/// owns the array. Library has no such array, so this owns one and fetches it — which also means opening
/// the log from here is a fresh read rather than whatever Settings last saw.
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
