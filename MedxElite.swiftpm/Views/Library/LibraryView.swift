import SwiftUI

/// The Library tab — everything that is not a daily habit in its own right.
///
/// Four of the five tabs are things you open without a reason: the dashboard, the bank, the
/// papers, the classes. Everything else is a place you go *to*, and a grid says that better than
/// a list does — a list implies an order to work through, a grid is a set of doors. Flashcards
/// leads it, because it was a tab yesterday and burying it would be the cost of this
/// rearrangement rather than its point.
public struct LibraryView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var activityStore = ActivityStore.shared
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var downloads = VideoDownloadStore.shared
    @ObservedObject private var customModules = MedxCustomModuleStore.shared
    @ObservedObject private var vod = MedxVodWatcher.shared
    @ObservedObject private var lobbyWatcher = MedxLobbyWatcher.shared

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize

    public init() {}

    private var uid: String? { authService.currentSession?.uid }

    /// Two up on a phone, four on an iPad. At an accessibility text size the grid collapses to one
    /// column: a tile whose title has wrapped to three lines is not a grid any more, and `List`
    /// would have been the honest layout at that size all along.
    private var columns: [GridItem] {
        let count = typeSize.isAccessibilitySize ? 1 : (sizeClass == .regular ? 4 : 2)
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    public var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(tiles) { tile in
                    LibraryTile(tile: tile)
                }
            }
            .padding(.horizontal, MedxSurface.gutter)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .medxPage(.library)
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ProfileSettingsButton()
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

    // MARK: - The grid

    private var tiles: [LibraryTileModel] {
        [
            LibraryTileModel(
                id: "cards",
                title: "Flashcards",
                detail: "Tap to flip, swipe for the next",
                symbol: "rectangle.stack.fill",
                hue: MedxCandy.butter,
                badge: nil
            ) { appState.open(route: .flashcards) },

            LibraryTileModel(
                id: "vod",
                title: "VOD feed",
                detail: "The raw bucket, newest first",
                symbol: "antenna.radiowaves.left.and.right",
                hue: MedxCandy.blue,
                badge: vod.unseenCount > 0 ? "\(vod.unseenCount) new" : nil
            ) { appState.open(route: .vodFeed) },

            LibraryTileModel(
                id: "faceoff",
                title: "Faceoff",
                detail: "One question, one minute, two of you",
                symbol: "bolt.fill",
                hue: MedxCandy.pink,
                badge: waitingLobbies == 0 ? nil : "\(waitingLobbies) waiting"
            ) { appState.open(route: .faceoff) },

            LibraryTileModel(
                id: "batch",
                title: "Batch papers",
                detail: "The batch's own four",
                symbol: "flag.pattern.checkered",
                hue: MedxCandy.tangerine,
                badge: nil
            ) { appState.open(route: .batchPapers) },

            LibraryTileModel(
                id: "custom",
                title: "Custom modules",
                detail: "Papers either of you saved",
                symbol: "slider.horizontal.3",
                hue: MedxCandy.violet,
                badge: customModules.modules.isEmpty ? nil : "\(customModules.modules.count)"
            ) { appState.open(route: .customModules) },

            LibraryTileModel(
                id: "quick",
                title: "Quick sitting",
                detail: "Scope, length, mode, go",
                symbol: "wand.and.stars",
                hue: MedxCandy.mint,
                badge: nil
            ) { appState.open(route: .quickSitting) },

            LibraryTileModel(
                id: "search",
                title: "Search",
                detail: "Full text across both banks",
                symbol: "magnifyingglass",
                hue: MedxCandy.lime,
                badge: nil
            ) { appState.open(route: .search(nil)) },

            LibraryTileModel(
                id: "bookmarks",
                title: "Bookmarks",
                detail: "Questions you kept",
                symbol: "bookmark.fill",
                hue: MedxCandy.butter,
                badge: bookmarkCount > 0 ? "\(bookmarkCount)" : nil
            ) { appState.showBookmarks = true },

            LibraryTileModel(
                id: "downloads",
                title: "Downloads",
                detail: "Saved for no signal",
                symbol: "arrow.down.circle.fill",
                hue: MedxCandy.sky,
                badge: downloadBadge
            ) { appState.showDownloads = true },

            LibraryTileModel(
                id: "log",
                title: "Activity log",
                detail: "Every sitting and class",
                symbol: "list.bullet.rectangle.portrait",
                hue: MedxCandy.mint,
                badge: nil
            ) { appState.showActivityLog = true },

            LibraryTileModel(
                id: "settings",
                title: "Settings",
                detail: "Accent, reminders, the index",
                symbol: "gearshape.fill",
                hue: MedxCandy.violet,
                badge: nil
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

// MARK: - One tile

/// A tile's content, kept as a value so the grid is one `ForEach` over data rather than eleven
/// hand-placed cells — which is what let the old list drift into four near-identical row helpers.
struct LibraryTileModel: Identifiable {
    let id: String
    let title: String
    let detail: String
    /// SF Symbol. Library is a grid of doors, and a symbol in the door's hue is what iOS
    /// itself puts on one.
    let symbol: String
    let hue: Color
    let badge: String?
    let action: () -> Void
}

struct LibraryTile: View {
    let tile: LibraryTileModel

    var body: some View {
        Button {
            HapticManager.light()
            tile.action()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 6) {
                    MedxSymbolMark(tile.symbol, hue: tile.hue, size: 44)

                    Spacer(minLength: 0)

                    if let badge = tile.badge {
                        MedxPill(badge, hue: tile.hue, weight: .solid)
                    }
                }

                Spacer(minLength: 10)

                Text(tile.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(tile.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            // A uniform floor rather than an aspect ratio: the grid should stay square-ish at the
            // default text size but grow with the label, not clip it.
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .medxCard()
            .contentShape(RoundedRectangle(cornerRadius: MedxSurface.cardRadius, style: .continuous))
        }
        .buttonStyle(BouncyButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tile.title)
        .accessibilityValue(tile.badge ?? "")
        .accessibilityHint(tile.detail)
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
