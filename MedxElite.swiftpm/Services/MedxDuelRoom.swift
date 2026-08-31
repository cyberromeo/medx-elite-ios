import Foundation
import Combine
import SwiftUI

/// One live Faceoff.
///
/// Three documents come in — the game and both player rows — and everything the room draws is
/// *derived* from them. Nothing is written to reach a phase: reveal in particular falls out of
/// "both answered, or the minute is gone", so the two screens turn over on the same input rather
/// than one of them waiting on a referee round-trip. The only writes are a player's own move and,
/// for the host, opening the next round.
@MainActor
public final class MedxDuelRoom: ObservableObject {
    // The documents.
    @Published public private(set) var game: MedxDuelGame?
    @Published public private(set) var players: [MedxDuelPlayer] = []
    @Published public private(set) var deck: [MedxDuelQuestion] = []
    @Published public private(set) var failure: String?
    @Published public private(set) var hasLoadedGame = false
    /// True once a read has proved the game is not there — a cancelled lobby, or a bad deep link.
    @Published public private(set) var isMissing = false

    /// Recomputed only when the *displayed* number changes, so a round re-renders about once a
    /// second rather than ten times.
    @Published public private(set) var remaining = MedxDuelRules.perQuestion
    @Published public private(set) var armingIn = 0
    @Published public private(set) var phase: MedxDuelPhase = .loading

    private var roomSubscription: MedxDuelSubscription?
    private var ticker: Timer?
    private var gameId: String?
    private var deckLoadedFor: String?

    /// Claimed before each one-shot write and released only if it failed. Guarded on the question
    /// number rather than a boolean, because `reveal` re-renders.
    private var timedOutFor = -1
    private var advancedFor = -1
    private var savedFor: String?

    /// A stub handed in by a test, which always wins.
    private let injected: MedxDuelTransport?
    /// The transport this room is actually using, resolved on first use rather than at `init`.
    private var live: MedxDuelTransport?

    /// **Resolved when a stream opens, not when this object is made.**
    ///
    /// This was a `let` assigned in `init`, and that was the Faceoff transport bug: `init` runs
    /// while the SDK sign-in is still an unawaited `Task` (see `AuthService.restoreSDKSession` and
    /// `MedxEliteApp.bootstrap`), so `MedxFirebaseBridge.isReady` was reliably `false` and the
    /// poller was chosen — and then kept for the life of the object no matter what happened next.
    /// A room is opened from a `.task`, long after auth has settled, so asking here asks at the
    /// only moment the answer can be right.
    private var transport: MedxDuelTransport {
        if let injected { return injected }
        if let live { return live }
        let made = MedxDuelTransportFactory.make()
        live = made
        return made
    }

    /// `nil` rather than `MedxDuelTransportFactory.make()` as the default, because a default
    /// argument expression is evaluated at the *call site* in a nonisolated context — and `make()`
    /// is `@MainActor`, since choosing the transport reads `MedxFirebaseBridge`. The parameter stays
    /// so a test can hand in a stub.
    public init(transport: MedxDuelTransport? = nil) {
        self.injected = transport
    }

    deinit {
        ticker?.invalidate()
    }

    // MARK: - People

    private var uid: String? { AuthService.shared.currentSession?.uid }

    public var isHost: Bool { game?.isHost(uid) ?? false }

    public var mine: MedxDuelPlayer? { players.first { $0.uid == uid } }

    public var theirs: MedxDuelPlayer? { players.first { $0.uid != uid && !$0.uid.isEmpty } }

    public var myProfile: Profile? {
        AuthService.shared.currentProfile ?? mine?.displayProfile
    }

    /// Their profile from their player row where it exists, and from the game document before they
    /// have joined — so the lobby can name who is being waited on.
    public var theirProfile: Profile? {
        if let theirs = theirs?.displayProfile { return theirs }
        let id = isHost ? game?.guestProfile : game?.hostProfile
        if let id, let profile = Profile.byId(id) { return profile }
        return Profile.allProfiles.first { $0.uid != uid }
    }

    public var canStart: Bool {
        MedxDuelRules.canStart(game: game, isHost: isHost, theirs: theirs)
    }

    public var theyLeft: Bool { theirs?.left ?? false }

    // MARK: - Where we are

    public var qIndex: Int { game?.qIndex ?? 0 }

    public var total: Int { game?.total ?? deck.count }

    public var question: MedxDuelQuestion? {
        deck.indices.contains(qIndex) ? deck[qIndex] : nil
    }

