import Foundation

// MARK: - The raw VOD bucket
//
// `medx_vod` is the ARISE VOD bucket, indexed: roughly 2,900 HLS recordings ordered purely by
// upload date. It is not a library — `medx_videos` is the library, curated by subject and batch
// — so this is a *feed*, and the only one of the two large enough to matter for read quota,
// which is why it is the only one that pages.

/// One bucket item, mapped the same way the PWA's `lib/videos.js` maps it so both clients agree
/// about what a recording is called.
public struct MedxVodItem: Identifiable, Hashable, Sendable {
    public let id: String
    /// The bucket key or title exactly as stored, kept because it is the only reliable handle
    /// on a recording and is worth showing on the player page.
    public let rawKey: String
    public let folder: String
    public let streamUrl: String
    public let thumbnailUrl: String
    public let subtitlesUrl: String
    public let hasSubtitles: Bool
    public let subject: String
    public let faculty: String
    public let batch: String
    public let durationSeconds: Int
    /// The `timestampValue` string Firestore returned, verbatim. It is the paging cursor, so it
    /// is carried rather than reformatted — a round trip through `Date` loses sub-second
    /// precision and two recordings uploaded in the same second would then repeat or vanish.
    public let uploadedAtRaw: String?
    public let uploadedAt: Date?

    /// A readable label for a bucket item.
    ///
    /// Most keys here are `rec<32 hex>` — ARISE's own recording ids. The real lecture titles only
    /// exist behind their login-gated API, which this app deliberately never touches, so there is
    /// nothing to look them up against. Printing 35 characters of hex as a title is worse than
    /// useless: every row looks identical at a glance. So the *folder* becomes the headline — it
    /// is the batch or class the recording belongs to, the one meaningful grouping the bucket does
    /// expose — and a short code identifies the file.
    ///
    /// Keys that are actually descriptive ("PhysiologyJuly15") keep their humanised title and show
    /// the folder underneath.
    public var display: (title: String, sub: String, opaque: Bool) {
        let opaque = MedxVodItem.isOpaqueKey(rawKey)
        guard opaque else {
            return (MedxVodItem.humanise(rawKey), folder.isEmpty ? "bucket item" : folder, false)
        }
        let short = String(rawKey.dropFirst(3).prefix(6)).uppercased()
        if folder.lowercased().hasPrefix("standalone-") {
            return ("Standalone recording", "#\(short)", true)
        }
        // Folders are lowercased in the bucket; upper-casing reads as the code it is rather
        // than as a mangled word.
        return (folder.isEmpty ? "Recording" : "Class \(folder.uppercased())", "#\(short)", true)
    }

    /// `rec` followed by at least sixteen hex characters — ARISE's own opaque recording id.
    static func isOpaqueKey(_ key: String) -> Bool {
        guard key.count >= 19, key.lowercased().hasPrefix("rec") else { return false }
        return key.dropFirst(3).allSatisfy { $0.isHexDigit }
    }

    /// `PhysiologyJuly15_final.m3u8` → `Physiology July 15 final`. Extensions and separators go,
    /// camel case is split, and runs of whitespace collapse.
    static func humanise(_ key: String) -> String {
        var text = key
        for suffix in [".m3u8", ".mp4", ".ts"] where text.lowercased().hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count))
        }
        text = text
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "([A-Za-z])([0-9])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? key : text
    }

    /// Playable by the existing player, which means watch history, resume, Continue on Home and
    /// the offline downloader all work on a bucket item with no changes at all.
    public var asRecordedVideo: RecordedVideo {
        let label = display
        return RecordedVideo(
            id: id,
            source: "VOD",
            batch: batch.isEmpty ? nil : batch,
            subject: subject.isEmpty ? "VOD bucket" : subject,
            title: label.title,
            faculty: faculty.isEmpty ? nil : faculty,
            durationSeconds: durationSeconds > 0 ? durationSeconds : nil,
            streamUrl: streamUrl,
            kind: "hls"
        )
    }

    public var formattedDuration: String {
        guard durationSeconds > 0 else { return "" }
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

// MARK: - Decoding

extension MedxVodItem {
    /// Built from a normalised Firestore document rather than through `Codable`, because the
    /// cursor needs the raw `timestampValue` string and the document id is the fallback id.
    ///
    /// `durationPreciseSeconds` wins over `durationSeconds` where it exists: the API's own
    /// duration is unreliable — it once claimed 14:50:00 for a 2:05:47 class — and the measured
    /// playlist sum is the honest number.
    init?(fields: [String: Any], fallbackId: String) {
        func string(_ key: String) -> String {
            (fields[key] as? String) ?? ""
        }
        func int(_ key: String) -> Int {
            if let value = fields[key] as? Int { return value }
            if let value = fields[key] as? Double { return Int(value) }
            if let value = fields[key] as? String { return Int(value) ?? 0 }
            return 0
        }

        let resolvedId = string("id").isEmpty ? fallbackId : string("id")
        guard !resolvedId.isEmpty else { return nil }

        self.id = resolvedId
        let key = string("title").isEmpty ? string("fileKey") : string("title")
        self.rawKey = key.isEmpty ? resolvedId : key
        self.folder = string("folder")
        self.streamUrl = string("streamUrl")
        self.thumbnailUrl = string("thumbnailUrl")
        self.subtitlesUrl = string("subtitlesUrl")
        self.hasSubtitles = (fields["hasSubtitles"] as? Bool) ?? false
        self.subject = string("subject")
        self.faculty = string("faculty")
        self.batch = string("batch")
        let precise = int("durationPreciseSeconds")
        self.durationSeconds = precise > 0 ? precise : int("durationSeconds")

        let raw = fields["uploadedAt"] as? String
        self.uploadedAtRaw = raw
        self.uploadedAt = raw.flatMap { MedxVodItem.parseTimestamp($0) }
    }

    /// Firestore hands timestamps back as RFC 3339 with a variable number of fractional digits,
    /// so both spellings have to parse or half the feed would come back undated.
    static func parseTimestamp(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let hit = fractional.date(from: value) { return hit }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: value)
    }
}

/// `medx_vod/_meta` — the sync watermark, one read.
///
/// `count` is *not* the size of the collection: the bucket sync script keeps it as a running
/// total of the documents that particular installation has added, so it resets whenever its
/// state file does. It is shown as "added by sync" and never as a collection total, because as
/// one it would be wrong by thousands.
public struct MedxVodMeta: Hashable, Sendable {
    public let count: Int
    public let lastUploadedAt: Date?
    public let lastUploadedAtRaw: String?
    public let updatedAt: Date?
}

/// One page of the feed, with the cursor that fetches the next.
public struct MedxVodPage: Sendable {
    public let items: [MedxVodItem]
    /// The last item's raw `uploadedAt`, or nil at the end of the bucket.
    public let cursor: String?
    public let done: Bool
}
