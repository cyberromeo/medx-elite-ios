import Foundation

public struct QODResponse: Codable, Sendable {
    public let status: String?
    public let data: QODData?
}

public struct QODData: Identifiable, Hashable, Codable, Sendable {
    public var id: Int { questionId ?? 0 }
    public let questionId: Int?
    public let question: String?
    public let subject: String?
    public let answers: [QODAnswer]?
    public let ansExplanation: String?

    enum CodingKeys: String, CodingKey {
        case questionId, question, subject, answers, ansExplanation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intVal = try? container.decode(Int.self, forKey: .questionId) {
            questionId = intVal
        } else if let strVal = try? container.decode(String.self, forKey: .questionId), let intVal = Int(strVal) {
            questionId = intVal
        } else {
            questionId = 0
        }
        question = try container.decodeIfPresent(String.self, forKey: .question)
        subject = try container.decodeIfPresent(String.self, forKey: .subject)
        answers = try container.decodeIfPresent([QODAnswer].self, forKey: .answers)
        ansExplanation = try container.decodeIfPresent(String.self, forKey: .ansExplanation)
    }

    public var correctChoiceId: Int? {
        answers?.first { $0.correct == true }?.answerId
    }
}

public struct QODAnswer: Identifiable, Hashable, Codable, Sendable {
    public var id: Int { answerId }
    public let answerId: Int
    public let answer: String?
    public let correct: Bool?

    enum CodingKeys: String, CodingKey {
        case answerId, answer, correct
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intVal = try? container.decode(Int.self, forKey: .answerId) {
            answerId = intVal
        } else if let strVal = try? container.decode(String.self, forKey: .answerId), let intVal = Int(strVal) {
            answerId = intVal
        } else {
            answerId = 0
        }
        answer = try container.decodeIfPresent(String.self, forKey: .answer)
        correct = try container.decodeIfPresent(Bool.self, forKey: .correct)
    }
}
