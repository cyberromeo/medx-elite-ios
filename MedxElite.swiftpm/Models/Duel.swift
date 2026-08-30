import Foundation

// MARK: - Faceoff documents
//
// Three documents make a duel, and the split between them is not stylistic — it is what the
// deployed rules on `medx-e9acd` will take:
//
//   medx_duels/{gameId}              the host owns it, both read it
//   medx_duels/{gameId}/deck/{part}  the deck, written once at the deal, immutable after
//   medx_duel_players/{gameId}__{uid}  each player owns exactly one, and it is the only place
//                                      they may write a move
//
// Nobody writes anybody else's document. That rule is why joining is the guest writing their own
// player row and the *host* is what flips the game to live, and why a client that runs out of
// clock writes its own timeout rather than having it written for it.

public enum MedxDuelStatus: String, Codable, Sendable {
    case lobby, live, done, abandoned
}

/// What a duel is being played on.
public struct MedxDuelSource: Hashable, Codable, Sendable {
    /// `series` or `custom`.
    public let kind: String
    public let id: String
    public let name: String
    public let subject: String

    public init(kind: String, id: String, name: String, subject: String) {
        self.kind = kind
        self.id = id
        self.name = name
        self.subject = subject
    }
}

/// One side's answer to the question currently open.
///
/// A player document only ever holds the *current* round, so every read of it is guarded on the
/// question number: a stale `round` left over from question 6 must not read as an answer to
/// question 7.
public struct MedxDuelRound: Hashable, Codable, Sendable {
    public let qIndex: Int
    public let optionId: Int?
    /// Seconds still on the clock at the tap. Captured then and never recomputed — the payout
    /// has to be the digit the player was looking at.
    public let remaining: Int
    public let correct: Bool
    public let timedOut: Bool

    public init(qIndex: Int, optionId: Int?, remaining: Int, correct: Bool, timedOut: Bool = false) {
        self.qIndex = qIndex
        self.optionId = optionId
        self.remaining = max(0, remaining)
        self.correct = correct
        self.timedOut = timedOut
    }

    /// Did this side actually pick something, as opposed to running out of clock?
    public var attempted: Bool { !timedOut && optionId != nil }

    /// A timed-out answer, for the side that never wrote one.
    public static func timedOut(qIndex: Int) -> MedxDuelRound {
        MedxDuelRound(qIndex: qIndex, optionId: nil, remaining: 0, correct: false, timedOut: true)
    }
}

public struct MedxDuelPlayer: Identifiable, Hashable, Codable, Sendable {
    public let uid: String
    public let gameId: String
    /// `Profile.id` — "graveyard" or "quantumguy".
    public let profile: String
    public let left: Bool
    public let round: MedxDuelRound?
    /// The question number this side has voted to move past. Both votes open the next round.
    public let next: Int?

    public var id: String { uid }

    public init(uid: String, gameId: String, profile: String, left: Bool = false, round: MedxDuelRound? = nil, next: Int? = nil) {
        self.uid = uid
        self.gameId = gameId
        self.profile = profile
        self.left = left
        self.round = round
        self.next = next
    }

    /// Their answer to a *specific* question, or nil.
    public func answer(to qIndex: Int) -> MedxDuelRound? {
        guard let round, round.qIndex == qIndex else { return nil }
        return round
    }

    public func hasVoted(past qIndex: Int) -> Bool { next == qIndex }

    public var displayProfile: Profile? { Profile.byId(profile) ?? Profile.byUid(uid) }

    /// The document id, which is deterministic so it can be fetched by name rather than queried
    /// for — that is what lets the REST transport read the whole room in one `batchGet`.
    public static func docId(gameId: String, uid: String) -> String { "\(gameId)__\(uid)" }
}

/// One round, scored, appended to the game's log.
public struct MedxDuelLogRow: Hashable, Codable, Sendable {
    public let qIndex: Int
    public let questionId: Int?
    /// Whoever had more of the clock left. Carries no points; it is a line on the reveal.
    public let first: String?
    /// Whoever scored more on this question, or nil for a tie.
    public let winner: String?
    /// Keyed by uid.
    public let answers: [String: MedxDuelAnswerRow]

    public init(qIndex: Int, questionId: Int?, first: String?, winner: String?, answers: [String: MedxDuelAnswerRow]) {
        self.qIndex = qIndex
        self.questionId = questionId
        self.first = first
        self.winner = winner
        self.answers = answers
    }
}

public struct MedxDuelAnswerRow: Hashable, Codable, Sendable {
    public let optionId: Int?
    public let correct: Bool
    public let timedOut: Bool
    /// `nil` when the side never picked, which is what separates "slow" from "silent".
    public let remaining: Int?
    public let points: Int

