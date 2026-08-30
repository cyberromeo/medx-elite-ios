#if canImport(FirebaseFirestore)
import Foundation
import FirebaseFirestore

/// Faceoff over the Firebase SDK's snapshot listeners.
///
/// The whole reason the package is in this project. A move lands on the other device in a few
/// hundred milliseconds instead of up to a second, which on a sixty-second clock is the difference
/// between "we are playing the same game" and "my screen is behind".
///
/// It implements the same protocol as `MedxDuelRestTransport` and writes the identical documents,
/// so the two are interchangeable and a build without the package loses latency, not the feature.
/// The three write rules are unchanged and are not negotiable: nobody writes anybody else's
/// document, every query is a single equality filter, and nothing is read before auth resolves.
@MainActor
public final class MedxFirestoreDuelTransport: MedxDuelTransport {
    public private(set) var remoteWorks: Bool?

    private let db = Firestore.firestore()

    public init() {}

    /// A listener needs no hint about urgency — it is already a stream.
    public func setUrgency(_ phase: MedxDuelPhase) {}

    // MARK: - Streams

    /// One delivery per change, out of two listeners.
    ///
    /// The protocol hands the room over as a single snapshot because the poller can fetch all three
    /// documents in one request. Here they are genuinely two streams, so the latest of each is held
    /// and any arrival republishes the pair — which also means the first delivery does not have to
    /// wait for both.
    public func watchRoom(
        gameId: String,
        onChange: @escaping (MedxDuelRoomSnapshot) -> Void
    ) -> MedxDuelSubscription {
        var latestGame: MedxDuelGame?
        var latestPlayers: [MedxDuelPlayer] = []
        var sawGame = false

        func publish(failure: String? = nil) {
            onChange(
                MedxDuelRoomSnapshot(game: latestGame, players: latestPlayers, failure: failure)
            )
        }

        let gameListener = db.collection(MedxDuelPath.games).document(gameId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if error != nil {
                    self.remoteWorks = false
                    publish(failure: "Firestore would not read the duel documents.")
                    return
                }
                self.remoteWorks = true
                sawGame = true
                latestGame = snapshot?.data().flatMap { MedxDuelCodec.game(id: gameId, fields: $0) }
                publish()
            }

        let playerListener = db.collection(MedxDuelPath.players)
            .whereField("gameId", isEqualTo: gameId)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if error != nil {
                    self.remoteWorks = false
                    publish(failure: "Firestore would not read the duel documents.")
                    return
                }
                self.remoteWorks = true
                latestPlayers = (snapshot?.documents ?? []).compactMap {
                    MedxDuelCodec.player(fields: $0.data())
                }
                // Held back until the game has been seen once, or a room would flash "not found"
                // between the two first deliveries.
                if sawGame { publish() }
            }

