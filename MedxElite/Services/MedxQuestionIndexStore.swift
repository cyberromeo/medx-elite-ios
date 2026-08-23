import Foundation
import Combine

// MARK: - Index entry

/// One question, flattened for search. Only what a result row needs plus the ids required
/// to fetch the real question back out of its module.
public struct MedxIndexedQuestion: Codable, Hashable, Sendable, Identifiable {
    public var id: String { "\(moduleId)#\(questionId)" }
    public let questionId: Int
    public let moduleId: String
    public let moduleName: String
    public let subjectId: Int
    public let subject: String
    public let chapter: String
    /// HTML-stripped question stem, capped — enough to recognise and to match against.
    public let text: String
    public let hasImage: Bool
    public let optionCount: Int

    public init(
        questionId: Int,
        moduleId: String,
        moduleName: String,
        subjectId: Int,
        subject: String,
        chapter: String,
        text: String,
        hasImage: Bool,
        optionCount: Int
    ) {
        self.questionId = questionId
        self.moduleId = moduleId
        self.moduleName = moduleName
        self.subjectId = subjectId
        self.subject = subject
        self.chapter = chapter
        self.text = text
        self.hasImage = hasImage
        self.optionCount = optionCount
    }

    public static let textLimit = 240

    /// Arise's stems are authored HTML. Tags, entities and runs of whitespace all collapse
    /// so the stored text is what a human would read.
    public static func plainText(from question: Question) -> String {
        let source = question.plain ?? question.html ?? ""
        let stripped = source
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(stripped.prefix(textLimit))
    }

    public static func hasFigure(_ question: Question) -> Bool {
        if let images = question.images, !images.isEmpty { return true }
        return (question.html ?? "").localizedCaseInsensitiveContains("<img")
    }
}

// MARK: - Filters

public struct MedxQuestionFilters: Hashable, Sendable {
    public enum Status: String, CaseIterable, Identifiable, Sendable {
        case any, unattempted, attempted, wrong

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .any: return "Any"
            case .unattempted: return "Unattempted"
            case .attempted: return "Attempted"
            case .wrong: return "Got wrong"
            }
        }

        public var icon: String {
            switch self {
            case .any: return "circle.dashed"
            case .unattempted: return "circle"
            case .attempted: return "checkmark.circle"
            case .wrong: return "xmark.circle"
            }
        }
    }

    /// `nil` means every subject.
    public var subjectId: Int?
    public var imageBased = false
    public var bookmarkedOnly = false
    public var status: Status = .any

    public init(subjectId: Int? = nil, imageBased: Bool = false, bookmarkedOnly: Bool = false, status: Status = .any) {
        self.subjectId = subjectId
        self.imageBased = imageBased
        self.bookmarkedOnly = bookmarkedOnly
        self.status = status
    }

    public var isActive: Bool {
        subjectId != nil || imageBased || bookmarkedOnly || status != .any
    }

    public var activeCount: Int {
        var count = 0
        if subjectId != nil { count += 1 }
        if imageBased { count += 1 }
        if bookmarkedOnly { count += 1 }
        if status != .any { count += 1 }
        return count
    }
}

/// The three id sets the status and bookmark filters need, gathered once per search rather
/// than per candidate.
public struct MedxAnswerHistory: Sendable {
    public var attempted: Set<Int>
    public var wrong: Set<Int>
    public var bookmarked: Set<Int>

    public init(attempted: Set<Int> = [], wrong: Set<Int> = [], bookmarked: Set<Int> = []) {
        self.attempted = attempted
        self.wrong = wrong
        self.bookmarked = bookmarked
    }

    /// Built from the attempt history and the bookmark list.
    public init(attempts: [SittingAttempt], bookmarks: [BookmarkedQuestion]) {
        var seen: Set<Int> = []
        var missed: Set<Int> = []
        for attempt in attempts {
            for response in attempt.responses {
                guard response.chosenId != nil || response.timedOut == true else { continue }
                seen.insert(response.questionId)
                if !response.correct { missed.insert(response.questionId) }
            }
        }
        attempted = seen
        wrong = missed
        bookmarked = Set(bookmarks.map(\.question.id))
    }
}

