import Foundation

// MARK: - Lenient array decoding

/// Placeholder that decodes from any JSON value without ever throwing. Used to step past
/// an element the real model rejected — an unkeyed container does not advance its cursor
/// on a failed `decode`, so without this the skip loop would spin forever.
struct MedxSkippedElement: Decodable {
    init(from decoder: Decoder) throws {
        _ = try? decoder.singleValueContainer()
    }
}

extension KeyedDecodingContainer {
    /// Decodes an array element by element and drops the ones that fail.
    ///
    /// Arise's exported modules occasionally carry one question with a field shape the
    /// model does not expect. Decoding `[Question]` in one shot meant that single bad
    /// entry made the whole 40-question module unavailable; now only it is lost.
    func decodeLenientArray<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T]? {
        guard contains(key) else { return nil }
        guard var container = try? nestedUnkeyedContainer(forKey: key) else { return nil }

        var items: [T] = []
        let bound = (container.count ?? 0) + 1
        var iterations = 0

        while !container.isAtEnd, iterations < bound {
            iterations += 1
            if let item = try? container.decode(T.self) {
                items.append(item)
            } else {
                _ = try? container.decode(MedxSkippedElement.self)
            }
        }

        return items
    }
}

public struct QBankSubject: Identifiable, Hashable, Codable, Sendable {
    public var id: Int { subjectId }
    public let subjectId: Int
    public let name: String
    public let slug: String?
    public let moduleCount: Int
    public let questionCount: Int?
    public let chapters: [QBankChapter]?

    enum CodingKeys: String, CodingKey {
        case subjectId, name, slug, moduleCount, questionCount, chapters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intVal = try? container.decode(Int.self, forKey: .subjectId) {
            subjectId = intVal
        } else if let strVal = try? container.decode(String.self, forKey: .subjectId), let intVal = Int(strVal) {
            subjectId = intVal
        } else {
            subjectId = 0
        }
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        slug = try? container.decodeIfPresent(String.self, forKey: .slug)
        moduleCount = (try? container.decodeIfPresent(Int.self, forKey: .moduleCount)) ?? 0
        questionCount = try? container.decodeIfPresent(Int.self, forKey: .questionCount)
        chapters = container.decodeLenientArray(QBankChapter.self, forKey: .chapters)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(subjectId, forKey: .subjectId)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(slug, forKey: .slug)
        try container.encode(moduleCount, forKey: .moduleCount)
        try container.encodeIfPresent(questionCount, forKey: .questionCount)
        try container.encodeIfPresent(chapters, forKey: .chapters)
    }

    public init(subjectId: Int, name: String, slug: String?, moduleCount: Int, questionCount: Int?, chapters: [QBankChapter]?) {
        self.subjectId = subjectId
        self.name = name
        self.slug = slug
        self.moduleCount = moduleCount
        self.questionCount = questionCount
        self.chapters = chapters
    }
}

public struct QBankChapter: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let name: String
    public let modules: [QBankModuleSummary]?

    enum CodingKeys: String, CodingKey {
        case id, name, modules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intVal = try? container.decode(Int.self, forKey: .id) {
            id = intVal
        } else if let strVal = try? container.decode(String.self, forKey: .id), let intVal = Int(strVal) {
            id = intVal
        } else {
            id = 0
        }
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        modules = container.decodeLenientArray(QBankModuleSummary.self, forKey: .modules)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(modules, forKey: .modules)
    }

    public init(id: Int, name: String, modules: [QBankModuleSummary]?) {
        self.id = id
        self.name = name
        self.modules = modules
    }
}

public struct QBankModuleSummary: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let questionCount: Int
    public let chapter: String?

    enum CodingKeys: String, CodingKey {
        case id, name, questionCount, chapter
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let strVal = try? container.decode(String.self, forKey: .id) {
            id = strVal
        } else if let intVal = try? container.decode(Int.self, forKey: .id) {
            id = String(intVal)
        } else {
            id = UUID().uuidString
        }
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        questionCount = (try? container.decodeIfPresent(Int.self, forKey: .questionCount)) ?? 0
        chapter = try? container.decodeIfPresent(String.self, forKey: .chapter)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(questionCount, forKey: .questionCount)
        try container.encodeIfPresent(chapter, forKey: .chapter)
    }

    public init(id: String, name: String, questionCount: Int, chapter: String? = nil) {
        self.id = id
        self.name = name
        self.questionCount = questionCount
        self.chapter = chapter
    }
}

public struct QBankModuleDetail: Identifiable, Hashable, Codable, Sendable {
    public var id: String { moduleId }
    public let moduleId: String
    public let subjectId: Int?
    public let subject: String?
    public let chapterId: Int?
    public let chapter: String?
    public let name: String
    public let description: String?
    public let questionCount: Int
    public let questions: [Question]?
    public let partCount: Int?

    public init(
        moduleId: String,
        subjectId: Int? = nil,
        subject: String? = nil,
        chapterId: Int? = nil,
        chapter: String? = nil,
        name: String,
        description: String? = nil,
        questionCount: Int,
        questions: [Question]? = nil,
        partCount: Int? = nil
    ) {
        self.moduleId = moduleId
        self.subjectId = subjectId
        self.subject = subject
        self.chapterId = chapterId
        self.chapter = chapter
        self.name = name
        self.description = description
        self.questionCount = questionCount
        self.questions = questions
        self.partCount = partCount
    }

