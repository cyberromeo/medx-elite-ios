import Foundation

// MARK: - Transport
//
// Everything the duel does to Firestore, behind one protocol.
//
// The protocol exists because there are two ways to get a room's three documents onto a screen
// within a second, and the choice is a deployment concern rather than a game one: the Firebase
// SDK's snapshot listeners, or a poll. `MedxDuelRoom` never learns which it is talking to.
//
// Note the shape: **one** `watchRoom` rather than the PWA's separate game and player streams.
// That is not a simplification for its own sake — the game document and both player documents
// have deterministic names, so a poll fetches all three in a single `batchGet`, and splitting
// them into two subscriptions would triple the requests to deliver the same three documents.

/// A live subscription. Cancelling is idempotent.
public final class MedxDuelSubscription {
    private var onCancel: (() -> Void)?

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    public func cancel() {
        onCancel?()
        onCancel = nil
    }

    deinit { onCancel?() }
}

/// The whole room, as one delivery.
public struct MedxDuelRoomSnapshot: Sendable {
    /// `nil` once a read has proved the game is gone; absent until the first delivery.
    public let game: MedxDuelGame?
    public let players: [MedxDuelPlayer]
    /// Set when the read was refused, which on this backend usually means the rules will not
    /// take the duel collections at all.
    public let failure: String?

    public init(game: MedxDuelGame?, players: [MedxDuelPlayer], failure: String? = nil) {
        self.game = game
        self.players = players
        self.failure = failure
    }
}

@MainActor
public protocol MedxDuelTransport: AnyObject {
    /// Whether the last read or write was accepted. `nil` before anything has been tried.
    var remoteWorks: Bool? { get }

    /// What to call this in Settings ▸ Diagnostics.
    ///
    /// Diagnostics used to derive the line from `MedxFirebaseBridge.isReady`, which is not the same
    /// claim: readiness says the SDK *could* be used, and this says what the open stream actually
    /// is. Those two disagreed for the whole of the transport-latch bug — the bridge could report
    /// "Live listeners" while every duel in the process was polling.
    var transportName: String { get }

    func watchRoom(
        gameId: String,
        onChange: @escaping (MedxDuelRoomSnapshot) -> Void
    ) -> MedxDuelSubscription

    func watchOpenLobbies(
        onChange: @escaping ([MedxDuelGame]) -> Void
    ) -> MedxDuelSubscription

    /// Tells the transport how urgent the next read is. A no-op for a listener-backed transport;
    /// for the poller it is the difference between one request every three seconds and one a
    /// second.
    func setUrgency(_ phase: MedxDuelPhase)

    /// Reads the deck once. It is immutable after the deal, so it is never watched.
    func loadDeck(gameId: String) async throws -> [MedxDuelQuestion]

    func listMyDuels(uid: String) async throws -> [MedxDuelGame]

    func createGame(
        hostUid: String,
        hostProfile: String,
        source: MedxDuelSource,
        deck: [MedxDuelQuestion],
        parts: [[MedxDuelQuestion]]
    ) async throws -> String

    func joinGame(gameId: String, uid: String, profile: String) async throws
    func startGame(gameId: String, guestUid: String, guestProfile: String) async throws
    func advance(gameId: String, row: MedxDuelLogRow, nextIndex: Int) async throws
    func finishGame(gameId: String, row: MedxDuelLogRow, scores: [String: MedxDuelScore]) async throws
    func abandonGame(gameId: String) async throws
    func submitAnswer(gameId: String, uid: String, round: MedxDuelRound) async throws
    func voteNext(gameId: String, uid: String, qIndex: Int) async throws
    func leaveGame(gameId: String, uid: String) async throws
}

// MARK: - Collections

enum MedxDuelPath {
    static let games = "medx_duels"
    static let players = "medx_duel_players"
    /// The deck is a subcollection, addressed as one path segment by the REST client.
    static func deck(_ gameId: String) -> String { "medx_duels/\(gameId)/deck" }
}

// MARK: - Codec
//
// Firestore document ↔ model. Hand-written rather than `Codable` for one reason that matters:
// `askedAt` is epoch milliseconds and has to survive as a `Double` through a JSON round trip that
// Firestore may hand back as either an integer or a double string, and the log is an array of
// nested maps that has to encode to exactly the shape the PWA writes.

enum MedxDuelCodec {
    // MARK: Reading

    static func game(id: String, fields: [String: Any]) -> MedxDuelGame? {
        func string(_ key: String) -> String? { fields[key] as? String }
        func int(_ key: String) -> Int {
            if let value = fields[key] as? Int { return value }
            if let value = fields[key] as? Double { return Int(value) }
            if let value = fields[key] as? String { return Int(value) ?? 0 }
            return 0
        }

        guard let hostUid = string("uid"), !hostUid.isEmpty else { return nil }

        var askedAt: Double?
        if let value = fields["askedAt"] as? Double { askedAt = value }
        else if let value = fields["askedAt"] as? Int { askedAt = Double(value) }
        else if let value = fields["askedAt"] as? String { askedAt = Double(value) }

        var source: MedxDuelSource?
        if let raw = fields["source"] as? [String: Any] {
            source = MedxDuelSource(
                kind: (raw["kind"] as? String) ?? "series",
                id: (raw["id"] as? String) ?? "",
                name: (raw["name"] as? String) ?? "Faceoff",
                subject: (raw["subject"] as? String) ?? ""
            )
        }

        let log = (fields["log"] as? [Any] ?? []).compactMap { entry -> MedxDuelLogRow? in
            guard let map = entry as? [String: Any] else { return nil }
            return logRow(from: map)
        }

        return MedxDuelGame(
            id: id,
            hostUid: hostUid,
            hostProfile: string("hostProfile") ?? "",
            guestUid: string("guestUid"),
            guestProfile: string("guestProfile"),
            status: MedxDuelStatus(rawValue: string("status") ?? "") ?? .lobby,
            source: source,
            total: int("total"),
            deckParts: int("deckParts"),
            qIndex: int("qIndex"),
            askedAt: askedAt,
            log: log.sorted { $0.qIndex < $1.qIndex },
            createdAt: string("createdAt") ?? "",
            updatedAt: string("updatedAt") ?? "",
            finishedAt: string("finishedAt")
        )
    }

