import Foundation

/// Faceoff over plain Firestore REST, by polling.
///
/// REST has no equivalent of the SDK's snapshot listeners, so this is the fallback — and the only
/// transport the Swift Playgrounds target can build, since it cannot take the Firebase package.
/// Three things keep the cost sane:
///
/// - **One request per tick.** The game document and both player documents have deterministic
///   names, so `batchGet` returns all three together. Three document reads a tick, not three
///   requests.
/// - **The tick follows the phase.** Nothing is polled while the 3·2·1 runs, because that clock is
///   derived from `askedAt` and both devices already have it. A round that is waiting on the other
///   one polls every second; a lobby polls every three.
/// - **A local write pokes it.** Answering does not wait for the next tick to see itself.
///
/// About 700–1,000 reads for a 20-question game per player, against a 50,000/day free tier.
@MainActor
public final class MedxDuelRestTransport: MedxDuelTransport {
    public private(set) var remoteWorks: Bool?

    public let transportName = "Polling"

    private var urgency: MedxDuelPhase = .loading
    private var pokeRequested = false

    public init() {}

    /// How long to wait before the next read, by where the room is.
    private var interval: Duration {
        switch urgency {
        case .loading: return .milliseconds(400)
        // Nothing to learn during the countdown: `askedAt` is already on both devices.
        case .arming: return .milliseconds(1_600)
        case .lobby: return .seconds(3)
        // They may have answered already, which is worth knowing but not urgently — the round
        // cannot turn over until this side picks something.
        case .asked: return .seconds(2)
        // This side has picked and the round turns over the moment they do. The one tick that has
        // to be fast.
        case .waiting, .reveal: return .seconds(1)
        case .done, .abandoned: return .seconds(6)
        }
    }

    public func setUrgency(_ phase: MedxDuelPhase) {
        urgency = phase
    }

    private func poke() {
        pokeRequested = true
    }

    // MARK: - Streams

