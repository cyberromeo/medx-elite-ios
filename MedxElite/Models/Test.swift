import Foundation

public struct BatchTest: Identifiable, Hashable, Codable, Sendable {
    public var id: String { testId }
    public let testId: String
    public let batchId: String?
    public let batch: String?
    public let name: String
    public let subject: String
    public let mode: String?
    public let testType: String?
    public let section: String?
    public let questionCount: Int
    public let officialTimeMins: Int
    public let gradable: Bool
    public let gradedCount: Int?
    public let priorAttempt: PriorAttemptInfo?
    public let performanceStats: [String: AnyCodableSendable]?
    public let rankInfo: [String: AnyCodableSendable]?

    enum CodingKeys: String, CodingKey {
        case id, testId, batchId, batch, name, subject, mode, testType, section
        case questionCount, officialTimeMins, gradable, gradedCount, priorAttempt
        case performanceStats, rankInfo
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let tid = try? container.decode(String.self, forKey: .testId) {
            testId = tid
        } else if let idVal = try? container.decode(String.self, forKey: .id) {
            testId = idVal
        } else {
            testId = UUID().uuidString
        }
        batchId = try container.decodeIfPresent(String.self, forKey: .batchId)
        batch = try container.decodeIfPresent(String.self, forKey: .batch)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Test"
        subject = try container.decodeIfPresent(String.self, forKey: .subject) ?? ""
        mode = try container.decodeIfPresent(String.self, forKey: .mode)
        testType = try container.decodeIfPresent(String.self, forKey: .testType)
        section = try container.decodeIfPresent(String.self, forKey: .section)
        questionCount = try container.decodeIfPresent(Int.self, forKey: .questionCount) ?? 0
        officialTimeMins = try container.decodeIfPresent(Int.self, forKey: .officialTimeMins) ?? questionCount
        gradable = try container.decodeIfPresent(Bool.self, forKey: .gradable) ?? false
        gradedCount = try container.decodeIfPresent(Int.self, forKey: .gradedCount)
        priorAttempt = try container.decodeIfPresent(PriorAttemptInfo.self, forKey: .priorAttempt)
        performanceStats = try container.decodeIfPresent([String: AnyCodableSendable].self, forKey: .performanceStats)
        rankInfo = try container.decodeIfPresent([String: AnyCodableSendable].self, forKey: .rankInfo)
    }
}

public struct PriorAttemptInfo: Hashable, Codable, Sendable {
    public let status: String?
    public let correct: Int?
    public let questionCount: Int?
    public let testRank: Int?
}

/// Helper wrapper for generic JSON decoding in Codable structs
public struct AnyCodableSendable: Codable, Hashable, Sendable {
    public let value: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self) {
            value = String(double)
        } else if let bool = try? container.decode(Bool.self) {
            value = String(bool)
        } else {
            value = ""
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
