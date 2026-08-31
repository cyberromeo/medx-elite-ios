import Foundation

// MARK: - The Marrow FMGE test series
//
// 352 keyed papers, 25,163 questions, catalogued in a single Firestore document
// (`medx_meta/series_fmge`) so the whole Tests screen costs one read and can then filter and
// group in memory. Questions are only fetched when a paper is actually opened, and they live
// in `medx_test_questions` alongside the four ARISE papers under the same `testId` field —
// Marrow's 24-character hex ids and ARISE's `test_<n>` ids cannot collide, which is why
// `FirestoreService.fetchTestQuestions` needs no series-specific branch.

public enum MedxSeriesGroup: String, CaseIterable, Identifiable, Codable, Sendable {
    case grand
    case mini
    case subject

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .grand: return "GTs"
        case .mini: return "Mini tests"
        case .subject: return "Subject tests"
        }
    }

    /// A subject paper names its subject in its title ("FMGE Sprint Series- ANATOMY"), so it
    /// gets the subject's own mark and `nil` here means "use the subject's symbol". The grand
    /// and mini papers have nothing to key off, and letting the subject hash decide put a
    /// random teddy bear next to a grand test — so they take their group's mark instead.
    public var symbol: String? {
        switch self {
        case .grand: return "trophy.fill"
        case .mini: return "bolt.fill"
        case .subject: return nil
        }
    }
}

public struct MedxSeriesPaper: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let group: MedxSeriesGroup
    public let year: String?
    public let questions: Int
    public let durationMin: Int
    /// When the paper ran, as epoch milliseconds in the seeded document.
    public let startAt: Double
    public let isPaid: Bool
    /// Papers the dump never fetched carry `false` and are dropped on read — there is
    /// nothing to open.
    public let hasQuestions: Bool

    public var startDate: Date? {
        startAt > 0 ? Date(timeIntervalSince1970: startAt / 1000) : nil
    }
    /// The one-line shape of the paper: "150 q · 150 min".
    public var line: String {
        "\(questions.formatted()) q · \((durationMin > 0 ? durationMin : questions).formatted()) min"
    }

    enum CodingKeys: String, CodingKey {
        case id, title, type, year, questions, durationMin, startAt, isPaid, hasQuestions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? "Paper"
        let raw = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? "subject"
        group = MedxSeriesGroup(rawValue: raw) ?? .subject
        year = try? container.decodeIfPresent(String.self, forKey: .year)
        questions = (try? container.decodeIfPresent(Int.self, forKey: .questions)) ?? 0
        durationMin = (try? container.decodeIfPresent(Int.self, forKey: .durationMin)) ?? 0
        // Epoch millis arrive as an integer that overflows nothing but is worth taking as a
        // Double so a future seeder writing it as one still decodes.
        if let double = try? container.decodeIfPresent(Double.self, forKey: .startAt) {
            startAt = double
        } else if let int = try? container.decodeIfPresent(Int.self, forKey: .startAt) {
            startAt = Double(int)
        } else {
            startAt = 0
        }
        isPaid = (try? container.decodeIfPresent(Bool.self, forKey: .isPaid)) ?? false
        hasQuestions = (try? container.decodeIfPresent(Bool.self, forKey: .hasQuestions)) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(group.rawValue, forKey: .type)
        try container.encodeIfPresent(year, forKey: .year)
        try container.encode(questions, forKey: .questions)
        try container.encode(durationMin, forKey: .durationMin)
        try container.encode(startAt, forKey: .startAt)
        try container.encode(isPaid, forKey: .isPaid)
        try container.encode(hasQuestions, forKey: .hasQuestions)
    }

    public init(
        id: String,
        title: String,
        group: MedxSeriesGroup,
        year: String? = nil,
        questions: Int,
        durationMin: Int,
        startAt: Double = 0,
        isPaid: Bool = false,
        hasQuestions: Bool = true
    ) {
        self.id = id
        self.title = title
        self.group = group
        self.year = year
        self.questions = questions
        self.durationMin = durationMin
        self.startAt = startAt
        self.isPaid = isPaid
        self.hasQuestions = hasQuestions
    }
}

public struct MedxSeriesIndex: Codable, Hashable, Sendable {
    public let course: String?
    public let name: String?
    public let papers: [MedxSeriesPaper]
    public let totalPapers: Int
    public let totalQuestions: Int

    /// How many papers each group has, taken from the papers actually kept rather than from
    /// the document's own counts — the catalogue counts all 376 and 24 of those have no
    /// questions to open.
    public func count(of group: MedxSeriesGroup) -> Int {
        papers.reduce(0) { $1.group == group ? $0 + 1 : $0 }
    }

