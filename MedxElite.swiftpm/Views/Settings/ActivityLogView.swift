import SwiftUI

// MARK: - Activity log

/// Every sitting and every class watched, in one list, newest first.
struct ActivityLogView: View {
    let uid: String?
    @Binding var attempts: [SittingAttempt]
    @ObservedObject private var activityStore = ActivityStore.shared
    @State private var selectedFilter: LogFilter = .all
    @State private var searchText = ""
    @State private var pendingDeletion: ActivityLogItem?
    @State private var confirmClearAttempts = false
    @State private var deletionError = false

    enum LogFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case videos = "Classes"
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

            let matchesSearch = searchText.isEmpty
                || item.title.localizedCaseInsensitiveContains(searchText)
                || item.subtitle.localizedCaseInsensitiveContains(searchText)

            return matchesCategory && matchesSearch
        }
    }

    private var subtitle: String {
        allItems.count == 1 ? "1 entry" : "\(MedxFormat.count(allItems.count)) entries"
    }

    var body: some View {
        Group {
            if allItems.isEmpty {
                MedxEmptyState(
                    "Nothing logged yet",
                    symbol: MedxFeature.activityLog.symbol,
                    message: "Every sitting and every class you watch is listed here."
                )
            } else {
                List {
                    Section {
                        Picker("Show", selection: $selectedFilter) {
                            ForEach(LogFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }

                    Section {
                        ForEach(filteredItems) { item in
                            row(item)
                        }
                    } footer: {
                        Text("\(MedxFormat.count(filteredItems.count)) entries. Swipe left to delete one, here and from your account.")
                    }
                }
                .listStyle(.insetGrouped)
                .searchable(text: $searchText, prompt: "Search the log")
            }
        }
        .navigationTitle(MedxFeature.activityLog.title)
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if !allItems.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            HapticManager.medium()
                            activityStore.clearAllWatchHistory(uid: uid)
                        } label: {
                            Label("Clear watch history", systemImage: "play.slash")
                        }

                        Button(role: .destructive) {
                            confirmClearAttempts = true
                        } label: {
                            Label("Clear every sitting", systemImage: "doc.badge.gearshape")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Manage the log")
                }
            }
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { item in
            Button("Delete", role: .destructive) {
                deleteItem(item)
            }
        } message: { item in
            Text(item.deleteMessage)
        }
        .confirmationDialog(
            "Clear every sitting?",
            isPresented: $confirmClearAttempts,
            titleVisibility: .visible
        ) {
            Button("Clear \(attempts.count) sittings", role: .destructive) {
                Task { await clearAllAttempts() }
            }
            Button("Keep them", role: .cancel) {}
        } message: {
            Text("Every sitting goes from your account, and the streak, goal and accuracy figures with it.")
        }
        .alert("Couldn't delete that", isPresented: $deletionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("It could not be removed from your account. Check your connection and try again.")
        }
    }

    private func row(_ item: ActivityLogItem) -> some View {
        HStack(spacing: MedxSpace.m) {
            MedxSymbolTile(item.symbol, hue: item.feature.color, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title.medxDisplayTitle)
                    .lineLimit(2)

                Text(item.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(item.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                pendingDeletion = item
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
        .accessibilityValue(item.subtitle)
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
        guard let token = try? await AuthService.shared.getValidIdToken() else {
            deletionError = true
            return
        }
        var failed = false
        for att in attempts {
            do {
                try await FirestoreService.shared.deleteAttempt(att, idToken: token)
            } catch {
                failed = true
            }
        }
        withAnimation {
            attempts.removeAll()
        }
        if failed {
            deletionError = true
        } else {
            HapticManager.success()
        }
    }
}

// MARK: - One entry

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
        case .video: return "play.fill"
        case .attempt(let attempt): return MedxAttemptKind.symbol(attempt.kind)
        }
    }

    var feature: MedxFeature {
        switch self {
        case .video: return .classes
        case .attempt(let attempt): return MedxAttemptKind.feature(attempt.kind)
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
            return "\(entry.video.subject) · \(status) · \(Int(entry.progress * 100))%"
        case .attempt(let attempt):
            let kind = MedxAttemptKind.label(attempt.kind)
            let mode = attempt.mode == "exam" ? "Exam" : "Revision"
            return "\(kind) · \(mode) · \(attempt.score) of \(attempt.total) (\(attempt.totalPercentage)%)"
        }
    }

    var formattedDate: String {
        MedxFormat.relative(date)
    }

    var deleteMessage: String {
        switch self {
        case .video: return "The watch history and resume position for this class go, on this device and from your account."
        case .attempt: return "This sitting goes for good, on this device and from your account."
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
