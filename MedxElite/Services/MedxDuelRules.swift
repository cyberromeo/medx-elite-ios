import Foundation

/// Faceoff — the rules of the game, and nothing else.
///
/// Deliberately free of anything but Foundation. Every function here is pure, which is what makes
/// the arithmetic and the phase machine readable in one place and checkable without a device — and
/// this project cannot sign in from the machine it is written on.
///
/// The two things worth reading twice are `remaining(at:)` and `phase(game:mine:theirs:now:)`.
public enum MedxDuelRules {
    /// One minute a question, same as revision mode in the solo runner.
    public static let perQuestion = 60

    /// Being right is the floor; the clock is the rest. See `score(_:)`.
    public static let basePoints = 40
    public static let maxPoints = basePoints + perQuestion // 100

    /// The 3-2-1 before a question opens. A touch over 3s so all three digits show.
    public static let armWindow: TimeInterval = 3.2

    /// Deck sizes the host can pick. 0 means "all of it".
    public static let lengths = [10, 20, 30, 0]

    /// How long a lobby nobody joined stays offerable.
    public static let staleLobby: TimeInterval = 45 * 60

    /// Short, sortable, readable in a URL — the same shape the PWA generates.
    public static func newGameId() -> String {
        let stamp = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let salt = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(3)).lowercased()
        return "g\(stamp)\(salt)"
    }

    // MARK: - Clock

    public static func deadline(askedAt: Double) -> Double {
        askedAt + Double(perQuestion) * 1000
    }

    /// Seconds still on the clock — the single expression behind both the countdown the player
    /// watches and the number their points are made of.
    ///
    /// `ceil` rather than `floor` so the clock shows 60 the instant a question opens and 0 only
    /// when it is genuinely spent, and so 100 is reachable. Clamped at the top because while a
    /// round is arming `askedAt` is in the future.
    public static func remaining(at askedAt: Double, now: Double = Date().timeIntervalSince1970 * 1000) -> Int {
        let left = (deadline(askedAt: askedAt) - now) / 1000
        return max(0, min(perQuestion, Int(ceil(left))))
    }

    // MARK: - Points

    /// The whole points system.
    ///
    ///     right      40 + whatever the clock still read when you tapped   40 … 100
    ///     wrong                                                                  0
    ///     no answer                                                              0
    ///
    /// There is no first-in or solo bonus, because being first *is* the bonus: it is what leaves
    /// more on the clock. A correct answer with 0:32 left is 40 + 32 = 72, and the 32 is the digit
    /// the player was looking at — `remaining` is captured at the tap and never recomputed, or the
    /// payout would be smaller than what they saw.
    public static func score(_ answer: MedxDuelRound?) -> Int {
        guard let answer, answer.correct else { return 0 }
        return basePoints + max(0, min(perQuestion, answer.remaining))
    }

    public static func possiblePoints(_ total: Int) -> Int {
        max(0, total) * maxPoints
    }

    // MARK: - Phases

    /// What to show for a player at reveal.
    ///
    /// Absence past the deadline is a timeout — and it has to be *read* that way rather than
    /// waited for, because the client that ran out of clock is the one that writes its own
    /// timeout row, and an app frozen in the background will not write anything at all. Before
    /// the deadline, absence just means "still thinking".
    public static func shownAnswer(
        of player: MedxDuelPlayer?,
        qIndex: Int,
        askedAt: Double,
        now: Double = Date().timeIntervalSince1970 * 1000
    ) -> MedxDuelRound? {
        if let own = player?.answer(to: qIndex) { return own }
        return now >= deadline(askedAt: askedAt) ? MedxDuelRound.timedOut(qIndex: qIndex) : nil
    }

    /// Where the room is, from the three documents both clients can already see.
    ///
    /// Nothing is written to reach a phase — reveal in particular is *derived*, so both screens
    /// turn over on the same input rather than waiting for a referee round-trip.
    public static func phase(
        game: MedxDuelGame?,
        mine: MedxDuelPlayer?,
        theirs: MedxDuelPlayer?,
        now: Double = Date().timeIntervalSince1970 * 1000
    ) -> MedxDuelPhase {
        guard let game else { return .loading }
        if game.status == .done { return .done }
        if game.status == .abandoned { return .abandoned }
        guard game.status == .live, let askedAt = game.askedAt, askedAt.isFinite else { return .lobby }

        if now < askedAt { return .arming }

        let iAnswered = mine?.answer(to: game.qIndex) != nil
        let theyAnswered = theirs?.answer(to: game.qIndex) != nil
        if iAnswered && theyAnswered { return .reveal }
        if now >= deadline(askedAt: askedAt) { return .reveal }
        return iAnswered ? .waiting : .asked
    }

    /// Whether the host may start.
    ///
    /// Joining is the guest's readiness signal, so the button is dead until their player document
    /// exists and stays dead if they back out — there is nothing for the guest to press, which is
    /// what keeps it obvious who is being waited on.
    public static func canStart(game: MedxDuelGame?, isHost: Bool, theirs: MedxDuelPlayer?) -> Bool {
        guard isHost, let game, game.status == .lobby, let theirs, !theirs.left else { return false }
        return true
    }

    /// A lobby nobody has joined goes cold rather than sitting in the list forever.
    public static func isOfferable(_ game: MedxDuelGame, now: Date = Date()) -> Bool {
        guard game.status == .lobby else { return false }
        guard let created = game.createdDate else { return true }
        return now.timeIntervalSince(created) < staleLobby
    }
}