    public var source: MedxDuelSource? { game?.source }

    public var isLoading: Bool {
        !hasLoadedGame || (game?.status == .live && deck.isEmpty)
    }

    // MARK: - The round

    public var myAnswer: MedxDuelRound? { mine?.answer(to: qIndex) }
    public var theirAnswer: MedxDuelRound? { theirs?.answer(to: qIndex) }

    /// What to *show*, which past the deadline means a timeout even from a side that never wrote
    /// one — an app frozen in the background writes nothing at all.
    public var shownMine: MedxDuelRound? { shown(for: mine) }
    public var shownTheirs: MedxDuelRound? { shown(for: theirs) }

    private func shown(for player: MedxDuelPlayer?) -> MedxDuelRound? {
        guard let askedAt = game?.askedAt else { return nil }
        return MedxDuelRules.shownAnswer(of: player, qIndex: qIndex, askedAt: askedAt)
    }

    /// "Mathu answered already" — only while you still have a pick to make.
    public var beatenBy: Profile? {
        (myAnswer == nil && theirAnswer != nil) ? theirProfile : nil
    }

    public var iVoted: Bool { mine?.hasVoted(past: qIndex) ?? false }
    public var theyVoted: Bool { theirs?.hasVoted(past: qIndex) ?? false }

    /// The round scored, for the reveal. Derived on both clients from the same two answers, so the
    /// breakdown on the two screens cannot disagree — and it is the same computation the host's log
    /// row is built from.
    public var tally: (rows: [String: MedxDuelAnswerRow], first: String?, winner: String?, best: Int)? {
        guard phase == .reveal, let uid, let theirUid = theirs?.uid else { return nil }
        return MedxDuelRules.tally(sides: [
            (uid, shownMine),
            (theirUid, shownTheirs)
        ])
    }

    public var uids: [String] {
        [game?.hostUid, game?.guestUid ?? theirs?.uid].compactMap { $0 }
    }

    /// Banked points, straight off the log, so the versus bar cannot disagree with the
    /// round-by-round review on the scoreboard.
    public var scores: [String: MedxDuelScore] {
        MedxDuelRules.finalScores(log: game?.log ?? [], uids: uids)
    }

    public var myScore: MedxDuelScore { uid.flatMap { scores[$0] } ?? MedxDuelScore() }
    // `theirs.flatMap`, not `theirs?.uid.flatMap`: inside the optional chain `uid` is a non-optional
    // `String`, so that would pick `Sequence.flatMap` and subscript `scores` with a `Character`.
    public var theirScore: MedxDuelScore { theirs.flatMap { scores[$0.uid] } ?? MedxDuelScore() }

    // MARK: - Lifecycle

    public func open(gameId: String) {
        guard self.gameId != gameId else { return }
        close()
        self.gameId = gameId
        hasLoadedGame = false
        isMissing = false
        failure = nil

        roomSubscription = transport.watchRoom(gameId: gameId) { [weak self] snapshot in
            self?.apply(snapshot, gameId: gameId)
        }
        startTicker()
        // A duel is a minute a question with no interaction between taps; the screen going dark
        // mid-round is the one thing a web app could not prevent and this can.
        UIApplication.shared.isIdleTimerDisabled = true
    }

    public func close() {
        roomSubscription?.cancel()
        roomSubscription = nil
        ticker?.invalidate()
        ticker = nil
        gameId = nil
        deckLoadedFor = nil
        timedOutFor = -1
        advancedFor = -1
        // Dropped so the next `open` re-asks which transport to use. The SDK may have signed in
        // between the two, and a closed room has nothing left that a stale choice would help.
        live = nil
        UIApplication.shared.isIdleTimerDisabled = false
        MedxLiveActivityController.shared.endDuel()
    }

    private func apply(_ snapshot: MedxDuelRoomSnapshot, gameId: String) {
        guard self.gameId == gameId else { return }
        hasLoadedGame = true
        failure = snapshot.failure

        if snapshot.failure == nil {
            isMissing = snapshot.game == nil
        }
        game = snapshot.game
        players = snapshot.players

        recomputePhase()
        loadDeckIfNeeded(gameId: gameId)
        writeMyTimeoutIfNeeded()
        advanceIfHostAndReady()
        fileAttemptIfDone()
        refreshLiveActivity()
    }