// MARK: - Store

/// The on-device question index.
///
/// The bank's question bodies live in 1,211 Firestore module documents that are only fetched
/// when a module is opened, so searching all 17,890 questions means having pulled them down
/// once. That is an opt-in build with a progress bar rather than something the app does
/// behind the student's back — and it is resumable, because 1,211 fetches will not always
/// finish in one sitting. Search works on whatever is indexed so far.
@MainActor
public final class MedxQuestionIndexStore: ObservableObject {
    public static let shared = MedxQuestionIndexStore()

    @Published public private(set) var entries: [MedxIndexedQuestion] = []
    @Published public private(set) var indexedModuleIds: Set<String> = []
    @Published public private(set) var expectedQuestions = 0
    @Published public private(set) var expectedModules = 0
    @Published public private(set) var isBuilding = false
    @Published public private(set) var modulesDone = 0
    @Published public private(set) var lastBuiltAt: Date?
    @Published public private(set) var lastError: String?

    /// Folded copies of `entries[i].text`, so a keystroke is a plain substring scan rather
    /// than 17,890 locale-aware comparisons.
    private var foldedKeys: [String] = []
    private var buildTask: Task<Void, Never>?

    private static let concurrentFetches = 6
    private static let persistEvery = 40

    private let fileManager = FileManager.default
    private let directory: URL
    private var fileURL: URL { directory.appendingPathComponent("index.json") }

    private init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var folder = base.appendingPathComponent("QuestionIndex", isDirectory: true)
        if !fileManager.fileExists(atPath: folder.path) {
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        // Re-downloadable, so it has no business in an iCloud backup.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        directory = folder

        loadFromDisk()
    }

    // MARK: - Derived reads

    public var indexedCount: Int { entries.count }

    public var isEmpty: Bool { entries.isEmpty }

    /// How much of the bank is searchable, 0…1. Falls back to the module tally before the
    /// per-question expectation is known.
    public var coverage: Double {
        if expectedQuestions > 0 {
            return min(Double(entries.count) / Double(expectedQuestions), 1)
        }
        if expectedModules > 0 {
            return min(Double(indexedModuleIds.count) / Double(expectedModules), 1)
        }
        return entries.isEmpty ? 0 : 1
    }

    public var isComplete: Bool {
        expectedModules > 0 && indexedModuleIds.count >= expectedModules
    }

    public var coverageSummary: String {
        guard expectedQuestions > 0 else {
            return entries.isEmpty ? "Nothing indexed yet" : "\(entries.count.formatted()) questions indexed"
        }
        return "\(entries.count.formatted()) of \(expectedQuestions.formatted()) questions"
    }

    public var formattedSize: String {
        guard let size = try? fileManager.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber else {
            return "—"
        }
        return ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
    }

    // MARK: - Expectations

    /// Records how big a full index would be, so the progress UI has a denominator even
    /// before a build starts.
    public func noteExpectations(subjects: [QBankSubject]) {
        let modules = Self.moduleTargets(from: subjects)
        expectedModules = modules.count
        expectedQuestions = modules.reduce(0) { $0 + $1.questionCount }
    }

    // MARK: - Search

    public func search(
        _ rawQuery: String,
        filters: MedxQuestionFilters,
        history: MedxAnswerHistory,
        limit: Int = 300
    ) -> [MedxIndexedQuestion] {
        let tokens = Self.fold(rawQuery)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 2 }

        // With no text this is a pure filter browse, which is still useful ("show me every
        // image-based question in Pathology I got wrong").
        guard !tokens.isEmpty || filters.isActive else { return [] }

        var results: [MedxIndexedQuestion] = []
        results.reserveCapacity(min(limit, 128))

        for (offset, entry) in entries.enumerated() {
            guard matches(entry, filters: filters, history: history) else { continue }
            if !tokens.isEmpty {
                let key = offset < foldedKeys.count ? foldedKeys[offset] : Self.fold(entry.text)
                guard tokens.allSatisfy({ key.contains($0) }) else { continue }
            }
            results.append(entry)
            if results.count >= limit { break }
        }