    public func paper(id: String) -> MedxSeriesPaper? {
        papers.first { $0.id == id }
    }

    enum CodingKeys: String, CodingKey {
        case course, name, counts, tests
    }

    private struct Counts: Codable {
        let papers: Int?
        let questions: Int?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        course = try? container.decodeIfPresent(String.self, forKey: .course)
        name = try? container.decodeIfPresent(String.self, forKey: .name)
        let all = container.decodeLenientArray(MedxSeriesPaper.self, forKey: .tests) ?? []
        papers = all.filter { $0.hasQuestions }
        let counts = try? container.decodeIfPresent(Counts.self, forKey: .counts)
        totalPapers = counts?.papers ?? papers.count
        totalQuestions = counts?.questions ?? papers.reduce(0) { $0 + $1.questions }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(course, forKey: .course)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(papers, forKey: .tests)
    }

    public init(course: String?, name: String?, papers: [MedxSeriesPaper]) {
        self.course = course
        self.name = name
        self.papers = papers
        self.totalPapers = papers.count
        self.totalQuestions = papers.reduce(0) { $0 + $1.questions }
    }
}

// MARK: - How a paper is grouped, and how it is sat

/// One month's worth of papers.
public struct MedxSeriesMonth: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let papers: [MedxSeriesPaper]
}

/// The rules of the series: how the papers are bucketed, and the one rule that turns a grand
/// paper into a sectioned sitting.
///
/// Deliberately free of anything but Foundation, and deliberately *not* seeded data. How a
/// paper is *sat* is a rule about this app, not a fact about the paper, so changing it should
/// not mean re-seeding 109 MB.
public enum MedxSeriesRules {
    /// One minute a question, which is what makes a 50-question block 50 minutes.
    public static let sectionSize = 50

    /// Grand papers are sat in blocks of 50, each with its own clock and no way back once
    /// submitted: 150 questions is 50+50+50, and the two 300-question mocks are six blocks by
    /// the same rule. Everything else is one sitting on Marrow's own official duration, so
    /// `nil` here means "unsectioned" — which is what every paper outside this series is.
    public static func sections(for paper: MedxSeriesPaper) -> [MedxRunnerSection]? {
        let total = paper.questions
        guard paper.group == .grand, total > sectionSize else { return nil }
        let count = Int(ceil(Double(total) / Double(sectionSize)))
        return (0..<count).map { index in
            let start = index * sectionSize
            let length = min(sectionSize, total - start)
            return MedxRunnerSection(
                label: "Section \(index + 1)",
                start: start,
                count: length,
                minutes: length
            )
        }
    }

    /// What exam mode is about to do, said in one line inside the mode picker. A sectioned
    /// paper is not something to walk into by mistake.
    public static func examBlurb(for paper: MedxSeriesPaper) -> String {
        guard let sections = sections(for: paper), let first = sections.first else {
            let minutes = paper.durationMin > 0 ? paper.durationMin : paper.questions
            return "One \(minutes)-minute timer for the paper. Answers after you submit."
        }
        return "\(sections.count) sections of \(first.count), \(first.minutes) minutes each. "
            + "No going back once a section is submitted."
    }
    /// The mark on a paper's row.
    public static func symbol(for paper: MedxSeriesPaper) -> String {
        paper.group.symbol ?? MedxSubjectArt.symbol(for: paper.title)
    }

    private static let monthKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    private static let monthLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()

    /// Papers bucketed by the month they ran, newest month first and newest paper first
    /// inside it — so scrolling down is going back through seven years of papers, the same
    /// shape the VOD feed uses for the bucket.
    public static func byMonth(_ papers: [MedxSeriesPaper]) -> [MedxSeriesMonth] {
        var order: [String] = []
        var buckets: [String: (label: String, papers: [MedxSeriesPaper])] = [:]

        for paper in papers.sorted(by: { $0.startAt > $1.startAt }) {
            let key: String
            let label: String
            if let date = paper.startDate {
                key = monthKeyFormatter.string(from: date)
                label = monthLabelFormatter.string(from: date)
            } else {
                key = "undated"
                label = "Undated"
            }
            if buckets[key] == nil {
                buckets[key] = (label, [])
                order.append(key)
            }
            buckets[key]?.papers.append(paper)
        }

        return order.compactMap { key in
            guard let bucket = buckets[key] else { return nil }
            return MedxSeriesMonth(id: key, label: bucket.label, papers: bucket.papers)
        }
    }
}