    /// The deck is immutable once dealt, so it is one read rather than a stream.
    private func loadDeckIfNeeded(gameId: String) {
        guard deckLoadedFor != gameId, game?.status != .lobby else { return }
        deckLoadedFor = gameId
        Task {
            do {
                deck = try await transport.loadDeck(gameId: gameId)
            } catch {
                deckLoadedFor = nil
                failure = "The deck for this game could not be read."
            }
        }
    }

    // MARK: - The clock

    /// Ten hertz, but only *published* when the number on screen actually changes.
    ///
    /// The 3·2·1 is 3.2 seconds long, so a one-second tick cannot draw it, and the boundary between
    /// arming and the open question has to land on time rather than on the next whole second —
    /// that boundary is where the minute starts. During the round itself the reading only changes
    /// once a second, so the view redraws about sixty times, not six hundred.
    ///
    /// Every reading is `remaining(at:)` against a shared `askedAt`, never an accumulator: a
    /// suspended app has to land on the right number on its first frame back, and two devices have
    /// to agree on the number even when their tick moments do not.
    private func startTicker() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard let game, game.status == .live, let askedAt = game.askedAt else {
            recomputePhase()
            return
        }
        let now = Date().timeIntervalSince1970 * 1000

        let nextRemaining = MedxDuelRules.remaining(at: askedAt, now: now)
        let nextArming = now < askedAt ? max(1, Int(ceil((askedAt - now) / 1000))) : 0
        if nextRemaining != remaining { remaining = nextRemaining }
        if nextArming != armingIn { armingIn = nextArming }

