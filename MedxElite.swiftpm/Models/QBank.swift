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
        correctIds = (container.decodeLenientArray(MedxOptionId.self, forKey: .correctIds) ?? []).map(\.value)
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

/// One option id as it arrives on the wire, in either shape the backend uses.
///
/// ARISE options are numbered — `333631` — and Marrow's are strings shaped
/// `<questionId>_<ordinal>`: `"40340_1"`. Everything downstream compares option ids as `Int`:
/// `correctIds.contains(option.id)` scores the answer, `QuestionResponse.chosenId` records it, and
/// SwiftUI's `ForEach` uses it as the row's identity. So the string form is folded to an `Int`
/// here, by the same rule on both sides of every one of those comparisons.
///
/// The trailing ordinal is what survives, because it is unique inside a question and a question is
/// the only scope any of those comparisons has. Before this, a non-numeric id fell to `0`: all four
/// options of a Marrow question were then identical to `ForEach`, which drew option A four times,
/// and `correctIds` decoded to empty, which scored every Marrow answer wrong.
public struct MedxOptionId: Decodable, Sendable {
    public let value: Int

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let intVal = try? single.decode(Int.self) {
            value = intVal
        } else {
            value = Self.int(from: try single.decode(String.self))
        }
    }

    public static func int(from raw: String) -> Int {
        if let direct = Int(raw) { return direct }
        if let tail = raw.split(separator: "_").last, let ordinal = Int(tail) { return ordinal }
        // Neither shape. A stable non-zero djb2 so identity is at least distinct per option text,
        // rather than every option collapsing onto the same row.
        var hash = 5381
        for byte in raw.utf8 { hash = (hash &* 33) &+ Int(byte) }
        return abs(hash % 1_000_003) + 1
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
        } else if let strVal = try? container.decode(String.self, forKey: .id) {
            id = MedxOptionId.int(from: strVal)
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

// MARK: - The two banks

/// ARISE is the batch's own bank — 1,211 modules cut by chapter. Marrow FMGE is 960
/// lesson-sized modules plus 3,554 previous-year questions.
///
/// They are seeded into the *same* `medx_qbank_modules` collection in the *same* document
/// shape and differ only in the `mw_` prefix on every Marrow id, which is why
/// `FirestoreService.fetchQBankModule` needs no branch and the runner never learns that a
/// second bank exists. `of(_:)` works on an id alone, so a subject page or a saved custom
/// module stays bank-agnostic.
public enum MedxBank: String, CaseIterable, Identifiable, Codable, Sendable {
    case arise
    case marrow

    public var id: String { rawValue }

    public static let marrowPrefix = "mw_"

    /// Works for subject, chapter and module ids alike.
    public static func of(_ id: String) -> MedxBank {
        id.hasPrefix(marrowPrefix) ? .marrow : .arise
    }

    public static let arisePrefix = "qb_"

    /// Whether an id names a real module in `medx_qbank_modules`, as opposed to one of the
    /// synthetic `search-…` / `custom-…` ids a filtered sitting is given. Both seeders prefix
    /// theirs — ARISE `qb_<n>`, Marrow `mw_<hex>` — and the distinction matters because an
    /// attempt row's `sourceId` is the only place a `medx_attempts` response can learn which
    /// module, and therefore which bank, it belongs to.
    public static func isModuleId(_ id: String) -> Bool {
        id.hasPrefix(arisePrefix) || id.hasPrefix(marrowPrefix)
    }

    public var label: String {
        switch self {
        case .arise: return "Arise"
        case .marrow: return "Marrow"
        }
    }

    public var eyebrow: String {
        switch self {
        case .arise: return "ARISE · Online Dec 26"
        case .marrow: return "Marrow · FMGE"
        }
    }

    /// The SF Symbol on a bank's chip and header. Both banks are question banks, so the
    /// difference has to be legible at chip size: ARISE is the live course, Marrow is the
    /// archive.
    public var symbol: String {
        switch self {
        case .arise: return "graduationcap.fill"
        case .marrow: return "archivebox.fill"
        }
    }
}

// MARK: - Bank-agnostic tree

/// A subject in either bank.
///
/// `QBankSubject.subjectId` is an `Int` and `QBankChapter.id` is an `Int`, which the ARISE
/// tree satisfies and Marrow does not: its ids are `mw_618a04d13dcbce9c59c6bb59` and
/// `mw_618a04d13dcbce9c59c6bb59_anatomy`. Rather than widen those two types — they are read by
/// the batch-paper screens and every `[Int: …]` tally keyed on a subject — this is added
/// alongside them and is the model every *new* screen reads, with the ARISE tree adapting in
/// through `init(arise:)`. The question index and Spotlight are both keyed on `id` as a string,
/// so they cover both banks.
public struct MedxBankSubject: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let bank: MedxBank
    public let name: String
    public let slug: String?
    public let moduleCount: Int
    public let questionCount: Int
    public let chapters: [MedxBankChapter]

    /// Every module in the subject, flattened — what the custom-module builder and the
    /// coverage tallies both want.
    public var modules: [QBankModuleSummary] {
        chapters.flatMap { $0.modules }
    }

    enum CodingKeys: String, CodingKey {
        case id, bank, name, slug, moduleCount, questionCount, chapters
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
        // The seeded document carries `bank`, but deriving it from the id is the one reading
        // that cannot go stale if a future seeder forgets the field.
        bank = MedxBank.of(id)
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        slug = try? container.decodeIfPresent(String.self, forKey: .slug)
        moduleCount = (try? container.decodeIfPresent(Int.self, forKey: .moduleCount)) ?? 0
        questionCount = (try? container.decodeIfPresent(Int.self, forKey: .questionCount)) ?? 0
        chapters = container.decodeLenientArray(MedxBankChapter.self, forKey: .chapters) ?? []
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(bank, forKey: .bank)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(slug, forKey: .slug)
        try container.encode(moduleCount, forKey: .moduleCount)
        try container.encode(questionCount, forKey: .questionCount)
        try container.encode(chapters, forKey: .chapters)
    }

    public init(
        id: String,
        bank: MedxBank,
        name: String,
        slug: String? = nil,
        moduleCount: Int,
        questionCount: Int,
        chapters: [MedxBankChapter]
    ) {
        self.id = id
        self.bank = bank
        self.name = name
        self.slug = slug
        self.moduleCount = moduleCount
        self.questionCount = questionCount
        self.chapters = chapters
    }

    /// The ARISE tree, adapted.
    public init(arise: QBankSubject) {
        self.id = String(arise.subjectId)
        self.bank = .arise
        self.name = arise.name
        self.slug = arise.slug
        self.moduleCount = arise.moduleCount
        self.questionCount = arise.questionCount ?? 0
        self.chapters = (arise.chapters ?? []).map { MedxBankChapter(arise: $0) }
    }
}

