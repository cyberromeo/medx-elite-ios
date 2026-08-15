import Foundation

public struct UserTrackerDoc: Codable, Sendable {
    public let subjects: [String: SubjectTrackerFields]?

    public init(subjects: [String: SubjectTrackerFields]?) {
        self.subjects = subjects
    }
}

public struct SubjectTrackerFields: Codable, Sendable {
    public var videos: Bool?
    public var r1: Bool?
    public var r2: Bool?
    public var pyqs: Bool?
    public var revisionVideos: Bool?
    public var qbank: Bool?

    enum CodingKeys: String, CodingKey {
        case videos = "Videos"
        case r1 = "R1"
        case r2 = "R2"
        case pyqs = "PYQs"
        case revisionVideos = "RevisionVideos"
        case qbank = "Qbank"
    }

    public init(videos: Bool? = nil, r1: Bool? = nil, r2: Bool? = nil, pyqs: Bool? = nil, revisionVideos: Bool? = nil, qbank: Bool? = nil) {
        self.videos = videos
        self.r1 = r1
        self.r2 = r2
        self.pyqs = pyqs
        self.revisionVideos = revisionVideos
        self.qbank = qbank
    }

    public func value(for field: TrackerField) -> Bool? {
        switch field {
        case .videos: return videos
        case .r1: return r1
        case .r2: return r2
        case .pyqs: return pyqs
        case .rev: return revisionVideos
        case .qbank: return qbank
        }
    }

    public mutating func setValue(_ val: Bool, for field: TrackerField) {
        switch field {
        case .videos: videos = val
        case .r1: r1 = val
        case .r2: r2 = val
        case .pyqs: pyqs = val
        case .rev: revisionVideos = val
        case .qbank: qbank = val
        }
    }
}

public enum TrackerField: String, CaseIterable, Identifiable, Sendable {
    case videos = "Videos"
    case r1 = "R1"
    case r2 = "R2"
    case pyqs = "PYQs"
    case rev = "RevisionVideos"
    case qbank = "Qbank"

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .videos: return "Videos"
        case .r1: return "R1"
        case .r2: return "R2"
        case .pyqs: return "PYQs"
        case .rev: return "Rev"
        case .qbank: return "QBank"
        }
    }
}
