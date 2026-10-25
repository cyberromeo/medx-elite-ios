import Foundation

/// An unfinished sitting, kept on the device so leaving is not losing.
///
/// Keyed by the *profile* and the paper, fingerprinted by the set of question ids that were
/// loaded, and carrying the order they were sat in. Three things that used to go wrong:
///
/// - the key had no uid, so one person's half-finished paper was offered to the other, and
///   "Start Over" deleted it;
/// - the fingerprint folded ids in order, so a shuffled custom paper never matched its own
///   save and "Save and Leave" quietly threw the progress away;
/// - a sitting saved on the block handover screen carried the closed block's leftover seconds,
///   so resuming opened the next block with a clock already at zero.
///
/// Clocks are saved as seconds left on the active block, with `awaitingHandover` set when the
/// next block has not started yet.
public struct MedxSittingSnapshot: Codable, Equatable, Sendable {
    public let fingerprint: String
    /// Question ids in the order they were sat, so a shuffled paper resumes in its own order.
    public let order: [Int]
    public let mode: String
    public let currentIndex: Int
    public let furthestIndex: Int
    public let responses: [QuestionResponse]
    public let revealed: [Int]
    public let remainingSeconds: Int
    public let sectionIndex: Int
    public let sectionLog: [MedxAttemptSection]
    public let awaitingHandover: Bool
    public let elapsedSeconds: Int
    public let savedAt: Date

    public init(
        fingerprint: String,
        order: [Int],
        mode: String,
        currentIndex: Int,
        furthestIndex: Int,
        responses: [QuestionResponse],
        revealed: [Int],
        remainingSeconds: Int,
        sectionIndex: Int,
        sectionLog: [MedxAttemptSection],
        awaitingHandover: Bool,
        elapsedSeconds: Int,
        savedAt: Date
    ) {
        self.fingerprint = fingerprint
        self.order = order
        self.mode = mode
        self.currentIndex = currentIndex
        self.furthestIndex = furthestIndex
        self.responses = responses
        self.revealed = revealed
        self.remainingSeconds = remainingSeconds
        self.sectionIndex = sectionIndex
        self.sectionLog = sectionLog
        self.awaitingHandover = awaitingHandover
        self.elapsedSeconds = elapsedSeconds
        self.savedAt = savedAt
    }

    private static let prefix = "medx.sitting."

    private static func key(uid: String, kind: String, id: String) -> String {
        "\(prefix)\(uid).\(kind).\(id)"
    }

    /// Order-independent: the count and an FNV fold over the *sorted* ids.
    public static func fingerprint(_ questions: [Question]) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for id in questions.map(\.id).sorted() {
            hash = (hash ^ UInt64(bitPattern: Int64(id))) &* 1_099_511_628_211
        }
        return "\(questions.count)-\(String(hash, radix: 16))"
    }

    public static func load(uid: String, kind: String, id: String) -> MedxSittingSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key(uid: uid, kind: kind, id: id)) else { return nil }
        return try? JSONDecoder().decode(MedxSittingSnapshot.self, from: data)
    }

    public func save(uid: String, kind: String, id: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key(uid: uid, kind: kind, id: id))
    }

    public static func clear(uid: String, kind: String, id: String) {
        UserDefaults.standard.removeObject(forKey: key(uid: uid, kind: kind, id: id))
    }

    /// Drops this profile's saved sittings older than `days`. Quick sittings and searches get a
    /// stable id per day, so the ones that were abandoned would otherwise pile up for good.
    public static func pruneStale(uid: String, olderThan days: Int = 14) {
        let defaults = UserDefaults.standard
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let mine = "\(prefix)\(uid)."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(mine) {
            guard let data = defaults.data(forKey: key),
                  let snapshot = try? JSONDecoder().decode(MedxSittingSnapshot.self, from: data)
            else {
                defaults.removeObject(forKey: key)
                continue
            }
            if snapshot.savedAt < cutoff {
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// "Question 14 of 50 · 12 answered · 31:20 left on the clock."
    public func summary(total: Int) -> String {
        let answered = responses.filter { $0.chosenId != nil }.count
        return "Question \(currentIndex + 1) of \(total) · \(answered) answered · \(MedxFormat.clock(remainingSeconds)) left on the clock."
    }
}
