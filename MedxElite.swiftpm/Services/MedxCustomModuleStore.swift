import Foundation
import Combine

/// Custom modules — the list, the mirror, and the run.
///
/// Storage is deliberately belt-and-braces, exactly as the PWA describes it. Every change is
/// written to this device first so the list is instant and works offline, then mirrored to
/// `medx_custom_modules` so it reaches the other one. **The mirror is allowed to fail**: the
/// deployed Firestore rules cannot be changed from here, so if that collection is not writable
/// the feature still works — it just stays on the device, and the screen says so rather than
/// pretending it synced.
///
/// The list is shared. There are two people using this app and one bank behind it, so the
/// collection is read whole rather than filtered by author.
@MainActor
public final class MedxCustomModuleStore: ObservableObject {
    public static let shared = MedxCustomModuleStore()

    @Published public private(set) var modules: [MedxCustomModule] = []
    @Published public private(set) var isLoading = false
    /// `nil` = not tried yet, `true` = the mirror works, `false` = local only.
    @Published public private(set) var remoteWorks: Bool?
    /// Set when a delete could not reach Firestore and the row will therefore come back.
    @Published public var lastDeleteWarning: String?

    private var loadedFor: String?

    private init() {}

    // MARK: - Local cache
    //
    // Keyed by the signed-in uid, which makes the key "the shared list as this profile last saw
    // it" rather than "the papers this profile wrote".

    private func cacheKey(_ uid: String) -> String { "medx.custom.modules.\(uid)" }

