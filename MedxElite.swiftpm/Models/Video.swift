import Foundation

public struct RecordedVideo: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let source: String?
    public let batchId: String?
    public let batch: String?
    public let subjectId: String?
    public let subject: String
    public let title: String
    public let faculty: String?
    public let durationSeconds: Int?
    public let duration: String?
    public let streamUrl: String
    public let kind: String?

    enum CodingKeys: String, CodingKey {
        case id, source, batchId, batch, subjectId, subject, title, faculty, durationSeconds, duration, streamUrl, kind
    }

    public init(
        id: String,
        source: String? = nil,
        batchId: String? = nil,
        batch: String? = nil,
        subjectId: String? = nil,
        subject: String,
        title: String,
        faculty: String? = nil,
        durationSeconds: Int? = nil,
        duration: String? = nil,
        streamUrl: String,
        kind: String? = nil
    ) {
        self.id = id
        self.source = source
        self.batchId = batchId
        self.batch = batch
        self.subjectId = subjectId
        self.subject = subject
        self.title = title
        self.faculty = faculty
        self.durationSeconds = durationSeconds
        self.duration = duration
        self.streamUrl = streamUrl
        self.kind = kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let idStr = try? container.decode(String.self, forKey: .id) {
            id = idStr
        } else if let idInt = try? container.decode(Int.self, forKey: .id) {
            id = String(idInt)
        } else {
            id = UUID().uuidString
        }
        source = try? container.decodeIfPresent(String.self, forKey: .source)
        
        if let bIdStr = try? container.decode(String.self, forKey: .batchId) {
            batchId = bIdStr
        } else if let bIdInt = try? container.decode(Int.self, forKey: .batchId) {
            batchId = String(bIdInt)
        } else {
            batchId = nil
        }
        
        batch = try? container.decodeIfPresent(String.self, forKey: .batch)
        
        if let sIdStr = try? container.decode(String.self, forKey: .subjectId) {
            subjectId = sIdStr
        } else if let sIdInt = try? container.decode(Int.self, forKey: .subjectId) {
            subjectId = String(sIdInt)
        } else {
            subjectId = nil
        }
        
        subject = (try? container.decodeIfPresent(String.self, forKey: .subject)) ?? "Subject"
        title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? "Class Video"
        faculty = try? container.decodeIfPresent(String.self, forKey: .faculty)
        durationSeconds = try? container.decodeIfPresent(Int.self, forKey: .durationSeconds)
        duration = try? container.decodeIfPresent(String.self, forKey: .duration)
        streamUrl = (try? container.decodeIfPresent(String.self, forKey: .streamUrl)) ?? ""
        kind = try? container.decodeIfPresent(String.self, forKey: .kind)
    }

    public var formattedDuration: String {
        guard let secs = durationSeconds, secs > 0 else {
            return duration ?? ""
        }
        let hours = secs / 3600
        let minutes = (secs % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

public struct VideoBatchGroup: Identifiable, Hashable, Sendable {
    public var id: String { batchId }
    public let batchId: String
    public let name: String
    public let totalSeconds: Int
    public let totalClasses: Int
    public let subjects: [VideoSubjectGroup]
}

public struct VideoSubjectGroup: Identifiable, Hashable, Sendable {
    public var id: String { subjectId }
    public let subjectId: String
    public let name: String
    public let totalSeconds: Int
    public let totalClasses: Int
    public let videos: [RecordedVideo]

    public var formattedDuration: String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
