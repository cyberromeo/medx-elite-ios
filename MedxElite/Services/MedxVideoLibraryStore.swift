import Foundation

// MARK: - The curated library's structure + the VOD → class bridge
//
// This is the native port of the PWA's `src/lib/admin.js` — the *only* place either app turns a
// raw bucket recording into a curated class. The bucket (`medx_vod`) is ~2,900 recordings with no
// titles and no structure; the Classes tab reads a different collection (`medx_videos`) organised
// folder → subject → class. This module is the bridge: pick a recording, give it a title and a
// home, and write it into `medx_videos` in exactly the shape `fetchVideos()` already expects, so an
// imported class is indistinguishable from an original ARISE one.
//
// The field names in `vodToClass` are **not** free choices — `fetchVideos()` reads exactly these,
// and `VideosBatchListView` groups on `batchId`/`batch` (folder) and `subjectId`/`subject`
// (subject). If they drift, a class is filed into a folder the app then puts somewhere else.

// MARK: - Folder documents

/// One `medx_video_folders` document. `Codable` so it comes straight through `fetchCollection`.
///
/// A folder can exist before it holds any class — that is the whole reason the collection exists —
/// so a subject here may have a zero count until something is filed under it.
public struct MedxVideoFolder: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let order: Int
    public let subjects: [MedxVideoFolderSubject]

    enum CodingKeys: String, CodingKey { case id, name, order, subjects }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Untitled folder"
        order = (try? c.decodeIfPresent(Int.self, forKey: .order)) ?? 0
        subjects = (try? c.decodeIfPresent([MedxVideoFolderSubject].self, forKey: .subjects)) ?? []
    }

    public init(id: String, name: String, order: Int, subjects: [MedxVideoFolderSubject]) {
        self.id = id
        self.name = name
        self.order = order
        self.subjects = subjects
    }
}

/// A subject inside a folder document. `subjectId` is a number on the oldest class docs and a
/// string on newer ones, so the id is decoded leniently and always kept as a string.
public struct MedxVideoFolderSubject: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let order: Int
    public let sticker: String

    enum CodingKeys: String, CodingKey { case id, name, order, sticker }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else if let n = try? c.decode(Int.self, forKey: .id) {
            id = String(n)
        } else {
            id = UUID().uuidString
        }
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Untitled"
        order = (try? c.decodeIfPresent(Int.self, forKey: .order)) ?? 0
        sticker = (try? c.decodeIfPresent(String.self, forKey: .sticker)) ?? ""
    }

    public init(id: String, name: String, order: Int, sticker: String) {
        self.id = id
        self.name = name
        self.order = order
        self.sticker = sticker
    }
}

// MARK: - The resolved tree the importer picks a destination from

/// A folder in the resolved tree — an explicit `medx_video_folders` document, or one *derived*
/// from the classes that already imply it.
public struct MedxLibraryFolder: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let order: Int
    public let derived: Bool
    public var subjects: [MedxLibrarySubject]
    public var classCount: Int
}

public struct MedxLibrarySubject: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let order: Int
    public var sticker: String
    public let derived: Bool
    public var classCount: Int
    /// Titles of the classes already filed here — used to pick the next class number.
    public var titles: [String]
}

// MARK: - The store