public struct MedxBankChapter: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let modules: [QBankModuleSummary]

    enum CodingKeys: String, CodingKey {
        case id, name, modules
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
        modules = container.decodeLenientArray(QBankModuleSummary.self, forKey: .modules) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(modules, forKey: .modules)
    }

    public init(id: String, name: String, modules: [QBankModuleSummary]) {
        self.id = id
        self.name = name
        self.modules = modules
    }

    public init(arise: QBankChapter) {
        self.id = String(arise.id)
        self.name = arise.name
        self.modules = arise.modules ?? []
    }
}
/// `medx_meta/qbank_fmge` — the whole Marrow tree in one document, so the QBank screen costs
/// one read for 20 subjects, 960 modules and 14,577 questions.
public struct MedxBankIndex: Codable, Hashable, Sendable {
    public let course: String?
    public let name: String?
    public let subjects: [MedxBankSubject]

    enum CodingKeys: String, CodingKey {
        case course, name, subjects
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        course = try? container.decodeIfPresent(String.self, forKey: .course)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        subjects = container.decodeLenientArray(MedxBankSubject.self, forKey: .subjects) ?? []
    }

    public init(course: String?, name: String?, subjects: [MedxBankSubject]) {
        self.course = course
        self.name = name
        self.subjects = subjects
    }
}
