import Foundation
import Combine

/// Finished sittings on their way to `medx_attempts`.
///
/// A sitting used to be posted once, at the moment it finished, and a failed post was dropped —
/// the comment said "kept locally" and nothing was. Modules are advertised as playable offline, so
/// a paper sat on a train showed its review and then never appeared in history, the streak or the
/// daily goal. Now every attempt is written here first, counted at once, and uploaded when it can
/// be: on enqueue, on every foreground, and before any screen reads attempts.
///
/// Idempotent by construction. The attempt carries its own document id — `att_<uuid>` for a
/// sitting, `duel_<gameId>_<uid>` for a faceoff — and the upload is a PATCH to that id, so a retry
/// after a lost response rewrites the same row rather than filing a second one. That is also what
/// stops a reopened faceoff filing its attempt again.
@MainActor
public final class MedxAttemptOutbox: ObservableObject {
    public static let shared = MedxAttemptOutbox()

    /// Rows waiting to land, for the profile they belong to.
    @Published public private(set) var pending: [SittingAttempt] = []

    private var inFlight: Set<String> = []
    private var loadedFor: String?

    private init() {}

    private func key(_ uid: String) -> String { "medx.attempts.outbox.\(uid)" }

    public static func newId() -> String {
        "att_" + UUID().uuidString.lowercased()
    }

    public static func duelId(gameId: String, uid: String) -> String {
        "duel_\(gameId)_\(uid)"
    }

    public func load(uid: String) {
        guard loadedFor != uid else { return }
        loadedFor = uid
        if let data = UserDefaults.standard.data(forKey: key(uid)),
           let rows = try? JSONDecoder().decode([SittingAttempt].self, from: data) {
            pending = rows
        } else {
            pending = []
        }
    }

    private func persist(uid: String) {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        UserDefaults.standard.set(data, forKey: key(uid))
    }

    /// Files a finished sitting: persisted first, counted at once, uploaded when it can be.
    @discardableResult
    public func enqueue(_ attempt: SittingAttempt) -> SittingAttempt {
        let row = (attempt.id?.isEmpty ?? true) ? attempt.withId(Self.newId()) : attempt
        guard !row.uid.isEmpty else { return row }
        load(uid: row.uid)
        pending.removeAll { $0.id == row.id }
        pending.append(row)
        persist(uid: row.uid)
        // The goal ring, the streak and the widgets move now, not after the next Home load.
        MedxStudyStatsStore.shared.record(row)
        Task { await flush(uid: row.uid) }
        return row
    }

    public func isPending(_ attempt: SittingAttempt) -> Bool {
        guard let id = attempt.id else { return false }
        return pending.contains { $0.id == id }
    }

    /// Uploads everything that is waiting. Safe to call often: a row is tried once at a time and a
    /// refusal simply leaves it for the next foreground or the next read.
    public func flush(uid: String) async {
        load(uid: uid)
        let rows = pending.filter { row in
            guard let id = row.id, row.uid == uid else { return false }
            return !inFlight.contains(id)
        }
        guard !rows.isEmpty, let token = try? await AuthService.shared.getValidIdToken() else { return }

        for row in rows {
            guard let id = row.id else { continue }
            inFlight.insert(id)
            defer { inFlight.remove(id) }
            do {
                try await FirestoreService.shared.saveAttempt(row, idToken: token)
                pending.removeAll { $0.id == id }
                persist(uid: uid)
            } catch {
                print("[AttemptOutbox] \(id) still waiting: \(error)")
            }
        }
    }

    /// Remote ∪ waiting, de-duplicated by id — the one list every screen should read.
    public func merged(remote: [SittingAttempt], uid: String) -> [SittingAttempt] {
        load(uid: uid)
        let remoteIds = Set(remote.compactMap(\.id))
        let waiting = pending.filter { row in
            guard row.uid == uid else { return false }
            guard let id = row.id else { return true }
            return !remoteIds.contains(id)
        }
        return remote + waiting
    }

    /// Sign-out forgets the in-memory view; the rows stay on disk under their own uid and are
    /// picked up again when that profile signs back in.
    public func reset() {
        pending = []
        inFlight = []
        loadedFor = nil
    }
}