        recomputePhase(now: now)
        // A deadline that has passed with no answer from this side is a timeout it has to write
        // itself, and the boundary is a clock event rather than a document change.
        writeMyTimeoutIfNeeded()
        advanceIfHostAndReady()
    }

    private func recomputePhase(now: Double = Date().timeIntervalSince1970 * 1000) {
        let next = MedxDuelRules.phase(game: game, mine: mine, theirs: theirs, now: now)
        guard next != phase else { return }
        phase = next
        transport.setUrgency(next)
        if next == .asked { HapticManager.medium() }
        if next == .reveal { HapticManager.selection() }
    }

    // MARK: - The three guards

    /// The client whose clock ran out writes its *own* timed-out row, because writing it for the
    /// other one would mean writing their document.
    private func writeMyTimeoutIfNeeded() {
        guard let gameId, let uid, phase == .reveal, myAnswer == nil else { return }
        guard timedOutFor != qIndex else { return }
        timedOutFor = qIndex
        let round = MedxDuelRound.timedOut(qIndex: qIndex)
        Task {
            try? await transport.submitAnswer(gameId: gameId, uid: uid, round: round)
        }
    }

    /// Only the host opens the next round — it is the one piece of shared state a round transition
    /// touches.
    ///
    /// If the host's app is in the background iOS has frozen its timer and nothing advances; the
    /// guest is *told* that rather than trying to referee, because refereeing would mean writing
    /// the host's document.
    private func advanceIfHostAndReady() {
        guard let gameId, let game, let uid, let theirUid = theirs?.uid else { return }
        guard isHost, phase == .reveal, !deck.isEmpty, iVoted, theyVoted else { return }
        guard advancedFor != qIndex else { return }
        advancedFor = qIndex

        let row = MedxDuelRules.logRow(
            qIndex: qIndex,
            questionId: question?.id,
            sides: [(uid, shownMine), (theirUid, shownTheirs)]
        )
        let nextIndex = qIndex + 1
        let isLast = nextIndex >= max(game.total, deck.count)

        Task {
            do {
                if isLast {
                    try await transport.finishGame(
                        gameId: gameId,
                        row: row,
                        scores: MedxDuelRules.finalScores(log: game.log + [row], uids: uids)
                    )
                } else {
                    try await transport.advance(gameId: gameId, row: row, nextIndex: nextIndex)
                }
            } catch {
                // Released, or a dropped connection at the wrong moment would leave the round
                // stuck with both votes in and nothing opening the next question.
                advancedFor = -1
                failure = "That round would not close. Tap Next again."
            }
        }
    }

    /// A faceoff counts, so each player files their *own* attempt row — the same rule as everywhere
    /// else here, and the same one-write-per-sitting guard the solo runner uses. Keyed on the game
    /// id, so re-opening a finished room to read the review does not file it twice.
    private func fileAttemptIfDone() {
        guard phase == .done, let gameId, let uid, let game, !game.log.isEmpty else { return }
        guard savedFor != gameId else { return }
        savedFor = gameId

        let rows = MedxDuelRules.attemptResponses(log: game.log, uid: uid)
        let mineScore = scores[uid] ?? MedxDuelScore()
        let attempt = SittingAttempt(
            id: nil,
            uid: uid,
            profile: AuthService.shared.currentProfile?.handle,
            kind: "duel",
            sourceId: game.source?.id ?? gameId,
            name: game.source?.name ?? "Faceoff",
            subject: game.source?.subject ?? game.source?.name ?? "",
            mode: "faceoff",
            gradable: true,
            total: max(game.total, rows.responses.count),
            score: mineScore.correct,
            attempted: mineScore.answered,
            durationSeconds: rows.seconds,
            finishedAt: game.finishedAt ?? ISO8601DateFormatter().string(from: Date()),
            responses: rows.responses
        )

        Task {
            guard let token = try? await AuthService.shared.getValidIdToken() else { return }
            try? await FirestoreService.shared.saveAttempt(attempt, idToken: token)
        }
    }

    // MARK: - Moves

    public func answer(_ option: QuestionOption) {
        guard let gameId, let uid, let question, phase == .asked else { return }
        HapticManager.selection()
        let round = MedxDuelRound(
            qIndex: qIndex,
            optionId: option.id,
            // The number the player was looking at, not a fresh reading — see `remaining` above.
            remaining: remaining,
            correct: question.correctIds.contains(option.id)
        )
        Task {
            do {
                try await transport.submitAnswer(gameId: gameId, uid: uid, round: round)
            } catch {
                failure = "That answer did not reach Firestore."
            }
        }
    }

    public func voteNext() {
        guard let gameId, let uid, phase == .reveal, !iVoted else { return }
        HapticManager.light()
        let index = qIndex
        Task { try? await transport.voteNext(gameId: gameId, uid: uid, qIndex: index) }
    }

    public func start() {
        guard let gameId, canStart, let theirs else { return }
        HapticManager.success()
        Task {
            do {
                try await transport.startGame(
                    gameId: gameId,
                    guestUid: theirs.uid,
                    guestProfile: theirs.profile
                )
            } catch {
                failure = "The game would not start."
            }
        }
    }

    public func join() {
        guard let gameId, let uid, let profile = myProfile, !isHost, mine == nil else { return }
        HapticManager.success()
        Task {
            do {
                try await transport.joinGame(gameId: gameId, uid: uid, profile: profile.id)
            } catch {
                failure = "Joining did not go through."
            }
        }
    }

    /// Own document first — that write always belongs to the caller. The host then closes the game
    /// itself, which is a field only the host may touch.
    public func leave() async {
        guard let gameId, let uid else { return }
        try? await transport.leaveGame(gameId: gameId, uid: uid)
        if isHost, game?.status != .done {
            try? await transport.abandonGame(gameId: gameId)
        }
        close()
    }

    // MARK: - Live Activity

    private func refreshLiveActivity() {
        guard let game, let mineUid = uid, let theirUid = theirs?.uid else { return }

        switch phase {
        case .done, .abandoned, .loading:
            MedxLiveActivityController.shared.endDuel()
        case .lobby:
            break
        case .arming, .asked, .waiting, .reveal:
            guard let askedAt = game.askedAt else { return }
            MedxLiveActivityController.shared.updateDuel(
                mine: myProfile,
                theirs: theirProfile,
                total: max(game.total, deck.count),
                state: MedxDuelActivityAttributes.ContentState(
                    qIndex: qIndex,
                    myPoints: scores[mineUid]?.points ?? 0,
                    theirPoints: scores[theirUid]?.points ?? 0,
                    phase: phase.rawValue,
                    roundEndDate: Date(timeIntervalSince1970: MedxDuelRules.deadline(askedAt: askedAt) / 1000)
                )
            )
        }
    }
}

// MARK: - Open lobbies, app-wide

/// The one subscription to every open lobby.
///
/// Home shows a Join card and the Library tile shows a badge, and both want the same answer — so
/// this is a singleton with a single stream rather than two screens each starting their own. On the
/// polling transport that halves the request rate for the whole time the app is open; on the SDK it
/// is one listener instead of two.
///
/// This is also the one thing that pulls the duel transport into the launch path, and that is what
/// made the transport latch bug *this* type's problem more than the room's: `shared` is a `static
/// let`, so it used to call `MedxDuelTransportFactory.make()` the first time any screen touched it —
/// during launch, while the SDK sign-in was still in flight — and hold the answer forever. Two
/// things fix it: the transport is resolved when `start()` opens the stream, and a readiness flip
/// from `MedxFirebaseBridge` tears the stream down and reopens it on the better transport.
@MainActor
public final class MedxLobbyWatcher: ObservableObject {
    public static let shared = MedxLobbyWatcher()