/// The six places a room can be. All derived; none of them is written anywhere.
public enum MedxDuelPhase: String, Hashable, Sendable {
    /// Still reading the documents.
    case loading
    /// Dealt, and waiting for the other one. Start lives here.
    case lobby
    /// `askedAt` is in the future: the 3 · 2 · 1.
    case arming
    /// The minute is running and you have not picked.
    case asked
    /// You picked; the other one has not, and the clock is still alive.
    case waiting
    /// Both picked, or the minute is gone.
    case reveal
    /// The last question was voted through.
    case done
    /// Somebody left mid-game.
    case abandoned
}

// MARK: - Tally

public extension MedxDuelRules {
    /// One round scored, from both sides' answers.
    ///
    /// `first` is whoever had more of the clock left. Two taps inside the same second read as
    /// identical numbers, so they credit *nobody* — the alternative is telling both players they
    /// were first, which is worse than telling neither.
    static func tally(
        sides: [(uid: String, answer: MedxDuelRound?)]
    ) -> (rows: [String: MedxDuelAnswerRow], first: String?, winner: String?, best: Int) {
        var rows: [String: MedxDuelAnswerRow] = [:]
        var live: [(uid: String, remaining: Int)] = []

        for side in sides {
            let answer = side.answer
            let attempted = answer?.attempted ?? false
            let remaining = attempted ? max(0, answer?.remaining ?? 0) : nil
            if let remaining { live.append((side.uid, remaining)) }
            rows[side.uid] = MedxDuelAnswerRow(
                optionId: answer?.optionId,
                correct: answer?.correct ?? false,
                timedOut: (answer?.timedOut ?? true),
                remaining: remaining,
                points: score(answer)
            )
        }

        var first: String?
        if live.count == 1 {
            first = live[0].uid
        } else if live.count == 2, live[0].remaining != live[1].remaining {
            first = live[0].remaining > live[1].remaining ? live[0].uid : live[1].uid
        }

        let best = rows.values.reduce(0) { max($0, $1.points) }
        let top = rows.filter { $0.value.points == best && $0.value.points > 0 }
        return (rows, first, top.count == 1 ? top.keys.first : nil, best)
    }

    /// A log row, ready to be appended to the game document.
    static func logRow(
        qIndex: Int,
        questionId: Int?,
        sides: [(uid: String, answer: MedxDuelRound?)]
    ) -> MedxDuelLogRow {
        let result = tally(sides: sides)
        return MedxDuelLogRow(
            qIndex: qIndex,
            questionId: questionId,
            first: result.first,
            winner: result.winner,
            answers: result.rows
        )
    }