        return MedxDuelSubscription {
            gameListener.remove()
            playerListener.remove()
        }
    }

    public func watchOpenLobbies(
        onChange: @escaping ([MedxDuelGame]) -> Void
    ) -> MedxDuelSubscription {
        let listener = db.collection(MedxDuelPath.games)
            .whereField("status", isEqualTo: MedxDuelStatus.lobby.rawValue)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if error != nil {
                    self.remoteWorks = false
                    onChange([])
                    return
                }
                self.remoteWorks = true
                onChange(
                    (snapshot?.documents ?? []).compactMap {
                        MedxDuelCodec.game(id: $0.documentID, fields: $0.data())
                    }
                )
            }
        return MedxDuelSubscription { listener.remove() }
    }

    // MARK: - Reads

    /// Chunked on the way in, so flattened on the way out — in part order, because the shuffle that
    /// made this deck happened once at the deal.
    public func loadDeck(gameId: String) async throws -> [MedxDuelQuestion] {
        let snapshot = try await db.collection(MedxDuelPath.games)
            .document(gameId)
            .collection("deck")
            .getDocuments()
        remoteWorks = true

        return snapshot.documents
            .sorted { (Int($0.documentID) ?? 0) < (Int($1.documentID) ?? 0) }
            .flatMap { MedxDuelCodec.questions(from: $0.data()) }
    }

    /// Two queries rather than one `or`, merged here: `uid == me OR guestUid == me` is a disjunction
    /// Firestore would want an index for, and sorting on top of either filter would want another.
    public func listMyDuels(uid: String) async throws -> [MedxDuelGame] {
        let games = db.collection(MedxDuelPath.games)
        async let hostedTask = games.whereField("uid", isEqualTo: uid).getDocuments()
        async let joinedTask = games.whereField("guestUid", isEqualTo: uid).getDocuments()
        let (hosted, joined) = try await (hostedTask, joinedTask)
        remoteWorks = true

        var byId: [String: MedxDuelGame] = [:]
        for document in hosted.documents + joined.documents {
            if let game = MedxDuelCodec.game(id: document.documentID, fields: document.data()) {
                byId[game.id] = game
            }
        }
        return byId.values.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Host: deal

    /// One batch, so the deck and the lobby become visible together — otherwise the guest could see
    /// a joinable game whose questions have not landed yet.
    public func createGame(
        hostUid: String,
        hostProfile: String,
        source: MedxDuelSource,
        deck: [MedxDuelQuestion],
        parts: [[MedxDuelQuestion]]
    ) async throws -> String {
        let gameId = MedxDuelRules.newGameId()
        let now = MedxDuelCodec.stamp()
        let batch = db.batch()
        let gameRef = db.collection(MedxDuelPath.games).document(gameId)

        for (index, questions) in parts.enumerated() {
            batch.setData(
                MedxDuelCodec.deckFields(part: index, questions: questions),
                forDocument: gameRef.collection("deck").document(String(index))
            )
        }

        batch.setData([
            "uid": hostUid,
            "hostProfile": hostProfile,
            "guestUid": NSNull(),
            "guestProfile": NSNull(),
            "status": MedxDuelStatus.lobby.rawValue,
            "source": MedxDuelCodec.sourceFields(source),
            "total": deck.count,
            "deckParts": parts.count,
            "qIndex": 0,
            "askedAt": NSNull(),
            "log": [Any](),
            "createdAt": now,
            "updatedAt": now
        ], forDocument: gameRef)

        // The host needs a player document for the same reason the guest does: it is the only place
        // either of them may write an answer.
        batch.setData(
            MedxDuelCodec.blankPlayer(gameId: gameId, uid: hostUid, profile: hostProfile),
            forDocument: db.collection(MedxDuelPath.players)
                .document(MedxDuelPlayer.docId(gameId: gameId, uid: hostUid))
        )

        do {
            try await batch.commit()
            remoteWorks = true
            return gameId
        } catch {
            remoteWorks = false
            throw error
        }
    }

    // MARK: - Writes

    public func joinGame(gameId: String, uid: String, profile: String) async throws {
        try await run {
            try await self.db.collection(MedxDuelPath.players)
                .document(MedxDuelPlayer.docId(gameId: gameId, uid: uid))
                .setData(MedxDuelCodec.blankPlayer(gameId: gameId, uid: uid, profile: profile))
        }
    }

    /// `askedAt` is always one arming window into the future, which is what makes the 3-2-1 and the
    /// question opening a single write.
    public func startGame(gameId: String, guestUid: String, guestProfile: String) async throws {
        try await run {
            try await self.game(gameId).updateData([
                "guestUid": guestUid,
                "guestProfile": guestProfile,
                "status": MedxDuelStatus.live.rawValue,
                "qIndex": 0,
                "askedAt": MedxDuelCodec.nowMillis() + MedxDuelRules.armWindow * 1000,
                "updatedAt": MedxDuelCodec.stamp()
            ])
        }
    }

    /// `arrayUnion` rather than a spread: it de-duplicates by deep equality, so a re-delivered
    /// snapshot firing the host's advance twice for the same round is a no-op instead of a duplicate
    /// log entry.
    public func advance(gameId: String, row: MedxDuelLogRow, nextIndex: Int) async throws {
        try await run {
            try await self.game(gameId).updateData([
                "log": FieldValue.arrayUnion([MedxDuelCodec.logRowFields(row)]),
                "qIndex": nextIndex,
                "askedAt": MedxDuelCodec.nowMillis() + MedxDuelRules.armWindow * 1000,
                "updatedAt": MedxDuelCodec.stamp()
            ])
        }
    }

    public func finishGame(
        gameId: String,
        row: MedxDuelLogRow,
        scores: [String: MedxDuelScore]
    ) async throws {
        let now = MedxDuelCodec.stamp()
        try await run {
            try await self.game(gameId).updateData([
                "log": FieldValue.arrayUnion([MedxDuelCodec.logRowFields(row)]),
                "scores": MedxDuelCodec.scoreFields(scores),
                "status": MedxDuelStatus.done.rawValue,
                "finishedAt": now,
                "updatedAt": now
            ])
        }
    }

    public func abandonGame(gameId: String) async throws {
        try await run {
            try await self.game(gameId).updateData([
                "status": MedxDuelStatus.abandoned.rawValue,
                "updatedAt": MedxDuelCodec.stamp()
            ])
        }
    }

    public func submitAnswer(gameId: String, uid: String, round: MedxDuelRound) async throws {
        try await run {
            try await self.player(gameId, uid).updateData([
                "round": MedxDuelCodec.roundFields(round)
            ])
        }
    }

    public func voteNext(gameId: String, uid: String, qIndex: Int) async throws {
        try await run {
            try await self.player(gameId, uid).updateData(["next": qIndex])
        }
    }

    public func leaveGame(gameId: String, uid: String) async throws {
        try await run {
            try await self.player(gameId, uid).updateData([
                "left": true,
                "leftAt": MedxDuelCodec.stamp()
            ])
        }
    }

    // MARK: - Plumbing

    private func game(_ gameId: String) -> DocumentReference {
        db.collection(MedxDuelPath.games).document(gameId)
    }

    private func player(_ gameId: String, _ uid: String) -> DocumentReference {
        db.collection(MedxDuelPath.players).document(MedxDuelPlayer.docId(gameId: gameId, uid: uid))
    }

    /// Every write goes through here, so `remoteWorks` is set in one place rather than remembered
    /// at nine call sites — the lobby's "Firestore would not take the duel collections" line is only
    /// honest if nothing forgets to record a refusal.
    private func run(_ body: () async throws -> Void) async throws {
        do {
            try await body()
            remoteWorks = true
        } catch {
            remoteWorks = false
            throw error
        }
    }
}
#endif