    enum CodingKeys: String, CodingKey {
        case id, moduleId, subjectId, subject, chapterId, chapter
        case name, description, questionCount, questions, partCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let mid = try? container.decode(String.self, forKey: .moduleId) {
            moduleId = mid
        } else if let idVal = try? container.decode(String.self, forKey: .id) {
            moduleId = idVal
        } else {
            moduleId = ""
        }
        subjectId = try? container.decodeIfPresent(Int.self, forKey: .subjectId)
        subject = try? container.decodeIfPresent(String.self, forKey: .subject)
        chapterId = try? container.decodeIfPresent(Int.self, forKey: .chapterId)
        chapter = try? container.decodeIfPresent(String.self, forKey: .chapter)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Module"
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        questions = container.decodeLenientArray(Question.self, forKey: .questions)
        // Trust the questions actually decoded over the exported count, so the runner's
        // timer and progress track cannot disagree with what is on screen.
        let declared = (try? container.decodeIfPresent(Int.self, forKey: .questionCount)) ?? 0
        questionCount = questions?.count ?? declared
        partCount = try? container.decodeIfPresent(Int.self, forKey: .partCount)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(moduleId, forKey: .moduleId)
        try container.encodeIfPresent(subjectId, forKey: .subjectId)
        try container.encodeIfPresent(subject, forKey: .subject)
        try container.encodeIfPresent(chapterId, forKey: .chapterId)
        try container.encodeIfPresent(chapter, forKey: .chapter)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(questionCount, forKey: .questionCount)
        try container.encodeIfPresent(questions, forKey: .questions)
        try container.encodeIfPresent(partCount, forKey: .partCount)
    }
}

public struct Question: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let lqId: Int?
    public let number: Int?
    public let html: String?
    public let plain: String?
    public let type: String?
    public let answerType: String?
    public let options: [QuestionOption]
    public let correctIds: [Int]
    public let explanation: String?
    public let reference: String?
    public let images: [String]?

    public var displayText: String {
        html ?? plain ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case id, lqId, number, html, plain, type, answerType, options, correctIds, explanation, reference, images
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intVal = try? container.decode(Int.self, forKey: .id) {
            id = intVal
        } else if let strVal = try? container.decode(String.self, forKey: .id), let intVal = Int(strVal) {
            id = intVal
        } else {
            id = 0
        }
        lqId = try? container.decodeIfPresent(Int.self, forKey: .lqId)
        number = try? container.decodeIfPresent(Int.self, forKey: .number)
        html = try? container.decodeIfPresent(String.self, forKey: .html)
        plain = try? container.decodeIfPresent(String.self, forKey: .plain)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
        answerType = try? container.decodeIfPresent(String.self, forKey: .answerType)
        options = container.decodeLenientArray(QuestionOption.self, forKey: .options) ?? []
        correctIds = container.decodeLenientArray(Int.self, forKey: .correctIds) ?? []
        explanation = try? container.decodeIfPresent(String.self, forKey: .explanation)
        reference = try? container.decodeIfPresent(String.self, forKey: .reference)
        images = container.decodeLenientArray(String.self, forKey: .images)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(lqId, forKey: .lqId)
        try container.encodeIfPresent(number, forKey: .number)
        try container.encodeIfPresent(html, forKey: .html)
        try container.encodeIfPresent(plain, forKey: .plain)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(answerType, forKey: .answerType)
        try container.encode(options, forKey: .options)
        try container.encode(correctIds, forKey: .correctIds)
        try container.encodeIfPresent(explanation, forKey: .explanation)
        try container.encodeIfPresent(reference, forKey: .reference)
        try container.encodeIfPresent(images, forKey: .images)
    }

    public init(
        id: Int,
        lqId: Int? = nil,
        number: Int? = nil,
        html: String? = nil,
        plain: String? = nil,
        type: String? = nil,
        answerType: String? = nil,
        options: [QuestionOption] = [],
        correctIds: [Int] = [],
        explanation: String? = nil,
        reference: String? = nil,
        images: [String]? = nil
    ) {
        self.id = id
        self.lqId = lqId
        self.number = number
        self.html = html
        self.plain = plain
        self.type = type
        self.answerType = answerType
        self.options = options
        self.correctIds = correctIds
        self.explanation = explanation
        self.reference = reference
        self.images = images
    }
}

public struct QuestionOption: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let label: String
    public let text: String
    public let correct: Bool?

    enum CodingKeys: String, CodingKey {
        case id, label, text, correct
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intVal = try? container.decode(Int.self, forKey: .id) {
            id = intVal
        } else if let strVal = try? container.decode(String.self, forKey: .id), let intVal = Int(strVal) {
            id = intVal
        } else {
            id = 0
        }
        label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? ""
        text = (try? container.decodeIfPresent(String.self, forKey: .text)) ?? ""
        correct = try? container.decodeIfPresent(Bool.self, forKey: .correct)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(correct, forKey: .correct)
    }

    public init(id: Int, label: String, text: String, correct: Bool? = nil) {
        self.id = id
        self.label = label
        self.text = text
        self.correct = correct
    }
}