    /// The whole game folded up, derived from the log so the scoreboard and the live versus bar
    /// cannot disagree with the round-by-round review.
    static func finalScores(log: [MedxDuelLogRow], uids: [String]) -> [String: MedxDuelScore] {
        var out = Dictionary(uniqueKeysWithValues: uids.map { ($0, MedxDuelScore()) })
        for row in log {
            for uid in uids {
                guard var score = out[uid] else { continue }
                let answer = row.answers[uid]
                score.rounds += 1
                score.points += answer?.points ?? 0
                if answer?.correct == true { score.correct += 1 }
                if let answer, !answer.timedOut, answer.optionId != nil {
                    score.answered += 1
                    if answer.correct {
                        let took = perQuestion - (answer.remaining ?? 0)
                        if score.fastest == nil || took < (score.fastest ?? .max) {
                            score.fastest = took
                        }
                    }
                }
                if row.first == uid { score.firsts += 1 }
                out[uid] = score
            }
        }
        return out
    }

    /// Who won, or nil for a dead heat.
    static func leader(scores: [String: MedxDuelScore], uids: [String]) -> String? {
        let rows = uids.map { ($0, scores[$0]?.points ?? 0) }
        let best = rows.reduce(0) { max($0, $1.1) }
        let top = rows.filter { $0.1 == best }
        return top.count == 1 ? top[0].0 : nil
    }
}

// MARK: - Filing it as a sitting

public extension MedxDuelRules {
    /// The log, rewritten as `medx_attempts` response rows.
    ///
    /// A faceoff *is* a sitting, so it is filed like one and folds into accuracy, streak and
    /// coverage — which means matching the runner's shape exactly, including seconds as time
    /// *taken* rather than the `remaining` the duel scores on.
    static func attemptResponses(
        log: [MedxDuelLogRow],
        uid: String
    ) -> (responses: [QuestionResponse], seconds: Int) {
        var responses: [QuestionResponse] = []
        var seconds = 0

        for row in log {
            let answer = row.answers[uid]
            let took = answer?.remaining == nil ? perQuestion : perQuestion - (answer?.remaining ?? 0)
            seconds += max(0, min(perQuestion, took))
            responses.append(
                QuestionResponse(
                    questionId: row.questionId ?? 0,
                    chosenId: answer?.optionId,
                    correct: answer?.correct ?? false,
                    timedOut: answer?.timedOut
                )
            )
        }
        return (responses, seconds)
    }
}

// MARK: - Dealing

public extension MedxDuelRules {
    /// Turn a source's questions into the deck both players will see.
    ///
    /// The deck is written out rather than re-fetched on each side for two reasons: a custom
    /// module may exist only on the host's device, and even for a Marrow paper the shuffle has to
    /// be identical, which is only guaranteed if it happens once.
    ///
    /// Unkeyed questions are dropped, and the count is reported so the lobby can say so.
    static func deal(
        questions: [Question],
        length: Int,
        shuffle: Bool = true
    ) -> (deck: [MedxDuelQuestion], parts: [[MedxDuelQuestion]], dropped: Int) {
        let keyed = questions.filter { !MedxDuelQuestion.correctIds(of: $0).isEmpty }
        let ordered = shuffle ? keyed.shuffled() : keyed
        let cut = length > 0 ? Array(ordered.prefix(length)) : ordered
        let deck = cut.map { MedxDuelQuestion(question: $0) }
        return (deck, chunk(deck), questions.count - keyed.count)
    }

    /// A deck split across documents.
    ///
    /// "All" on a 150-question grand paper is well past Firestore's 1 MiB per-document limit once
    /// explanations are carried, so the deck is chunked by measured size the same way the seeder
    /// chunks `medx_test_questions`. 700 KB leaves room for the document's own overhead.
    static func chunk(_ questions: [MedxDuelQuestion], maxBytes: Int = 700_000) -> [[MedxDuelQuestion]] {
        var parts: [[MedxDuelQuestion]] = []
        var current: [MedxDuelQuestion] = []
        var size = 0
        let encoder = JSONEncoder()

        for question in questions {
            let bytes = (try? encoder.encode(question).count) ?? 2_000
            if !current.isEmpty, size + bytes > maxBytes {
                parts.append(current)
                current = []
                size = 0
            }
            current.append(question)
            size += bytes
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }
}