    static func player(fields: [String: Any]) -> MedxDuelPlayer? {
        guard let uid = fields["uid"] as? String, !uid.isEmpty else { return nil }

        var round: MedxDuelRound?
        if let raw = fields["round"] as? [String: Any] {
            round = MedxDuelRound(
                qIndex: intValue(raw["qIndex"]) ?? -1,
                optionId: intValue(raw["optionId"]),
                remaining: intValue(raw["remaining"]) ?? 0,
                correct: (raw["correct"] as? Bool) ?? false,
                timedOut: (raw["timedOut"] as? Bool) ?? false
            )
        }

        return MedxDuelPlayer(
            uid: uid,
            gameId: (fields["gameId"] as? String) ?? "",
            profile: (fields["profile"] as? String) ?? "",
            left: (fields["left"] as? Bool) ?? false,
            round: round,
            next: intValue(fields["next"])
        )
    }

    static func intValue(_ any: Any?) -> Int? {
        if let value = any as? Int { return value }
        if let value = any as? Double { return Int(value) }
        if let value = any as? String { return Int(value) }
        return nil
    }

    static func logRow(from map: [String: Any]) -> MedxDuelLogRow? {
        var answers: [String: MedxDuelAnswerRow] = [:]
        for (uid, raw) in (map["answers"] as? [String: Any] ?? [:]) {
            guard let entry = raw as? [String: Any] else { continue }
            answers[uid] = MedxDuelAnswerRow(
                optionId: intValue(entry["optionId"]),
                correct: (entry["correct"] as? Bool) ?? false,
                timedOut: (entry["timedOut"] as? Bool) ?? false,
                remaining: intValue(entry["remaining"]),
                points: intValue(entry["points"]) ?? 0
            )
        }
        return MedxDuelLogRow(
            qIndex: intValue(map["qIndex"]) ?? 0,
            questionId: intValue(map["questionId"]),
            first: map["first"] as? String,
            winner: map["winner"] as? String,
            answers: answers
        )
    }

    // MARK: Writing
    //
    // Firestore rejects `undefined` and the REST converter drops anything it cannot map, so every
    // optional is coalesced explicitly rather than left out — a missing `guestUid` has to be a
    // written null, not an absent key, or the guest's join would not clear it.

    static func stamp() -> String { ISO8601DateFormatter().string(from: Date()) }

    static func nowMillis() -> Double { Date().timeIntervalSince1970 * 1000 }

    static func sourceFields(_ source: MedxDuelSource) -> [String: Any] {
        [
            "kind": source.kind,
            "id": source.id,
            "name": source.name,
            "subject": source.subject
        ]
    }

    static func logRowFields(_ row: MedxDuelLogRow) -> [String: Any] {
        var answers: [String: Any] = [:]
        for (uid, answer) in row.answers {
            var entry: [String: Any] = [
                "correct": answer.correct,
                "timedOut": answer.timedOut,
                "points": answer.points
            ]
            if let optionId = answer.optionId { entry["optionId"] = optionId }
            if let remaining = answer.remaining { entry["remaining"] = remaining }
            answers[uid] = entry
        }

        var out: [String: Any] = [
            "qIndex": row.qIndex,
            "answers": answers
        ]
        if let questionId = row.questionId { out["questionId"] = questionId }
        if let first = row.first { out["first"] = first }
        if let winner = row.winner { out["winner"] = winner }
        return out
    }

    static func scoreFields(_ scores: [String: MedxDuelScore]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (uid, score) in scores {
            var entry: [String: Any] = [
                "points": score.points,
                "correct": score.correct,
                "answered": score.answered,
                "firsts": score.firsts,
                "rounds": score.rounds
            ]
            if let fastest = score.fastest { entry["fastest"] = fastest }
            out[uid] = entry
        }
        return out
    }

    static func roundFields(_ round: MedxDuelRound) -> [String: Any] {
        var out: [String: Any] = [
            "qIndex": round.qIndex,
            "remaining": round.remaining,
            "correct": round.correct,
            "timedOut": round.timedOut,
            "at": nowMillis()
        ]
        if let optionId = round.optionId { out["optionId"] = optionId }
        return out
    }

    static func blankPlayer(gameId: String, uid: String, profile: String) -> [String: Any] {
        [
            "uid": uid,
            "gameId": gameId,
            "profile": profile,
            "left": false,
            "joinedAt": stamp()
        ]
    }

    static func deckFields(part: Int, questions: [MedxDuelQuestion]) -> [String: Any] {
        let encoded = questions.compactMap { question -> [String: Any]? in
            guard let data = try? JSONEncoder().encode(question),
                  let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return map
        }
        return ["part": part, "questions": encoded]
    }

    static func questions(from fields: [String: Any]) -> [MedxDuelQuestion] {
        guard let raw = fields["questions"] as? [Any] else { return [] }
        let decoder = JSONDecoder()
        return raw.compactMap { entry in
            guard let map = entry as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: map)
            else { return nil }
            return try? decoder.decode(MedxDuelQuestion.self, from: data)
        }
    }
}
