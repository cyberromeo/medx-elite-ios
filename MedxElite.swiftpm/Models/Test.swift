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
        batchId = try? container.decodeIfPresent(String.self, forKey: .batchId)
        batch = try? container.decodeIfPresent(String.self, forKey: .batch)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Test"
        subject = (try? container.decodeIfPresent(String.self, forKey: .subject)) ?? ""
        mode = try? container.decodeIfPresent(String.self, forKey: .mode)
        testType = try? container.decodeIfPresent(String.self, forKey: .testType)
        section = try? container.decodeIfPresent(String.self, forKey: .section)
        questionCount = (try? container.decodeIfPresent(Int.self, forKey: .questionCount)) ?? 0
        officialTimeMins = (try? container.decodeIfPresent(Int.self, forKey: .officialTimeMins)) ?? questionCount
        gradable = (try? container.decodeIfPresent(Bool.self, forKey: .gradable)) ?? false
        gradedCount = try? container.decodeIfPresent(Int.self, forKey: .gradedCount)
        // Arise writes these three as free-form maps and sometimes not at all. A shape we
        // do not model must not take the whole test down with it, so they decode leniently.
        priorAttempt = try? container.decodeIfPresent(PriorAttemptInfo.self, forKey: .priorAttempt)
        performanceStats = try? container.decodeIfPresent([String: AnyCodableSendable].self, forKey: .performanceStats)
        rankInfo = try? container.decodeIfPresent([String: AnyCodableSendable].self, forKey: .rankInfo)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(testId, forKey: .testId)
        try container.encodeIfPresent(batchId, forKey: .batchId)
        try container.encodeIfPresent(batch, forKey: .batch)
        try container.encode(name, forKey: .name)
        try container.encode(subject, forKey: .subject)
        try container.encodeIfPresent(mode, forKey: .mode)
        try container.encodeIfPresent(testType, forKey: .testType)
        try container.encodeIfPresent(section, forKey: .section)
        try container.encode(questionCount, forKey: .questionCount)
        try container.encode(officialTimeMins, forKey: .officialTimeMins)
        try container.encode(gradable, forKey: .gradable)
        try container.encodeIfPresent(gradedCount, forKey: .gradedCount)
        try container.encodeIfPresent(priorAttempt, forKey: .priorAttempt)
        try container.encodeIfPresent(performanceStats, forKey: .performanceStats)
        try container.encodeIfPresent(rankInfo, forKey: .rankInfo)
    }

    public init(
        testId: String,
        batchId: String? = nil,
        batch: String? = nil,
        name: String,
        subject: String,
        mode: String? = nil,
        testType: String? = nil,
        section: String? = nil,
        questionCount: Int,
        officialTimeMins: Int,
        gradable: Bool,
        gradedCount: Int? = nil,
        priorAttempt: PriorAttemptInfo? = nil,
        performanceStats: [String: AnyCodableSendable]? = nil,
        rankInfo: [String: AnyCodableSendable]? = nil
    ) {
        self.testId = testId
        self.batchId = batchId
        self.batch = batch
        self.name = name
        self.subject = subject
        self.mode = mode
        self.testType = testType
        self.section = section
        self.questionCount = questionCount
        self.officialTimeMins = officialTimeMins
        self.gradable = gradable
        self.gradedCount = gradedCount
        self.priorAttempt = priorAttempt
        self.performanceStats = performanceStats
        self.rankInfo = rankInfo
    }
}

public struct PriorAttemptInfo: Hashable, Codable, Sendable {
    public let status: String?
    public let correct: Int?
    public let questionCount: Int?
    public let testRank: Int?

    public init(status: String? = nil, correct: Int? = nil, questionCount: Int? = nil, testRank: Int? = nil) {
        self.status = status
        self.correct = correct
        self.questionCount = questionCount
        self.testRank = testRank
    }
}

/// Helper wrapper for generic JSON decoding in Codable structs
public struct AnyCodableSendable: Codable, Hashable, Sendable {
    public let value: String

    public init(value: String = "") {
        self.value = value
    }

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