    @Published public private(set) var lobbies: [MedxDuelGame] = []
    @Published public private(set) var hasLoaded = false

    private let injected: MedxDuelTransport?
    private var live: MedxDuelTransport?
    private var subscription: MedxDuelSubscription?
    private var readiness: AnyCancellable?

    /// What Settings ▸ Diagnostics reports. `nil` while nothing is subscribed, which is an honest
    /// answer rather than a guess — before a stream is open there is no transport in use to name.
    ///
    /// Deliberately does **not** go through `transport`: reading a diagnostics row must not be the
    /// thing that decides which transport the app uses for the rest of the session.
    public var activeTransportName: String? {
        guard subscription != nil else { return nil }
        return (injected ?? live)?.transportName
    }

    private var transport: MedxDuelTransport {
        if let injected { return injected }
        if let live { return live }
        let made = MedxDuelTransportFactory.make()
        live = made
        return made
    }

    private init(transport: MedxDuelTransport? = nil) {
        self.injected = transport
        // Deliberately the only work `init` does. Subscribing to readiness is cheap and touches
        // nothing; resolving a transport here is what the bug was.
        //
        // The hop through `Task { @MainActor in }` is the same one `MedxDuelRoom.startTicker` makes
        // for the same reason: a Combine `sink` closure is not actor-isolated, and everything it
        // touches here is.
        readiness = MedxFirebaseBridge.shared.$isReady
            .removeDuplicates()
            .sink { ready in
                guard ready else { return }
                Task { @MainActor in MedxLobbyWatcher.shared.upgradeToListeners() }
            }
    }

    /// Lobbies the *other* one dealt and nobody has joined. Stale ones go cold rather than sitting
    /// in the list forever.
    public var theirs: [MedxDuelGame] {
        let uid = AuthService.shared.currentSession?.uid
        return lobbies.filter { $0.hostUid != uid && MedxDuelRules.isOfferable($0) }
    }

    /// Gated on a uid: a read that fires before auth resolves reports a permission error that is a
    /// race, not a rules problem.
    public func start() {
        guard AuthService.shared.currentSession != nil, subscription == nil else { return }
        transport.setUrgency(.lobby)
        subscription = transport.watchOpenLobbies { [weak self] games in
            self?.lobbies = games
            self?.hasLoaded = true
        }
    }

    public func stop() {
        subscription?.cancel()
        subscription = nil
    }

    /// The SDK signed in after this stream was already polling. Swap under it.
    ///
    /// Only ever an *upgrade*. Readiness going false means the SDK became unusable, and a listener
    /// stream that has stopped delivering is not something this could detect or repair from here —
    /// the poller it would want is chosen on the next `start()` anyway.
    ///
    /// `internal` rather than `private` because the readiness subscription reaches it through
    /// `shared`: the `sink` closure has to hop to the main actor, and hopping with a captured `self`
    /// is what would make it a retain cycle.
    func upgradeToListeners() {
        guard injected == nil, subscription != nil else { return }
        if let live, live is MedxFirestoreDuelTransportMarker { return }
        stop()
        live = nil
        start()
    }
}

/// What "already on the better transport" means, without `#if canImport` leaking into
/// `MedxLobbyWatcher`.
///
/// `MedxFirestoreDuelTransport` only exists in a build that has the Firebase package, so naming it
/// in a type check would need an availability fence around the check itself. Conformance instead:
/// the SDK transport declares it, the poller does not, and the Playgrounds target — which has no SDK
/// transport at all — sees a protocol nothing conforms to, which is exactly right.
public protocol MedxFirestoreDuelTransportMarker {}

// MARK: - Which transport

public enum MedxDuelTransportFactory {
    /// The SDK where it is linked, the poller otherwise.
    ///
    /// `MedxFirebaseBridge.isReady` is false in the Swift Playgrounds target, which cannot take the
    /// Firebase package, and also on a device where `FirebaseApp.configure` or the SDK sign-in
    /// failed — in both cases the poller is a working Faceoff rather than no Faceoff.
    @MainActor
    public static func make() -> MedxDuelTransport {
        #if canImport(FirebaseFirestore)
        if MedxFirebaseBridge.shared.isReady {
            return MedxFirestoreDuelTransport()
        }
        #endif
        return MedxDuelRestTransport()
    }
}
