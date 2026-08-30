import Foundation

// MARK: - Custom modules
//
// A saved selection of QBank modules that runs as one paper.
//
// The unit is a *module*, not an individual question: the two banks are already cut into
// 2,171 chapter-sized modules, so "Anatomy upper limb + Ortho fractures, shuffled, capped at
// 40" is the paper people actually want to build, and it needs six taps instead of forty.
//
// The document shape is field-for-field the PWA's (`src/lib/custom.js`), because the list is
// one shared Firestore collection: a paper built on a phone in the PWA opens here, and one
// built here opens there.

/// One picked module inside a saved selection.
///
/// The chapter and subject names are carried alongside the id so a paper can still say where
/// each question came from after the bank has been re-seeded and the module ids have moved.
/// `bank` is carried for the same reason — a mixed paper should still be able to name the bank
/// a question is from once the id has stopped resolving.
public struct MedxModuleSource: Identifiable, Hashable, Codable, Sendable {
    public let moduleId: String
    public let name: String
    public let chapter: String
    public let subject: String
    public let bank: MedxBank
    public let questionCount: Int

    public var id: String { moduleId }

    enum CodingKeys: String, CodingKey {
        case type, moduleId, name, chapter, subject, bank, questionCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        moduleId = (try? container.decodeIfPresent(String.self, forKey: .moduleId)) ?? ""
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Module"
        chapter = (try? container.decodeIfPresent(String.self, forKey: .chapter)) ?? ""
        subject = (try? container.decodeIfPresent(String.self, forKey: .subject)) ?? ""
        // The stored `bank` is trusted where present, but the id is the fallback and the
        // arbiter: a source written before the field existed still resolves correctly.
        if let raw = try? container.decodeIfPresent(String.self, forKey: .bank),
           let parsed = MedxBank(rawValue: raw) {
            bank = parsed
        } else {
            bank = MedxBank.of(moduleId)
        }
        questionCount = (try? container.decodeIfPresent(Int.self, forKey: .questionCount)) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // The PWA writes `type: 'module'`; kept so a row round-trips unchanged rather than
        // losing a field every time the other client saves it.
        try container.encode("module", forKey: .type)
        try container.encode(moduleId, forKey: .moduleId)
        try container.encode(name, forKey: .name)
        try container.encode(chapter, forKey: .chapter)
        try container.encode(subject, forKey: .subject)
        try container.encode(bank.rawValue, forKey: .bank)
        try container.encode(questionCount, forKey: .questionCount)
    }

    public init(module: QBankModuleSummary, chapter: MedxBankChapter, subject: MedxBankSubject) {
        self.moduleId = module.id
        self.name = module.name
        self.chapter = chapter.name
        self.subject = subject.name
        self.bank = subject.bank
        self.questionCount = module.questionCount
    }
}