/// Loads the folder→subject tree and files recordings into it. An `actor`, because it only ever
/// touches Firestore through `FirestoreService` and holds no view state.
public actor MedxVideoLibraryStore {
    public static let shared = MedxVideoLibraryStore()
    private init() {}

    /// The whole library in one pass: the folder documents *and* the structure the existing
    /// classes already imply.
    ///
    /// The derived half is the important one — the ~110 original ARISE classes have no folder
    /// document, so listing only `medx_video_folders` would show an empty rail over a full library.
    /// Every existing batch and subject is folded in and marked `derived`, exactly as the PWA's
    /// `listStructure` does. `folderKey = batchId||batch`, `subjectKey = subjectId ?? subject`.
    public func listStructure(idToken: String) async throws -> [MedxLibraryFolder] {
        async let foldersTask = FirestoreService.shared.fetchVideoFolders(idToken: idToken)
        async let classesTask = FirestoreService.shared.fetchVideos(idToken: idToken)
        let (folderDocs, classes) = try await (foldersTask, classesTask)

        // Explicit folders first.
        var order: [String] = []
        var folders: [String: MedxLibraryFolder] = [:]
        for doc in folderDocs {
            let subjects = doc.subjects.map {
                MedxLibrarySubject(
                    id: $0.id, name: $0.name, order: $0.order, sticker: $0.sticker,
                    derived: false, classCount: 0, titles: []
                )
            }
            folders[doc.id] = MedxLibraryFolder(
                id: doc.id, name: doc.name, order: doc.order,
                derived: false, subjects: subjects, classCount: 0
            )
            order.append(doc.id)
        }

        // Then everything the classes imply.
        for video in classes {
            let folderKey = video.batchId ?? video.batch ?? "unsorted"
            let subjectKey = video.subjectId ?? video.subject

            if folders[folderKey] == nil {
                folders[folderKey] = MedxLibraryFolder(
                    id: folderKey, name: video.batch ?? "Unsorted batch", order: 500,
                    derived: true, subjects: [], classCount: 0
                )
                order.append(folderKey)
            }
            folders[folderKey]?.classCount += 1

            if let subjectIndex = folders[folderKey]?.subjects.firstIndex(where: { $0.id == subjectKey }) {
                folders[folderKey]?.subjects[subjectIndex].classCount += 1
                folders[folderKey]?.subjects[subjectIndex].titles.append(video.title)
            } else {
                folders[folderKey]?.subjects.append(
                    MedxLibrarySubject(
                        id: subjectKey, name: video.subject, order: 500, sticker: "",
                        derived: true, classCount: 1, titles: [video.title]
                    )
                )
            }
        }

        // Sort subjects within each folder, then the folders — curated (low order) before derived.
        let sorted = order.compactMap { key -> MedxLibraryFolder? in
            guard var folder = folders[key] else { return nil }
            folder.subjects.sort { lhs, rhs in
                lhs.order != rhs.order ? lhs.order < rhs.order
                    : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return folder
        }
        return sorted.sorted { lhs, rhs in
            lhs.order != rhs.order ? lhs.order < rhs.order
                : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// One recording into one subject. Returns the class document that was written, so the caller
    /// can fold it into its own numbering before the reload lands.
    public func importOne(
        vod: MedxVodItem,
        folder: MedxLibraryFolder,
        subject: MedxLibrarySubject,
        title: String,
        idToken: String
    ) async throws -> [String: Any] {
        let record = Self.vodToClass(vod: vod, folder: folder, subject: subject, title: title)
        try await FirestoreService.shared.importVodToClass(record: record, idToken: idToken)
        return record
    }

    // MARK: - Mapping (ported field-for-field from admin.js `vodToClass`)

    /// A bucket document plus a destination becomes an ARISE class document.
    public static func vodToClass(
        vod: MedxVodItem,
        folder: MedxLibraryFolder,
        subject: MedxLibrarySubject,
        title: String
    ) -> [String: Any] {
        let docId = classIdFor(vod.id)
        let seconds = vod.durationSeconds
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        return [
            "id": docId,
            "title": cleanTitle.isEmpty ? "Untitled class" : cleanTitle,
            "subject": subject.name,
            "subjectId": subject.id,
            "sticker": subject.sticker,
            "batch": folder.name,
            "batchId": folder.id,
            "faculty": vod.faculty,
            "streamUrl": vod.streamUrl,
            "durationSeconds": seconds,
            "durationPreciseSeconds": seconds,
            // The bucket's duration is the measured playlist length, the one the player trusts.
            "durationSource": seconds > 0 ? "measured" : "unknown",
            "expiryDate": "",
            "thumbnailUrl": vod.thumbnailUrl,
            "subtitlesUrl": vod.subtitlesUrl,
            "hasSubtitles": vod.hasSubtitles,
            // Provenance: what the row came from, so the browser can grey out a recording that
            // already has a home.
            "vodId": vod.id,
            "vodKey": vod.rawKey,
            "vodFolder": vod.folder,
            "uploadedAt": vod.uploadedAtRaw ?? "",
            "kind": "hls",
            "origin": "vod-import",
            "addedAt": ISO8601DateFormatter().string(from: Date()),
        ]
    }

    /// Firestore document ids may not contain `/`, and a bucket key sometimes does. The `vod_`
    /// prefix guarantees an import can never collide with an original ARISE class (whose ids are
    /// plain recording numbers), and it is idempotent — most bucket ids already carry it.
    public static func classIdFor(_ vodId: String) -> String {
        let clean = vodId.map { ch -> Character in
            (ch.isLetter || ch.isNumber || ch == "." || ch == "-" || ch == "_") ? ch : "_"
        }
        let cleaned = String(clean)
        return cleaned.lowercased().hasPrefix("vod_") ? cleaned : "vod_\(cleaned)"
    }

    /// The next class number for a subject: the highest trailing integer across the titles already
    /// filed there, plus one. Read off the titles rather than counted, so it survives a deletion in
    /// the middle and picks up where a hand-typed "Class 12" left off.
    public static func nextClassNumber(existingTitles: [String]) -> Int {
        var maxNumber = 0
        for title in existingTitles {
            // Trailing run of digits.
            let trailing = title.reversed().prefix { $0.isNumber }
            if !trailing.isEmpty, let value = Int(String(trailing.reversed())) {
                maxNumber = max(maxNumber, value)
            }
        }
        return maxNumber + 1
    }
}
