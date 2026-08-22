import Foundation

public struct RunnerPayload: Identifiable, Hashable, Sendable {
    public let kind: String // "qbank" or "test"
    public let id: String
    public let name: String
    public let subject: String
    public let mode: SittingMode
    public let gradable: Bool

    public init(kind: String, id: String, name: String, subject: String, mode: SittingMode, gradable: Bool = true) {
        self.kind = kind
        self.id = id
        self.name = name
        self.subject = subject
        self.mode = mode
        self.gradable = gradable
    }
}

public struct SittingAttempt: Identifiable, Hashable, Codable, Sendable {
    public let id: String?
    public let uid: String
    public let profile: String?
    public let kind: String // "qbank" or "test"
    public let sourceId: String
    public let name: String
    public let subject: String?
    public let mode: String // "exam" or "revision"
    public let gradable: Bool?
    public let total: Int
    public let score: Int
    public let attempted: Int
    public let durationSeconds: Int?
    public let finishedAt: String?
    public let responses: [QuestionResponse]

    public var accuracyPercentage: Int {
        guard attempted > 0 else { return 0 }
        return Int(round(Double(score) / Double(attempted) * 100.0))
    }

    public var totalPercentage: Int {
        guard total > 0 else { return 0 }
        return Int(round(Double(score) / Double(total) * 100.0))
    }

    enum CodingKeys: String, CodingKey {
        case id, uid, profile, kind, sourceId, name, subject, mode, gradable
        case total, score, attempted, durationSeconds, finishedAt, responses
    }

    public init(
        id: String?,
        uid: String,
        profile: String?,
        kind: String,
        sourceId: String,
        name: String,
        subject: String?,
        mode: String,
        gradable: Bool?,
        total: Int,
        score: Int,
        attempted: Int,
        durationSeconds: Int?,
        finishedAt: String?,
        responses: [QuestionResponse]
    ) {
        self.id = id
        self.uid = uid
        self.profile = profile
        self.kind = kind
        self.sourceId = sourceId
        self.name = name
        self.subject = subject
        self.mode = mode
        self.gradable = gradable
        self.total = total
        self.score = score
        self.attempted = attempted
        self.durationSeconds = durationSeconds
        self.finishedAt = finishedAt
        self.responses = responses
    }

    /// Lenient on purpose: an attempt written by an older build with a missing field used
    /// to be dropped wholesale, which silently deflated every stat on the Home screen.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        uid = (try? container.decodeIfPresent(String.self, forKey: .uid)) ?? ""
        profile = try? container.decodeIfPresent(String.self, forKey: .profile)
        kind = (try? container.decodeIfPresent(String.self, forKey: .kind)) ?? "qbank"
        sourceId = (try? container.decodeIfPresent(String.self, forKey: .sourceId)) ?? ""
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Sitting"
        subject = try? container.decodeIfPresent(String.self, forKey: .subject)
        mode = (try? container.decodeIfPresent(String.self, forKey: .mode)) ?? "exam"
        gradable = try? container.decodeIfPresent(Bool.self, forKey: .gradable)
        total = (try? container.decodeIfPresent(Int.self, forKey: .total)) ?? 0
        score = (try? container.decodeIfPresent(Int.self, forKey: .score)) ?? 0
        attempted = (try? container.decodeIfPresent(Int.self, forKey: .attempted)) ?? 0
        durationSeconds = try? container.decodeIfPresent(Int.self, forKey: .durationSeconds)
        finishedAt = try? container.decodeIfPresent(String.self, forKey: .finishedAt)
        responses = container.decodeLenientArray(QuestionResponse.self, forKey: .responses) ?? []
    }

    public var finishedDate: Date? {
        guard let finishedAt else { return nil }
        return ISO8601DateFormatter().date(from: finishedAt)
    }
}

public struct QuestionResponse: Identifiable, Hashable, Codable, Sendable {
    public var id: Int { questionId }
    public let questionId: Int
    public let chosenId: Int?
    public let correct: Bool
    public let timedOut: Bool?

    enum CodingKeys: String, CodingKey {
        case questionId, chosenId, correct, timedOut
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let qid = try? container.decode(Int.self, forKey: .questionId) {
            questionId = qid
        } else if let qidStr = try? container.decode(String.self, forKey: .questionId), let qid = Int(qidStr) {
            questionId = qid
        } else {
            questionId = 0
        }
        chosenId = try? container.decodeIfPresent(Int.self, forKey: .chosenId)
        correct = (try? container.decodeIfPresent(Bool.self, forKey: .correct)) ?? false
        timedOut = try? container.decodeIfPresent(Bool.self, forKey: .timedOut)
    }

    public init(questionId: Int, chosenId: Int?, correct: Bool, timedOut: Bool? = nil) {
        self.questionId = questionId
        self.chosenId = chosenId
        self.correct = correct
        self.timedOut = timedOut
    }
}

public enum SittingMode: String, CaseIterable, Identifiable, Sendable {
    case exam = "exam"
    case revision = "revision"

    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .exam: return "Exam Mode"
        case .revision: return "Revision Mode"
        }
    }
    public var description: String {
        switch self {
        case .exam: return "1 minute per question total timer. Grade and explanations revealed at the end."
        case .revision: return "60s per question timer. Instant answer reveal & explanations as you answer."
        }
    }
}