/// A saved paper.
///
/// `uid` records whoever *created* it and is deliberately never re-stamped when the other one
/// edits — the author pill on the card would stop telling the truth. `synced` is this device's
/// bookkeeping, never part of the document; see `MedxCustomModuleStore.reconcile` for the one
/// thing it is load-bearing for.
public struct MedxCustomModule: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var uid: String
    public var name: String
    public var note: String
    public var sources: [MedxModuleSource]
    public var shuffle: Bool
    /// `nil` means every question in the selection.
    public var limit: Int?
    public var createdAt: String
    public var updatedAt: String
    /// `nil` = never asked, `true` = this device has seen it land, `false` = local only.
    public var synced: Bool?

    public var questionCount: Int {
        sources.reduce(0) { $0 + $1.questionCount }
    }

    /// What a run will actually ask, once the cap is applied.
    public var effectiveCount: Int {
        guard let limit, limit > 0 else { return questionCount }
        return min(questionCount, limit)
    }

    public var updatedDate: Date? {
        ISO8601DateFormatter().date(from: updatedAt)
    }

    public var author: Profile? { Profile.byUid(uid) }

    enum CodingKeys: String, CodingKey {
        case id, uid, name, note, sources, shuffle, limit, createdAt, updatedAt, synced
    }

    /// Lenient per field, like every other model here: a paper written by an older build with
    /// a field missing must not vanish from a shared list.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? MedxCustomModule.newId()
        uid = (try? container.decodeIfPresent(String.self, forKey: .uid)) ?? ""
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        note = (try? container.decodeIfPresent(String.self, forKey: .note)) ?? ""
        sources = container.decodeLenientArray(MedxModuleSource.self, forKey: .sources) ?? []
        shuffle = (try? container.decodeIfPresent(Bool.self, forKey: .shuffle)) ?? true
        // A stored `0` means "all", the same as absent — that is what the cap segmented writes.
        let storedLimit = try? container.decodeIfPresent(Int.self, forKey: .limit)
        limit = (storedLimit ?? 0) > 0 ? storedLimit : nil
        let stamp = ISO8601DateFormatter().string(from: Date())
        createdAt = (try? container.decodeIfPresent(String.self, forKey: .createdAt)) ?? stamp
        updatedAt = (try? container.decodeIfPresent(String.self, forKey: .updatedAt)) ?? createdAt
        synced = try? container.decodeIfPresent(Bool.self, forKey: .synced)
    }

    public init(
        id: String,
        uid: String,
        name: String,
        note: String,
        sources: [MedxModuleSource],
        shuffle: Bool,
        limit: Int?,
        createdAt: String,
        updatedAt: String,
        synced: Bool?
    ) {
        self.id = id
        self.uid = uid
        self.name = name
        self.note = note
        self.sources = sources
        self.shuffle = shuffle
        self.limit = limit
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.synced = synced
    }

    /// Short, sortable, and readable in a URL — the same shape the PWA generates, so ids from
    /// either client sort together.
    public static func newId() -> String {
        let stamp = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let salt = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(4)).lowercased()
        return "c\(stamp)\(salt)"
    }

    public static func blank(uid: String) -> MedxCustomModule {
        let now = ISO8601DateFormatter().string(from: Date())
        return MedxCustomModule(
            id: newId(),
            uid: uid,
            name: "",
            note: "",
            sources: [],
            shuffle: true,
            limit: nil,
            createdAt: now,
            updatedAt: now,
            synced: nil
        )
    }
}

// MARK: - The merge rule

/// The one decision that can lose somebody's papers, kept on its own and free of Firestore.
public enum MedxCustomModuleRules {
    /// Newest first. `updatedAt` is an ISO-8601 string, so comparing text compares dates.
    public static func byNewest(_ a: MedxCustomModule, _ b: MedxCustomModule) -> Bool {
        a.updatedAt > b.updatedAt
    }

    /// The shared list, out of what Firestore returned and what this device had.
    ///
    /// A local row the mirror does not have means one of two *opposite* things, and getting
    /// them the wrong way round is the only way this feature loses data:
    ///
    /// - it never reached Firestore — a failed save, or it was built offline. Keep it, and mark
    ///   it so the screen can say it is on this device only.
    /// - it *was* mirrored and is gone now, which means the other one deleted it. Drop it, or
    ///   every shared delete would undo itself on the other device.
    ///
    /// The persisted `synced` flag is the only thing that separates those, and it is carried
    /// through rather than recomputed: a row that was mirrored keeps saying so even while it is
    /// absent from an inconclusive read.
    ///
    /// `authoritative` is false when the read could not prove a deletion — a cached answer while
    /// offline, chiefly. Nothing is purged on one of those, so a plane journey cannot empty the
    /// list.
    public static func reconcile(
        remote: [MedxCustomModule],
        local: [MedxCustomModule],
        authoritative: Bool
    ) -> [MedxCustomModule] {
        let seen = Set(remote.map(\.id))
        let kept = local.filter { row in
            if seen.contains(row.id) { return false }        // the mirror wins
            if authoritative, row.synced == true { return false } // deleted by the other one
            return true
        }

        var merged = remote.map { row -> MedxCustomModule in
            var copy = row
            copy.synced = true
            return copy
        }
        merged.append(contentsOf: kept.map { row -> MedxCustomModule in
            var copy = row
            copy.synced = row.synced == true
            return copy
        })
        return merged.sorted(by: byNewest)
    }
}
