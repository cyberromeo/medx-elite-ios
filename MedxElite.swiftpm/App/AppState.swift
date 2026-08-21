import SwiftUI
import Combine

@MainActor
public final class AppState: ObservableObject {
    public static let shared = AppState()

    @Published public var isDarkMode: Bool = true

    private init() {}
}

public struct BookmarkedQuestion: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(sourceId)-\(question.id)" }
    public var docId: String { "\(ownerId)_\(sourceId)_\(question.id)" }
    public let sourceId: String
    public let ownerId: String
    public let sourceName: String
    public let subject: String
    public let question: Question
    public let bookmarkedAt: Date

    enum CodingKeys: String, CodingKey {
        case sourceId, ownerId, sourceName, subject, question, bookmarkedAt
    }

    public init(
        sourceId: String,
        ownerId: String,
        sourceName: String,
        subject: String,
        question: Question,
        bookmarkedAt: Date = Date()
    ) {
        self.sourceId = sourceId
        self.ownerId = ownerId
        self.sourceName = sourceName
        self.subject = subject
        self.question = question
        self.bookmarkedAt = bookmarkedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceId = try container.decodeIfPresent(String.self, forKey: .sourceId) ?? ""
        ownerId = try container.decodeIfPresent(String.self, forKey: .ownerId) ?? ""
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName) ?? ""
        subject = try container.decodeIfPresent(String.self, forKey: .subject) ?? ""
        question = try container.decode(Question.self, forKey: .question)

        if let dateVal = try? container.decode(Date.self, forKey: .bookmarkedAt) {
            bookmarkedAt = dateVal
        } else if let dateStr = try? container.decode(String.self, forKey: .bookmarkedAt),
                  let parsed = ISO8601DateFormatter().date(from: dateStr) {
            bookmarkedAt = parsed
        } else {
            bookmarkedAt = Date()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceId, forKey: .sourceId)
        try container.encode(ownerId, forKey: .ownerId)
        try container.encode(sourceName, forKey: .sourceName)
        try container.encode(subject, forKey: .subject)
        try container.encode(question, forKey: .question)
        try container.encode(ISO8601DateFormatter().string(from: bookmarkedAt), forKey: .bookmarkedAt)
    }

    public var previewText: String {
        let source = question.plain ?? question.html ?? "Question \(question.number ?? question.id)"
        return source
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: bookmarkedAt, relativeTo: Date())
    }
}

public struct WatchHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: String { video.id }
    public var docId: String { "\(ownerId)_\(video.id)" }
    public let video: RecordedVideo
    public let ownerId: String
    public var positionSeconds: Double
    public var durationSeconds: Double
    public var watchedAt: Date

    enum CodingKeys: String, CodingKey {
        case video, ownerId, positionSeconds, durationSeconds, watchedAt
    }

    public init(
        video: RecordedVideo,
        ownerId: String,
        positionSeconds: Double,
        durationSeconds: Double,
        watchedAt: Date = Date()
    ) {
        self.video = video
        self.ownerId = ownerId
        self.positionSeconds = positionSeconds
        self.durationSeconds = durationSeconds
        self.watchedAt = watchedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        video = try container.decode(RecordedVideo.self, forKey: .video)
        ownerId = try container.decodeIfPresent(String.self, forKey: .ownerId) ?? ""
        positionSeconds = try container.decodeIfPresent(Double.self, forKey: .positionSeconds) ?? 0
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? Double(video.durationSeconds ?? 0)

        if let dateVal = try? container.decode(Date.self, forKey: .watchedAt) {
            watchedAt = dateVal
        } else if let dateStr = try? container.decode(String.self, forKey: .watchedAt),
                  let parsed = ISO8601DateFormatter().date(from: dateStr) {
            watchedAt = parsed
        } else {
            watchedAt = Date()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(video, forKey: .video)
        try container.encode(ownerId, forKey: .ownerId)
        try container.encode(positionSeconds, forKey: .positionSeconds)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(ISO8601DateFormatter().string(from: watchedAt), forKey: .watchedAt)
    }

    public var progress: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(max(positionSeconds / durationSeconds, 0), 1)
    }

    public var isCompleted: Bool {
        progress >= 0.95
    }

    public var resumePosition: Double {
        guard durationSeconds <= 0 || positionSeconds < durationSeconds - 15 else { return 0 }
        return positionSeconds > 5 ? positionSeconds : 0
    }

    public var formattedResumeTime: String {
        let total = max(Int(positionSeconds), 0)
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }

    public var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: watchedAt, relativeTo: Date())
    }
}