        return results
    }

    private func matches(
        _ entry: MedxIndexedQuestion,
        filters: MedxQuestionFilters,
        history: MedxAnswerHistory
    ) -> Bool {
        if let subjectId = filters.subjectId, entry.subjectId != subjectId { return false }
        if filters.imageBased, !entry.hasImage { return false }
        if filters.bookmarkedOnly, !history.bookmarked.contains(entry.questionId) { return false }

        switch filters.status {
        case .any:
            return true
        case .attempted:
            return history.attempted.contains(entry.questionId)
        case .unattempted:
            return !history.attempted.contains(entry.questionId)
        case .wrong:
            return history.wrong.contains(entry.questionId)
        }
    }

    nonisolated private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    // MARK: - Build

    public func build(subjects: [QBankSubject]) {
        guard !isBuilding else { return }
        noteExpectations(subjects: subjects)

        let targets = Self.moduleTargets(from: subjects).filter { !indexedModuleIds.contains($0.moduleId) }
        guard !targets.isEmpty else {
            lastBuiltAt = Date()
            return
        }

        isBuilding = true
        lastError = nil
        modulesDone = 0

        buildTask = Task { [weak self] in
            await self?.runBuild(targets: targets)
        }
    }

    public func cancelBuild() {
        buildTask?.cancel()
        buildTask = nil
        isBuilding = false
        persist()
    }

    private func runBuild(targets: [MedxModuleTarget]) async {
        var sinceLastPersist = 0

        for chunkStart in stride(from: 0, to: targets.count, by: Self.concurrentFetches) {
            if Task.isCancelled { break }

            let chunk = Array(targets[chunkStart..<min(chunkStart + Self.concurrentFetches, targets.count)])

            // Refreshed per chunk rather than once for the whole build: 1,211 fetches can
            // easily outlive a one-hour ID token.
            guard let token = try? await AuthService.shared.getValidIdToken() else {
                lastError = "Sign-in expired. Try again."
                break
            }

            // A task group yields in completion order, so each child carries its module id
            // back rather than the results being zipped against the chunk by position.
            let harvested = await withTaskGroup(
                of: MedxHarvest.self,
                returning: [MedxHarvest].self
            ) { group in
                for target in chunk {
                    group.addTask { await Self.harvest(target, idToken: token) }
                }
                var collected: [MedxHarvest] = []
                for await batch in group { collected.append(batch) }
                return collected
            }

            for result in harvested {
                entries.append(contentsOf: result.questions)
                foldedKeys.append(contentsOf: result.questions.map { Self.fold($0.text) })
                // A module whose document has no decodable questions is still marked seen,
                // or every rebuild would retry the same broken document forever.
                indexedModuleIds.insert(result.moduleId)
            }

            modulesDone += chunk.count
            sinceLastPersist += chunk.count
            if sinceLastPersist >= Self.persistEvery {
                sinceLastPersist = 0
                persist()
            }
        }

        isBuilding = false
        buildTask = nil
        lastBuiltAt = Date()
        persist()
    }

    /// Fetching through `FirestoreService.fetchQBankModule` on purpose: it warms the same
    /// module cache the runner reads, so building the index also makes those modules
    /// playable offline.
    nonisolated private static func harvest(_ target: MedxModuleTarget, idToken: String) async -> MedxHarvest {
        guard let module = try? await FirestoreService.shared.fetchQBankModule(
            moduleId: target.moduleId,
            idToken: idToken
        ) else {
            return MedxHarvest(moduleId: target.moduleId, questions: [])
        }

        let questions = (module.questions ?? []).map { question in
            MedxIndexedQuestion(
                questionId: question.id,
                moduleId: target.moduleId,
                moduleName: target.moduleName,
                subjectId: target.subjectId,
                subject: target.subject,
                chapter: target.chapter,
                text: MedxIndexedQuestion.plainText(from: question),
                hasImage: MedxIndexedQuestion.hasFigure(question),
                optionCount: question.options.count
            )
        }
        return MedxHarvest(moduleId: target.moduleId, questions: questions)
    }

    nonisolated private static func moduleTargets(from subjects: [QBankSubject]) -> [MedxModuleTarget] {
        var targets: [MedxModuleTarget] = []
        for subject in subjects {
            for chapter in subject.chapters ?? [] {
                for module in chapter.modules ?? [] {
                    targets.append(
                        MedxModuleTarget(
                            moduleId: module.id,
                            moduleName: module.name,
                            subjectId: subject.subjectId,
                            subject: subject.name,
                            chapter: chapter.name,
                            questionCount: module.questionCount
                        )
                    )
                }
            }
        }
        return targets
    }

    // MARK: - Turning results back into a sitting

    /// Every indexed question that passes the filters, optionally narrowed to a set of
    /// subjects. The custom-module builder needs a *pool* to sample from rather than a text
    /// match, which is why this bypasses the "query or filter required" rule in `search`.
    public func pool(
        subjectIds: Set<Int>,
        filters: MedxQuestionFilters,
        history: MedxAnswerHistory
    ) -> [MedxIndexedQuestion] {
        var scoped = filters
        scoped.subjectId = nil

        return entries.filter { entry in
            guard subjectIds.isEmpty || subjectIds.contains(entry.subjectId) else { return false }
            return matches(entry, filters: scoped, history: history)
        }
    }

    /// Fetches the real `Question` values behind a set of index entries.
    ///
    /// Grouped by module so each Firestore document is read once however many of its
    /// questions matched, and ordered by first appearance so the sitting follows the order
    /// the student was looking at.
    public func questions(for entries: [MedxIndexedQuestion], limit: Int) async -> [Question] {
        guard limit > 0, !entries.isEmpty else { return [] }
        guard let token = try? await AuthService.shared.getValidIdToken() else { return [] }

        var wanted: [String: Set<Int>] = [:]
        var moduleOrder: [String] = []
        for entry in entries.prefix(limit * 2) {
            if wanted[entry.moduleId] == nil { moduleOrder.append(entry.moduleId) }
            wanted[entry.moduleId, default: []].insert(entry.questionId)
        }

        var collected: [Question] = []
        for moduleId in moduleOrder {
            guard let module = try? await FirestoreService.shared.fetchQBankModule(
                moduleId: moduleId,
                idToken: token
            ) else { continue }

            let ids = wanted[moduleId] ?? []
            collected.append(contentsOf: (module.questions ?? []).filter { ids.contains($0.id) })
            if collected.count >= limit { break }
        }

        return Array(collected.prefix(limit))
    }

    // MARK: - Persistence

    public func wipe() {

        cancelBuild()
        entries = []
        foldedKeys = []
        indexedModuleIds = []
        modulesDone = 0
        lastBuiltAt = nil
        lastError = nil
        try? fileManager.removeItem(at: fileURL)
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(MedxIndexFile.self, from: data) else { return }
        entries = payload.entries
        indexedModuleIds = Set(payload.moduleIds)
        expectedModules = payload.expectedModules
        expectedQuestions = payload.expectedQuestions
        lastBuiltAt = payload.builtAt
        foldedKeys = payload.entries.map { Self.fold($0.text) }
    }

    /// Encoded off the main actor: the finished file is several megabytes and re-encoding it
    /// on the main thread every forty modules would be a visible stutter.
    private func persist() {
        let payload = MedxIndexFile(
            entries: entries,
            moduleIds: Array(indexedModuleIds),
            expectedModules: expectedModules,
            expectedQuestions: expectedQuestions,
            builtAt: lastBuiltAt ?? Date()
        )
        let destination = fileURL
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(payload) else { return }
            try? data.write(to: destination, options: .atomic)
        }
    }
}

// MARK: - Build helpers

struct MedxModuleTarget: Sendable {
    let moduleId: String
    let moduleName: String
    let subjectId: Int
    let subject: String
    let chapter: String
    let questionCount: Int
}

struct MedxHarvest: Sendable {
    let moduleId: String
    let questions: [MedxIndexedQuestion]
}

struct MedxIndexFile: Codable, Sendable {
    let entries: [MedxIndexedQuestion]
    let moduleIds: [String]
    let expectedModules: Int
    let expectedQuestions: Int
    let builtAt: Date
}
