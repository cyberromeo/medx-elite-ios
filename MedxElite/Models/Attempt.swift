import Foundation

/// One timed block of a sectioned paper.
///
/// A Marrow grand paper is sat as 50+50+50, each block with its own clock and no way back
/// once it is submitted — that is what makes it a section rather than a bookmark. An
/// unsectioned paper is a single block over the whole thing, so the runner has one code path
/// rather than a sectioned and an unsectioned one.
public struct MedxRunnerSection: Identifiable, Hashable, Sendable {
    public let label: String
    /// Index of the first question, absolute in the paper.
    public let start: Int
    public let count: Int
    public let minutes: Int

    public var id: Int { start }
    public var end: Int { start + count }
    public var seconds: Int { max(minutes, 1) * 60 }

    public init(label: String, start: Int, count: Int, minutes: Int) {
        self.label = label
        self.start = start
        self.count = count
        self.minutes = minutes
    }

    /// Clamped to what the paper actually contains: the catalogue's question count and the
    /// number of documents that came through the export do not always agree, and a range
    /// running past the end of the array would trap.
    public static func clamped(_ sections: [MedxRunnerSection], to total: Int) -> [MedxRunnerSection] {
        var cursor = 0
        var out: [MedxRunnerSection] = []
        for section in sections {
            guard cursor < total else { break }
            let length = min(section.count, total - cursor)
            out.append(
                MedxRunnerSection(
                    label: section.label,
                    start: cursor,
                    count: length,
                    minutes: section.minutes
                )
            )
            cursor += length
        }
        return out.isEmpty ? [] : out
    }
}

/// One block, scored, as it is written into `medx_attempts`.
///
/// Field for field what the PWA writes (`useRunner.js:183`), so a sectioned sitting run on
/// either client reads correctly on the other.
public struct MedxAttemptSection: Identifiable, Hashable, Codable, Sendable {
    public let index: Int
    public let label: String
    public let total: Int
    public let score: Int
    public let attempted: Int
    public let seconds: Int

    public var id: Int { index }

    enum CodingKeys: String, CodingKey {
        case index, label, total, score, attempted, seconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = (try? container.decodeIfPresent(Int.self, forKey: .index)) ?? 0
        label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? "Section"
        total = (try? container.decodeIfPresent(Int.self, forKey: .total)) ?? 0
        score = (try? container.decodeIfPresent(Int.self, forKey: .score)) ?? 0
        attempted = (try? container.decodeIfPresent(Int.self, forKey: .attempted)) ?? 0
        seconds = (try? container.decodeIfPresent(Int.self, forKey: .seconds)) ?? 0
    }

    public init(index: Int, label: String, total: Int, score: Int, attempted: Int, seconds: Int) {
        self.index = index
        self.label = label
        self.total = total
        self.score = score
        self.attempted = attempted
        self.seconds = seconds
    }
}

public struct RunnerPayload: Identifiable, Hashable, Sendable {
    public let kind: String // "qbank", "test", "series", "custom" or "duel"
    public let id: String
    public let name: String
    public let subject: String
    public let mode: SittingMode
    public let gradable: Bool
    /// Questions supplied up front instead of fetched by `id`.
    ///
    /// A custom module and "practise these search results" assemble their questions from
    /// several source modules, so there is no single document the runner could load. When
    /// this is non-nil the runner skips the fetch entirely.
    public let questions: [Question]?
    /// Timed blocks, for a Marrow grand paper. `nil` is one block over the whole paper,
    /// which is what every caller outside the test series passes.
    public let sections: [MedxRunnerSection]?
    /// The paper's own official duration in exam mode, when it has one. `nil` falls back to
    /// one minute a question — Marrow's mini tests are 25 questions in 25 minutes either way,
    /// but a subject paper is not always.
    public let examSeconds: Int?

    public init(
        kind: String,
        id: String,
        name: String,
        subject: String,
        mode: SittingMode,
        gradable: Bool = true,
        questions: [Question]? = nil,
        sections: [MedxRunnerSection]? = nil,
        examSeconds: Int? = nil
    ) {
        self.kind = kind
        self.id = id
        self.name = name
        self.subject = subject
        self.mode = mode
        self.gradable = gradable
        self.questions = questions
        self.sections = sections
        self.examSeconds = examSeconds
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
    /// Present only for a sectioned paper. An unsectioned sitting files no breakdown rather
    /// than a one-row breakdown of itself.
    public let sections: [MedxAttemptSection]?

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
        case total, score, attempted, durationSeconds, finishedAt, responses, sections
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
        responses: [QuestionResponse],
        sections: [MedxAttemptSection]? = nil
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
        self.sections = sections
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
        // The PWA writes `sections: []` for an unsectioned paper, so an empty array is
        // normalised back to absent — otherwise the review screen would draw a breakdown
        // header over nothing.
        let decodedSections = container.decodeLenientArray(MedxAttemptSection.self, forKey: .sections)
        sections = (decodedSections?.isEmpty ?? true) ? nil : decodedSections
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

// MARK: - What produced a row

/// The five things that can file an attempt, and how each of them is named on screen.
///
/// `SittingAttempt.kind` stays a raw `String` rather than becoming this enum: both clients write
/// that field and the PWA is free to add a sixth kind tomorrow, so a row with an unrecognised kind
/// has to render as *something* rather than fail to decode. Hence the lookup, and hence
/// `label(_:)` taking the string and falling back rather than returning an optional.
public enum MedxAttemptKind: String, CaseIterable, Sendable {
    case qbank, test, series, custom, duel

    public var label: String {
        switch self {
        case .qbank: return "QBank"
        case .test: return "Batch paper"
        case .series: return "Marrow test"
        case .custom: return "Custom module"
        case .duel: return "Faceoff"
        }
    }

    public var sticker: String {
        switch self {
        case .qbank: return "brain"
        case .test: return "flag"
        case .series: return "trophy"
        case .custom: return "memo"
        case .duel: return "bolt"
        }
    }

    /// A kind that predates this list, or one only the PWA writes, is shown as a plain sitting.
    public static func label(_ raw: String) -> String {
        MedxAttemptKind(rawValue: raw)?.label ?? "Sitting"
    }

    public static func sticker(_ raw: String) -> String {
        MedxAttemptKind(rawValue: raw)?.sticker ?? "memo"
    }
}