@MainActor
public final class ActivityStore: ObservableObject {
    public static let shared = ActivityStore()

    @Published public private(set) var bookmarks: [BookmarkedQuestion] = []
    @Published public private(set) var watchHistory: [WatchHistoryEntry] = []
    @Published public private(set) var isSyncing = false
    @Published public private(set) var lastSyncedAt: Date?

    private let bookmarksKey = "medx.activity.bookmarks"
    private let watchHistoryKey = "medx.activity.watchHistory"

    private init() {
        bookmarks = Self.load([BookmarkedQuestion].self, key: bookmarksKey) ?? []
        watchHistory = Self.load([WatchHistoryEntry].self, key: watchHistoryKey) ?? []
    }

    // MARK: - Bookmarks
    public func bookmarks(for uid: String?) -> [BookmarkedQuestion] {
        guard let uid else { return [] }
        return bookmarks
            .filter { $0.ownerId == uid }
            .sorted { $0.bookmarkedAt > $1.bookmarkedAt }
    }

    public func isBookmarked(questionId: Int, sourceId: String, uid: String?) -> Bool {
        guard let uid else { return false }
        return bookmarks.contains { $0.question.id == questionId && $0.sourceId == sourceId && $0.ownerId == uid }
    }

    public func toggleBookmark(question: Question, payload: RunnerPayload, uid: String?) {
        toggleBookmark(
            question: question,
            sourceId: payload.id,
            sourceName: payload.name,
            subject: payload.subject,
            uid: uid
        )
    }

    public func toggleBookmark(
        question: Question,
        sourceId: String,
        sourceName: String,
        subject: String,
        uid: String?
    ) {
        guard let uid else { return }
        if let existing = bookmarks.first(where: { $0.question.id == question.id && $0.sourceId == sourceId && $0.ownerId == uid }) {
            removeBookmark(existing, uid: uid)
        } else {
            let newBookmark = BookmarkedQuestion(
                sourceId: sourceId,
                ownerId: uid,
                sourceName: sourceName,
                subject: subject,
                question: question,
                bookmarkedAt: Date()
            )
            bookmarks.insert(newBookmark, at: 0)
            saveBookmarks()

            // Sync to Firebase in background
            Task {
                do {
                    let token = try await AuthService.shared.getValidIdToken()
                    try await FirestoreService.shared.saveBookmark(newBookmark, idToken: token)
                } catch {
                    print("[ActivityStore] Cloud save bookmark error: \(error)")
                }
            }
        }
    }

    public func removeBookmark(_ bookmark: BookmarkedQuestion, uid: String? = nil) {
        let targetUid = uid ?? bookmark.ownerId
        bookmarks.removeAll { $0.docId == bookmark.docId || ($0.question.id == bookmark.question.id && $0.sourceId == bookmark.sourceId && $0.ownerId == targetUid) }
        saveBookmarks()

        // Sync deletion to Firebase
        Task {
            do {
                let token = try await AuthService.shared.getValidIdToken()
                try await FirestoreService.shared.deleteBookmark(docId: bookmark.docId, idToken: token)
            } catch {
                print("[ActivityStore] Cloud delete bookmark error: \(error)")
            }
        }
    }

    public func clearAllBookmarks(uid: String?) {
        guard let uid else { return }
        let toDelete = bookmarks.filter { $0.ownerId == uid }
        bookmarks.removeAll { $0.ownerId == uid }
        saveBookmarks()

        Task {
            do {
                let token = try await AuthService.shared.getValidIdToken()
                for b in toDelete {
                    try await FirestoreService.shared.deleteBookmark(docId: b.docId, idToken: token)
                }
            } catch {
                print("[ActivityStore] Cloud clear bookmarks error: \(error)")
            }
        }
    }

    // MARK: - Watch History & Resume
    public func watchHistory(for uid: String?) -> [WatchHistoryEntry] {
        guard let uid else { return [] }
        return watchHistory
            .filter { $0.ownerId == uid }
            .sorted { $0.watchedAt > $1.watchedAt }
    }

    public func entry(for videoId: String, uid: String?) -> WatchHistoryEntry? {
        guard let uid else { return nil }
        return watchHistory.first { $0.video.id == videoId && $0.ownerId == uid }
    }

