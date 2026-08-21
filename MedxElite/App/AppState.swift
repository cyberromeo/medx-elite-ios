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
    public let sourceId: String
    public let ownerId: String
    public let sourceName: String
    public let subject: String
    public let question: Question
    public let bookmarkedAt: Date

    public var previewText: String {
        let source = question.plain ?? question.html ?? "Question \(question.number ?? question.id)"
        return source
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct WatchHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    public var id: String { video.id }
    public let video: RecordedVideo
    public let ownerId: String
    public var positionSeconds: Double
    public var durationSeconds: Double
    public var watchedAt: Date

    public var progress: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(max(positionSeconds / durationSeconds, 0), 1)
    }

    public var resumePosition: Double {
        guard durationSeconds <= 0 || positionSeconds < durationSeconds - 20 else { return 0 }
        return positionSeconds
    }
}

@MainActor
public final class ActivityStore: ObservableObject {
    public static let shared = ActivityStore()

    @Published public private(set) var bookmarks: [BookmarkedQuestion] = []
    @Published public private(set) var watchHistory: [WatchHistoryEntry] = []

    private let bookmarksKey = "medx.activity.bookmarks"
    private let watchHistoryKey = "medx.activity.watchHistory"

    private init() {
        bookmarks = Self.load([BookmarkedQuestion].self, key: bookmarksKey) ?? []
        watchHistory = Self.load([WatchHistoryEntry].self, key: watchHistoryKey) ?? []
    }

    public func bookmarks(for uid: String?) -> [BookmarkedQuestion] {
        guard let uid else { return [] }
        return bookmarks.filter { $0.ownerId == uid }
    }

    public func watchHistory(for uid: String?) -> [WatchHistoryEntry] {
        guard let uid else { return [] }
        return watchHistory
            .filter { $0.ownerId == uid }
            .sorted { $0.watchedAt > $1.watchedAt }
    }

    public func isBookmarked(questionId: Int, sourceId: String, uid: String?) -> Bool {
        guard let uid else { return false }
        return bookmarks.contains { $0.question.id == questionId && $0.sourceId == sourceId && $0.ownerId == uid }
    }

    public func toggleBookmark(question: Question, payload: RunnerPayload, uid: String?) {
        guard let uid else { return }
        if let index = bookmarks.firstIndex(where: {
            $0.question.id == question.id && $0.sourceId == payload.id && $0.ownerId == uid
        }) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.insert(
                BookmarkedQuestion(
                    sourceId: payload.id,
                    ownerId: uid,
                    sourceName: payload.name,
                    subject: payload.subject,
                    question: question,
                    bookmarkedAt: Date()
                ),
                at: 0
            )
        }
        saveBookmarks()
    }

    public func removeBookmark(_ bookmark: BookmarkedQuestion) {
        bookmarks.removeAll { $0.id == bookmark.id && $0.subject == bookmark.subject }
        saveBookmarks()
    }

    public func recordVideoProgress(video: RecordedVideo, uid: String?, position: Double, duration: Double) {
        guard let uid else { return }
        let safePosition = position.isFinite ? max(position, 0) : 0
        let safeDuration = duration.isFinite ? max(duration, 0) : 0
        let storedVideo = RecordedVideo(
            id: video.id,
            source: video.source,
            batchId: video.batchId,
            batch: video.batch,
            subjectId: video.subjectId,
            subject: video.subject,
            title: video.title,
            faculty: video.faculty,
            durationSeconds: video.durationSeconds,
            duration: video.duration,
            streamUrl: video.streamUrl,
            kind: video.kind
        )
        let resolvedDuration = safeDuration > 0 ? safeDuration : Double(video.durationSeconds ?? 0)
        let entry = WatchHistoryEntry(
            video: storedVideo,
            ownerId: uid,
            positionSeconds: safePosition,
            durationSeconds: max(resolvedDuration, 0),
            watchedAt: Date()
        )
        watchHistory.removeAll { $0.video.id == video.id && $0.ownerId == uid }
        watchHistory.insert(entry, at: 0)
        saveWatchHistory()
    }

    public func entry(for videoId: String, uid: String?) -> WatchHistoryEntry? {
        guard let uid else { return nil }
        return watchHistory.first { $0.video.id == videoId && $0.ownerId == uid }
    }

    public func removeWatchHistory(_ entry: WatchHistoryEntry) {
        watchHistory.removeAll { $0.video.id == entry.video.id && $0.ownerId == entry.ownerId }
        saveWatchHistory()
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
