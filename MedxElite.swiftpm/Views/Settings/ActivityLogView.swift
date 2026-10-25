import SwiftUI

// MARK: - Activity Log View (Unified Watch History & Test Attempts)

struct ActivityLogView: View {
    let uid: String?
    @Binding var attempts: [SittingAttempt]
    @ObservedObject private var activityStore = ActivityStore.shared
    @State private var selectedFilter: LogFilter = .all
    @State private var searchText = ""
    @State private var pendingDeletion: ActivityLogItem?
    @State private var showClearOptions = false
    @State private var deletionError = false
    @State private var isDeleting = false

    enum LogFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case videos = "Videos"
        case qbank = "QBank"
        case tests = "Tests"

        var id: String { rawValue }
    }

    /// Which attempt kinds count as a paper rather than a module. `series` joined `test` when
    /// the Tests tab became the Marrow catalogue; without it, 352 papers' worth of sittings
    /// were filed under QBank.
    private static let paperKinds: Set<String> = ["test", "series"]

    private var allItems: [ActivityLogItem] {
        let videoItems = activityStore.watchHistory(for: uid).map(ActivityLogItem.video)
        let attemptItems = attempts.map(ActivityLogItem.attempt)
        return (videoItems + attemptItems).sorted { $0.date > $1.date }
    }

    private var filteredItems: [ActivityLogItem] {
        allItems.filter { item in
            let matchesCategory: Bool
            switch selectedFilter {
            case .all:
                matchesCategory = true
            case .videos:
                if case .video = item { matchesCategory = true } else { matchesCategory = false }
            case .qbank:
                if case .attempt(let att) = item, !Self.paperKinds.contains(att.kind) { matchesCategory = true } else { matchesCategory = false }
            case .tests:
                if case .attempt(let att) = item, Self.paperKinds.contains(att.kind) { matchesCategory = true } else { matchesCategory = false }
            }

            let matchesSearch = searchText.isEmpty ||
                item.title.localizedCaseInsensitiveContains(searchText) ||
                item.subtitle.localizedCaseInsensitiveContains(searchText)

            return matchesCategory && matchesSearch
        }
    }

    var body: some View {
        Group {
            if allItems.isEmpty {
                ContentUnavailableView(
                    "No Activity Log",
                    systemImage: "list.bullet.rectangle.portrait",
                    description: Text("Your video watch history and QBank/test attempts will appear in this unified log.")
                )
            } else {
                List {
                    // Filter picker
                    Section {
                        Picker("Filter Activity", selection: $selectedFilter) {
                            ForEach(LogFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.vertical, 2)
                    }

                    Section {
                        ForEach(filteredItems) { item in
                            HStack(spacing: 14) {
                                MedxSymbolMark(item.symbol, hue: item.color, size: 34)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title.medxDisplayTitle)
                                        .font(.headline)
                                        .lineLimit(2)

                                    Text(item.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)

                                    Text(item.formattedDate)
                                        .font(.caption)
                                        .foregroundStyle(Color(uiColor: .tertiaryLabel))
                                }

                                Spacer()

                                Button(role: .destructive) {
                                    pendingDeletion = item
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.secondary)
                                        .frame(width: 44, height: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Delete \(item.title)")
                            }
                            .padding(.vertical, 4)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    pendingDeletion = item
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } footer: {
                        Text("\(filteredItems.count) activity entries")
                            .font(.caption)
                    }
                }
                .searchable(text: $searchText, prompt: "Search activity log…")
            }
        }
        .navigationTitle("Activity Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !allItems.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            activityStore.clearAllWatchHistory(uid: uid)
                        } label: {
                            Label("Clear Watch History", systemImage: "play.slash")
                        }

                        Button(role: .destructive) {
                            Task {
                                await clearAllAttempts()
                            }
                        } label: {
                            Label("Clear All Test Attempts", systemImage: "doc.badge.gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(width: 44, height: 44)
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete Activity Entry?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { item in
            Button("Delete", role: .destructive) {
                deleteItem(item)
            }
        } message: { item in
            Text(item.deleteMessage)
        }
        .alert("Failed to Delete", isPresented: $deletionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Could not delete from cloud. Please check your internet connection and try again.")
        }
    }

    private func deleteItem(_ item: ActivityLogItem) {
        switch item {
        case .video(let entry):
            activityStore.removeWatchHistory(entry, uid: uid)
            HapticManager.success()

        case .attempt(let attempt):
            Task {
                do {
                    let token = try await AuthService.shared.getValidIdToken()
                    try await FirestoreService.shared.deleteAttempt(attempt, idToken: token)
                    withAnimation {
                        attempts.removeAll { $0.id == attempt.id || ($0.sourceId == attempt.sourceId && $0.finishedAt == attempt.finishedAt) }
                    }
                    HapticManager.success()
                } catch {
                    deletionError = true
                }
            }
        }
        pendingDeletion = nil
    }

    private func clearAllAttempts() async {
        guard let token = try? await AuthService.shared.getValidIdToken() else { return }
        for att in attempts {
            try? await FirestoreService.shared.deleteAttempt(att, idToken: token)
        }
        withAnimation {
            attempts.removeAll()
        }
        HapticManager.success()
    }
}

// MARK: - Activity Log Item Wrapper

private enum ActivityLogItem: Identifiable, Hashable {
    case video(WatchHistoryEntry)
    case attempt(SittingAttempt)

    var id: String {
        switch self {
        case .video(let entry): return "video-\(entry.ownerId)-\(entry.id)"
        case .attempt(let attempt): return "attempt-\(attempt.id ?? attempt.sourceId + (attempt.finishedAt ?? ""))"
        }
    }

    var date: Date {
        switch self {
        case .video(let entry): return entry.watchedAt
        case .attempt(let attempt): return attempt.finishedDate ?? .distantPast
        }
    }

    var symbol: String {
        switch self {
        case .video: return "play.rectangle.fill"
        case .attempt(let attempt): return MedxAttemptKind.symbol(attempt.kind)
        }
    }

    var color: Color {
        switch self {
        case .video: return MedxCandy.violet
        case .attempt(let attempt): return MedxAttemptKind.hue(attempt.kind)
        }
    }

    var title: String {
        switch self {
        case .video(let entry): return entry.video.title
        case .attempt(let attempt): return attempt.name
        }
    }

    var subtitle: String {
        switch self {
        case .video(let entry):
            let status = entry.isCompleted ? "Watched" : "Resume at \(entry.formattedResumeTime)"
            return "\(entry.video.subject) · \(status) (\(Int(entry.progress * 100))%)"
        case .attempt(let attempt):
            let kind = MedxAttemptKind.label(attempt.kind)
            let mode = attempt.mode == "exam" ? "Exam" : "Revision"
            return "\(kind) (\(mode)) · Score: \(attempt.score)/\(attempt.total) (\(attempt.totalPercentage)%)"
        }
    }

    var formattedDate: String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    var deleteMessage: String {
        switch self {
        case .video: return "Deleting this log entry will delete the watch history and clear its resume position both on this device and online."
        case .attempt: return "Deleting this log entry will permanently remove the test/QBank attempt record on this device and online."
        }
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