    public func recordVideoProgress(
        video: RecordedVideo,
        uid: String?,
        position: Double,
        duration: Double,
        syncToCloud: Bool = true
    ) {
        guard let uid else { return }
        let safePosition = position.isFinite ? max(position, 0) : 0
        let safeDuration = duration.isFinite ? max(duration, 0) : 0
        let resolvedDuration = safeDuration > 0 ? safeDuration : Double(video.durationSeconds ?? 0)

        let entry = WatchHistoryEntry(
            video: video,
            ownerId: uid,
            positionSeconds: safePosition,
            durationSeconds: max(resolvedDuration, 0),
            watchedAt: Date()
        )

        watchHistory.removeAll { $0.video.id == video.id && $0.ownerId == uid }
        watchHistory.insert(entry, at: 0)
        saveWatchHistory()

        if syncToCloud {
            Task {
                do {
                    let token = try await AuthService.shared.getValidIdToken()
                    try await FirestoreService.shared.saveWatchHistoryEntry(entry, idToken: token)
                } catch {
                    print("[ActivityStore] Cloud save watch history error: \(error)")
                }
            }
        }
    }

    public func removeWatchHistory(_ entry: WatchHistoryEntry, uid: String? = nil) {
        let targetUid = uid ?? entry.ownerId
        watchHistory.removeAll { $0.video.id == entry.video.id && $0.ownerId == targetUid }
        saveWatchHistory()

        Task {
            do {
                let token = try await AuthService.shared.getValidIdToken()
                try await FirestoreService.shared.deleteWatchHistoryEntry(docId: entry.docId, idToken: token)
            } catch {
                print("[ActivityStore] Cloud delete watch history error: \(error)")
            }
        }
    }

    public func clearAllWatchHistory(uid: String?) {
        guard let uid else { return }
        let toDelete = watchHistory.filter { $0.ownerId == uid }
        watchHistory.removeAll { $0.ownerId == uid }
        saveWatchHistory()

        Task {
            do {
                let token = try await AuthService.shared.getValidIdToken()
                for w in toDelete {
                    try await FirestoreService.shared.deleteWatchHistoryEntry(docId: w.docId, idToken: token)
                }
            } catch {
                print("[ActivityStore] Cloud clear watch history error: \(error)")
            }
        }
    }

    // MARK: - Cloud Synchronization Engine
    public func syncWithCloud(uid: String) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let token = try await AuthService.shared.getValidIdToken()

            async let cloudBookmarksTask = FirestoreService.shared.fetchBookmarks(uid: uid, idToken: token)
            async let cloudHistoryTask = FirestoreService.shared.fetchWatchHistory(uid: uid, idToken: token)

            let (cloudBookmarks, cloudHistory) = try await (cloudBookmarksTask, cloudHistoryTask)

            // Merge bookmarks: combine local and cloud, keeping newest
            var bookmarkDict: [String: BookmarkedQuestion] = [:]
            for b in self.bookmarks where b.ownerId == uid {
                bookmarkDict[b.docId] = b
            }
            for cb in cloudBookmarks {
                if let local = bookmarkDict[cb.docId] {
                    if cb.bookmarkedAt > local.bookmarkedAt {
                        bookmarkDict[cb.docId] = cb
                    }
                } else {
                    bookmarkDict[cb.docId] = cb
                }
            }
            let mergedBookmarks = Array(bookmarkDict.values).sorted { $0.bookmarkedAt > $1.bookmarkedAt }

            // Merge watch history
            var historyDict: [String: WatchHistoryEntry] = [:]
            for h in self.watchHistory where h.ownerId == uid {
                historyDict[h.docId] = h
            }
            for ch in cloudHistory {
                if let local = historyDict[ch.docId] {
                    if ch.watchedAt > local.watchedAt {
                        historyDict[ch.docId] = ch
                    }
                } else {
                    historyDict[ch.docId] = ch
                }
            }
            let mergedHistory = Array(historyDict.values).sorted { $0.watchedAt > $1.watchedAt }

            // Update state and local storage
            var updatedBookmarks = self.bookmarks.filter { $0.ownerId != uid }
            updatedBookmarks.append(contentsOf: mergedBookmarks)
            self.bookmarks = updatedBookmarks
            saveBookmarks()

            var updatedHistory = self.watchHistory.filter { $0.ownerId != uid }
            updatedHistory.append(contentsOf: mergedHistory)
            self.watchHistory = updatedHistory
            saveWatchHistory()

            self.lastSyncedAt = Date()
        } catch {
            print("[ActivityStore] Cloud sync failed: \(error)")
        }
    }

    private func saveBookmarks() {
        Self.save(bookmarks, key: bookmarksKey)
    }

    private func saveWatchHistory() {
        Self.save(watchHistory, key: watchHistoryKey)
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