    private func localList(_ uid: String) -> [MedxCustomModule] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(uid)),
              let decoded = try? JSONDecoder().decode([MedxCustomModule].self, from: data)
        else { return [] }
        return decoded
    }

    private func writeLocal(_ uid: String, _ list: [MedxCustomModule]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey(uid))
    }

    private func upsertLocal(_ uid: String, _ record: MedxCustomModule) {
        var list = localList(uid)
        if let index = list.firstIndex(where: { $0.id == record.id }) {
            list[index] = record
        } else {
            list.insert(record, at: 0)
        }
        writeLocal(uid, list)
    }

    // MARK: - Reads

    public func loadIfNeeded(uid: String?) async {
        guard let uid, loadedFor != uid else { return }
        await reload(uid: uid)
    }

    /// Both people's papers, newest first.
    ///
    /// The whole collection, not this profile's slice of it — that is the sharing. A refused or
    /// offline read falls back to this device's cache and claims nothing is synced unless the
    /// device has actually seen it land.
    public func reload(uid: String?) async {
        guard let uid else {
            modules = []
            return
        }
        isLoading = true
        defer { isLoading = false }

        let local = localList(uid)
        do {
            let token = try await AuthService.shared.getValidIdToken()
            let remote = try await FirestoreService.shared.fetchCustomModules(idToken: token)
            remoteWorks = true
            let merged = MedxCustomModuleRules.reconcile(
                remote: remote,
                local: local,
                // A REST read either answered or threw; there is no cached-answer case to be
                // unsure about, unlike the PWA's IndexedDB mirror. So a successful read *can*
                // prove a deletion, and purging on it is what makes a shared delete stick.
                authoritative: true
            )
            writeLocal(uid, merged)
            modules = merged
            loadedFor = uid
        } catch {
            remoteWorks = false
            modules = local
                .map { row -> MedxCustomModule in
                    var copy = row
                    copy.synced = row.synced == true
                    return copy
                }
                .sorted(by: MedxCustomModuleRules.byNewest)
            loadedFor = uid
        }
    }

    // MARK: - Writes

    /// Saves a paper and reports what actually landed.
    ///
    /// The creator is whoever built it, not whoever saved it last: either of them can edit
    /// either's paper, and the author pill on the card has to keep telling the truth.
    @discardableResult
    public func save(_ draft: MedxCustomModule, uid: String) async -> MedxCustomModule {
        var next = draft
        if next.uid.isEmpty { next.uid = uid }
        next.updatedAt = ISO8601DateFormatter().string(from: Date())
        if next.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            next.name = Self.defaultName()
        }

        // Local first, so the list is correct before the network is asked anything.
        var pending = next
        pending.synced = false
        upsertLocal(uid, pending)
        applyToPublished(pending)

        do {
            let token = try await AuthService.shared.getValidIdToken()
            try await FirestoreService.shared.saveCustomModule(next, idToken: token)
            remoteWorks = true
            var landed = next
            // Recorded as landed, which is what lets a later delete by the other one actually
            // stick instead of being resurrected as an unsynced local row.
            landed.synced = true
            upsertLocal(uid, landed)
            applyToPublished(landed)
            return landed
        } catch {
            remoteWorks = false
            return pending
        }
    }

    /// Delete, from both of them.
    ///
    /// The row goes locally either way. If Firestore refuses the delete, the mirror still has it
    /// and the next load brings it back — so that is said out loud now rather than letting the
    /// paper silently reappear later.
    public func delete(id: String, uid: String) async {
        let before = localList(uid)
        let gone = before.first { $0.id == id }
        writeLocal(uid, before.filter { $0.id != id })
        modules.removeAll { $0.id == id }
        lastDeleteWarning = nil

        do {
            let token = try await AuthService.shared.getValidIdToken()
            try await FirestoreService.shared.deleteCustomModule(id: id, idToken: token)
            remoteWorks = true
        } catch {
            remoteWorks = false
            if gone?.synced == true {
                lastDeleteWarning = "Deleted here, but Firestore would not take the change. "
                    + "It is still on the other device, so it will come back the next time this list loads."
            }
        }
    }

    private func applyToPublished(_ record: MedxCustomModule) {
        if let index = modules.firstIndex(where: { $0.id == record.id }) {
            modules[index] = record
        } else {
            modules.insert(record, at: 0)
        }
        modules.sort(by: MedxCustomModuleRules.byNewest)
    }

    private static func defaultName() -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return "Custom · " + formatter.string(from: Date())
    }

    // MARK: - Running one

    /// Which of a selection's modules a run actually has to read.
    ///
    /// The builder can put all 2,171 modules in a paper with one tap, and a capped paper does not
    /// need them: reading every module for a 40-question sitting is a whole day of the Firestore
    /// budget for 2% of the questions. Sources are shuffled first when the paper is shuffled, so
    /// the sample still spreads across the whole selection, then taken until they cover twice the
    /// cap — the margin absorbs a stale `questionCount` and any module retired since it was
    /// picked.
    static func sourcesForRun(_ module: MedxCustomModule) -> [MedxModuleSource] {
        let sources = module.sources
        guard let limit = module.limit, limit > 0, sources.count > 1 else { return sources }

        let order = module.shuffle ? sources.shuffled() : sources
        let want = limit * 2
        var take: [MedxModuleSource] = []
        var covered = 0
        for source in order {
            take.append(source)
            covered += source.questionCount
            if covered >= want { break }
        }
        return take
    }

    /// Turns a saved selection into a question list.
    ///
    /// Modules are fetched in parallel but a missing one is skipped rather than failing the run —
    /// a re-seed can retire a module id, and losing one chapter is better than losing the paper.
    /// Shuffling happens across the whole pool so a mixed module genuinely interleaves subjects
    /// instead of playing them in blocks.
    public func buildQuestions(
        for module: MedxCustomModule
    ) async -> (questions: [Question], missing: [MedxModuleSource]) {
        guard let token = try? await AuthService.shared.getValidIdToken() else {
            return ([], module.sources)
        }
        let sources = Self.sourcesForRun(module)

        var fetched: [String: [Question]] = [:]
        var missing: [MedxModuleSource] = []

        await withTaskGroup(of: (MedxModuleSource, [Question]?).self) { group in
            for source in sources {
                group.addTask {
                    let detail = try? await FirestoreService.shared.fetchQBankModule(
                        moduleId: source.moduleId,
                        idToken: token
                    )
                    return (source, detail?.questions)
                }
            }
            for await (source, questions) in group {
                guard let questions else {
                    missing.append(source)
                    continue
                }
                fetched[source.moduleId] = questions
            }
        }

        // Reassembled in the *selection's* order rather than the order the fetches happened to
        // finish in: an unshuffled paper is expected to play its chapters in the order they were
        // picked, and a task group answers whenever it likes.
        var pool: [Question] = []
        for source in sources {
            pool.append(contentsOf: fetched[source.moduleId] ?? [])
        }

        if module.shuffle {
            pool.shuffle()
        }
        if let limit = module.limit, limit > 0 {
            pool = Array(pool.prefix(limit))
        }
        return (pool, missing)
    }
}