    public init(optionId: Int?, correct: Bool, timedOut: Bool, remaining: Int?, points: Int) {
        self.optionId = optionId
        self.correct = correct
        self.timedOut = timedOut
        self.remaining = remaining
        self.points = points
    }
}

/// One side's game, folded from the log.
public struct MedxDuelScore: Hashable, Codable, Sendable {
    public var points = 0
    public var correct = 0
    public var answered = 0
    public var firsts = 0
    public var rounds = 0
    /// Seconds *taken* on a question that was got right — the interesting number, and not the
    /// same as the largest `remaining`, because a fast wrong answer is nobody's best.
    public var fastest: Int?

    public init() {}
}

/// A question cut down to what a duel round actually renders.
///
/// The key is hoisted to `correctIds` because the backend is inconsistent about where it lives —
/// some questions carry `correctIds`, others only an `options[].correct` flag — and normalising
/// once at the deal means neither client has to know that. Unkeyed questions never reach the deck
/// at all: a duel question that cannot be scored has no business in a scored game.
public struct MedxDuelQuestion: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let html: String
    public let plain: String
    public let options: [QuestionOption]
    public let correctIds: [Int]
    public let explanation: String
    public let reference: String

    public init(question: Question) {
        self.id = question.id
        self.html = question.html ?? question.plain ?? ""
        self.plain = question.plain ?? ""
        self.options = question.options.map {
            QuestionOption(id: $0.id, label: $0.label.isEmpty ? "?" : $0.label, text: $0.text)
        }
        self.correctIds = MedxDuelQuestion.correctIds(of: question)
        self.explanation = question.explanation ?? ""
        self.reference = question.reference ?? ""
    }

    /// The API is inconsistent about where the key lives — some questions carry `correctIds`,
    /// others only an `options[].correct` flag, and an unattempted paper has neither. All three
    /// are handled, and an empty result is what makes a question undealable.
    public static func correctIds(of question: Question) -> [Int] {
        if !question.correctIds.isEmpty { return question.correctIds }
        return question.options.filter { $0.correct == true }.map(\.id)
    }

    /// Back to a runner question, so a duel's deck can be reviewed with the same views.
    public var asQuestion: Question {
        Question(
            id: id,
            html: html.isEmpty ? nil : html,
            plain: plain.isEmpty ? nil : plain,
            options: options,
            correctIds: correctIds,
            explanation: explanation.isEmpty ? nil : explanation,
            reference: reference.isEmpty ? nil : reference
        )
    }
}

/// The game document.
public struct MedxDuelGame: Identifiable, Hashable, Sendable {
    public let id: String
    /// The host's uid. The field is `uid` in Firestore, matching the PWA.
    public let hostUid: String
    public let hostProfile: String
    public let guestUid: String?
    public let guestProfile: String?
    public let status: MedxDuelStatus
    public let source: MedxDuelSource?
    public let total: Int
    public let deckParts: Int
    public let qIndex: Int
    /// Epoch milliseconds, always set one arming window into the future — a future `askedAt`
    /// *is* the 3·2·1, and the same value is the start of the minute, which is what makes
    /// opening a round a single write.
    public let askedAt: Double?
    public let log: [MedxDuelLogRow]
    public let createdAt: String
    public let updatedAt: String
    public let finishedAt: String?

    public var uids: [String] { [hostUid, guestUid].compactMap { $0 } }

    public func isHost(_ uid: String?) -> Bool { uid != nil && uid == hostUid }

    public var createdDate: Date? { ISO8601DateFormatter().date(from: createdAt) }
    public var finishedDate: Date? { finishedAt.flatMap { ISO8601DateFormatter().date(from: $0) } }

    public init(
        id: String,
        hostUid: String,
        hostProfile: String,
        guestUid: String?,
        guestProfile: String?,
        status: MedxDuelStatus,
        source: MedxDuelSource?,
        total: Int,
        deckParts: Int,
        qIndex: Int,
        askedAt: Double?,
        log: [MedxDuelLogRow],
        createdAt: String,
        updatedAt: String,
        finishedAt: String?
    ) {
        self.id = id
        self.hostUid = hostUid
        self.hostProfile = hostProfile
        self.guestUid = guestUid
        self.guestProfile = guestProfile
        self.status = status
        self.source = source
        self.total = total
        self.deckParts = deckParts
        self.qIndex = qIndex
        self.askedAt = askedAt
        self.log = log
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.finishedAt = finishedAt
    }
}
