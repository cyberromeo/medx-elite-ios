import Foundation

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
        chosenId = try container.decodeIfPresent(Int.self, forKey: .chosenId)
        correct = try container.decodeIfPresent(Bool.self, forKey: .correct) ?? false
        timedOut = try container.decodeIfPresent(Bool.self, forKey: .timedOut)
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