    public func watchRoom(
        gameId: String,
        onChange: @escaping (MedxDuelRoomSnapshot) -> Void
    ) -> MedxDuelSubscription {
        // Both uids are hard-coded profiles, so both player document names are known without a
        // query — which is the whole reason one request can carry the room.
        let paths: [(collection: String, docId: String)] =
            [(MedxDuelPath.games, gameId)]
            + Profile.allProfiles.map {
                (MedxDuelPath.players, MedxDuelPlayer.docId(gameId: gameId, uid: $0.uid))
            }

        let task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.readRoom(gameId: gameId, paths: paths, onChange: onChange)
                await self?.waitForNextTick()
            }
        }
        return MedxDuelSubscription { task.cancel() }
    }

    private func readRoom(
        gameId: String,
        paths: [(collection: String, docId: String)],
        onChange: (MedxDuelRoomSnapshot) -> Void
    ) async {
        guard let token = try? await AuthService.shared.getValidIdToken() else { return }
        do {
            let documents = try await FirestoreService.shared.batchGet(paths: paths, idToken: token)
            remoteWorks = true

            let game = documents[gameId].flatMap { MedxDuelCodec.game(id: gameId, fields: $0) }
            let players = documents
                .filter { $0.key != gameId }
                .compactMap { MedxDuelCodec.player(fields: $0.value) }

            onChange(MedxDuelRoomSnapshot(game: game, players: players))
        } catch {
            remoteWorks = false
            onChange(
                MedxDuelRoomSnapshot(
                    game: nil,
                    players: [],
                    failure: "Firestore would not read the duel documents."
                )
            )
        }
    }

    /// Sleeps in slices so a local write can cut the wait short. A single `Task.sleep` for the
    /// whole interval would mean answering a question and then watching a one-second gap before
    /// the screen agreed that you had.
    private func waitForNextTick() async {
        let slice = Duration.milliseconds(120)
        var waited = Duration.zero
        let target = interval
        while waited < target, !Task.isCancelled {
            if pokeRequested {
                pokeRequested = false
                return
            }
            try? await Task.sleep(for: slice)
            waited += slice
        }
    }

    public func watchOpenLobbies(
        onChange: @escaping ([MedxDuelGame]) -> Void
    ) -> MedxDuelSubscription {
        let task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.readLobbies(onChange: onChange)
                // Slower than a live room on purpose: this runs on Home and in the Library badge
                // for the whole time the app is open, and a dealt game a few seconds late is not
                // a dealt game missed.
                try? await Task.sleep(for: .seconds(5))
            }
        }
        return MedxDuelSubscription { task.cancel() }
    }

    private func readLobbies(onChange: ([MedxDuelGame]) -> Void) async {
        guard let token = try? await AuthService.shared.getValidIdToken() else { return }
        do {
            // A single equality filter, because a composite index is not something anyone on this
            // project can deploy. The split by owner and the sort happen in memory.
            let documents = try await FirestoreService.shared.runRawQuery(
                collection: MedxDuelPath.games,
                whereField: "status",
                equals: MedxDuelStatus.lobby.rawValue,
                idToken: token
            )
            remoteWorks = true
            onChange(games(from: documents))
        } catch {
            remoteWorks = false
            onChange([])
        }
    }

    private func games(from documents: [[String: Any]]) -> [MedxDuelGame] {
        documents.compactMap { doc in
            guard let rawFields = doc["fields"] as? [String: Any],
                  let name = doc["name"] as? String,
                  let id = name.split(separator: "/").last
            else { return nil }
            return MedxDuelCodec.game(
                id: String(id),
                fields: FirestoreService.normalizeFirestoreMap(rawFields)
            )
        }
    }

    // MARK: - Reads

    /// The deck, by name rather than by listing the subcollection.
    ///
    /// `deckParts` is on the game document, and the parts are named `0`, `1`, `2`, so every part
    /// is addressable — which turns a subcollection list into one `batchGet`.
    public func loadDeck(gameId: String) async throws -> [MedxDuelQuestion] {
        let token = try await AuthService.shared.getValidIdToken()
        // The part count is not known until the game document has been read, so it is read here
        // rather than threaded through: the deck is loaded once per room.
        let head = try await FirestoreService.shared.batchGet(
            paths: [(MedxDuelPath.games, gameId)],
            idToken: token
        )
        guard let fields = head[gameId],
              let game = MedxDuelCodec.game(id: gameId, fields: fields)
        else { throw URLError(.resourceUnavailable) }

        let parts = max(game.deckParts, 1)
        let documents = try await FirestoreService.shared.batchGet(
            paths: (0..<parts).map { (MedxDuelPath.deck(gameId), String($0)) },
            idToken: token
        )
        remoteWorks = true

        // Flattened in part order; a task-group or a dictionary would not preserve it, and the
        // shuffle that made this deck happened once at the deal.
        return (0..<parts).flatMap { part -> [MedxDuelQuestion] in
            guard let fields = documents[String(part)] else { return [] }
            return MedxDuelCodec.questions(from: fields)
        }
    }

    /// Every duel this profile was in, either side of it.
    ///
    /// Two queries rather than one `or`, merged here: `uid == me OR guestUid == me` is a
    /// disjunction Firestore would want an index for, and sorting on top of either filter would
    /// want another.
    public func listMyDuels(uid: String) async throws -> [MedxDuelGame] {
        let token = try await AuthService.shared.getValidIdToken()
        async let hostedTask = FirestoreService.shared.runRawQuery(
            collection: MedxDuelPath.games,
            whereField: "uid",
            equals: uid,
            idToken: token
        )
        async let joinedTask = FirestoreService.shared.runRawQuery(
            collection: MedxDuelPath.games,
            whereField: "guestUid",
            equals: uid,
            idToken: token
        )
        let merged = try await hostedTask + joinedTask
        remoteWorks = true

        var byId: [String: MedxDuelGame] = [:]
        for game in games(from: merged) {
            byId[game.id] = game
        }
        return byId.values.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Host: deal

    /// One commit, so the deck and the lobby become visible together — otherwise the guest could
    /// see a joinable game whose questions have not landed yet.
    ///
    /// The host gets a player document of its own for the same reason the guest does: it is the
    /// only place either of them may write an answer.
    public func createGame(
        hostUid: String,
        hostProfile: String,
        source: MedxDuelSource,
        deck: [MedxDuelQuestion],
        parts: [[MedxDuelQuestion]]
    ) async throws -> String {
        let token = try await AuthService.shared.getValidIdToken()
        let gameId = MedxDuelRules.newGameId()
        let now = MedxDuelCodec.stamp()

        var writes: [FirestoreService.MedxWrite] = parts.enumerated().map { index, questions in
            FirestoreService.MedxWrite(
                collection: MedxDuelPath.deck(gameId),
                docId: String(index),
                fields: MedxDuelCodec.deckFields(part: index, questions: questions)
            )
        }

        writes.append(
            FirestoreService.MedxWrite(
                collection: MedxDuelPath.games,
                docId: gameId,
                fields: [
                    "uid": hostUid,
                    "hostProfile": hostProfile,
                    "status": MedxDuelStatus.lobby.rawValue,
                    "source": MedxDuelCodec.sourceFields(source),
                    "total": deck.count,
                    "deckParts": parts.count,
                    "qIndex": 0,
                    "log": [Any](),
                    "createdAt": now,
                    "updatedAt": now
                ]
            )
        )

        writes.append(
            FirestoreService.MedxWrite(
                collection: MedxDuelPath.players,
                docId: MedxDuelPlayer.docId(gameId: gameId, uid: hostUid),
                fields: MedxDuelCodec.blankPlayer(gameId: gameId, uid: hostUid, profile: hostProfile)
            )
        )

        do {
            try await FirestoreService.shared.commit(writes: writes, idToken: token)
            remoteWorks = true
            return gameId
        } catch {
            remoteWorks = false
            throw error
        }
    }

    // MARK: - Guest: join
    //
    // Writing their own player document is the *whole* of joining. The host notices it arrive and
    // is the one that flips the game to live, because that field belongs to the host's document.

    public func joinGame(gameId: String, uid: String, profile: String) async throws {
        try await write(
            collection: MedxDuelPath.players,
            docId: MedxDuelPlayer.docId(gameId: gameId, uid: uid),
            fields: MedxDuelCodec.blankPlayer(gameId: gameId, uid: uid, profile: profile),
            merge: false
        )
    }

    // MARK: - Host: the game
    //
    // `askedAt` is always set one arming window into the future, which is what makes the 3-2-1 and
    // the question opening a single write: a future `askedAt` *is* the countdown, and the same
    // value is the start of the minute.

    public func startGame(gameId: String, guestUid: String, guestProfile: String) async throws {
        try await write(
            collection: MedxDuelPath.games,
            docId: gameId,
            fields: [
                "guestUid": guestUid,
                "guestProfile": guestProfile,
                "status": MedxDuelStatus.live.rawValue,
                "qIndex": 0,
                "askedAt": MedxDuelCodec.nowMillis() + MedxDuelRules.armWindow * 1000,
                "updatedAt": MedxDuelCodec.stamp()
            ],
            merge: true
        )
    }

    /// Close the round and open the next one.
    ///
    /// The log row goes in through an append transform rather than a spread, so if the host's
    /// advance fires twice for the same round — a re-render, a resumed app redelivering a
    /// snapshot — the second one is a no-op instead of a duplicate entry. The `qIndex` and
    /// `askedAt` writes are idempotent for the same reason.
    public func advance(gameId: String, row: MedxDuelLogRow, nextIndex: Int) async throws {
        let token = try await AuthService.shared.getValidIdToken()
        do {
            try await FirestoreService.shared.commit(
                writes: [
                    FirestoreService.MedxWrite(
                        collection: MedxDuelPath.games,
                        docId: gameId,
                        fields: [
                            "log": [MedxDuelCodec.logRowFields(row)],
                            "qIndex": nextIndex,
                            "askedAt": MedxDuelCodec.nowMillis() + MedxDuelRules.armWindow * 1000,
                            "updatedAt": MedxDuelCodec.stamp()
                        ],
                        appendPaths: ["log"],
                        merge: true
                    )
                ],
                idToken: token
            )
            remoteWorks = true
            poke()
        } catch {
            remoteWorks = false
            throw error
        }
    }

    public func finishGame(
        gameId: String,
        row: MedxDuelLogRow,
        scores: [String: MedxDuelScore]
    ) async throws {
        let token = try await AuthService.shared.getValidIdToken()
        let now = MedxDuelCodec.stamp()
        do {
            try await FirestoreService.shared.commit(
                writes: [
                    FirestoreService.MedxWrite(
                        collection: MedxDuelPath.games,
                        docId: gameId,
                        fields: [
                            "log": [MedxDuelCodec.logRowFields(row)],
                            "scores": MedxDuelCodec.scoreFields(scores),
                            "status": MedxDuelStatus.done.rawValue,
                            "finishedAt": now,
                            "updatedAt": now
                        ],
                        appendPaths: ["log"],
                        merge: true
                    )
                ],
                idToken: token
            )
            remoteWorks = true
            poke()
        } catch {
            remoteWorks = false
            throw error
        }
    }

    public func abandonGame(gameId: String) async throws {
        try await write(
            collection: MedxDuelPath.games,
            docId: gameId,
            fields: [
                "status": MedxDuelStatus.abandoned.rawValue,
                "updatedAt": MedxDuelCodec.stamp()
            ],
            merge: true
        )
    }

    // MARK: - Either: my own moves
    //
    // All three write one field of one document, the caller's own.

    public func submitAnswer(gameId: String, uid: String, round: MedxDuelRound) async throws {
        try await write(
            collection: MedxDuelPath.players,
            docId: MedxDuelPlayer.docId(gameId: gameId, uid: uid),
            fields: ["round": MedxDuelCodec.roundFields(round)],
            merge: true
        )
    }

    public func voteNext(gameId: String, uid: String, qIndex: Int) async throws {
        try await write(
            collection: MedxDuelPath.players,
            docId: MedxDuelPlayer.docId(gameId: gameId, uid: uid),
            fields: ["next": qIndex],
            merge: true
        )
    }

    public func leaveGame(gameId: String, uid: String) async throws {
        try await write(
            collection: MedxDuelPath.players,
            docId: MedxDuelPlayer.docId(gameId: gameId, uid: uid),
            fields: ["left": true, "leftAt": MedxDuelCodec.stamp()],
            merge: true
        )
    }

    /// Every write goes through here, so `remoteWorks` and the poke are in one place rather than
    /// remembered at nine call sites.
    private func write(
        collection: String,
        docId: String,
        fields: [String: Any],
        merge: Bool
    ) async throws {
        let token = try await AuthService.shared.getValidIdToken()
        do {
            try await FirestoreService.shared.writeDocument(
                collection: collection,
                docId: docId,
                fields: fields,
                merge: merge,
                idToken: token
            )
            remoteWorks = true
            poke()
        } catch {
            remoteWorks = false
            throw error
        }
    }
}
