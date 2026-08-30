import Foundation
import Combine
import BackgroundTasks
import UserNotifications

/// Notices when something new lands in the ARISE VOD bucket, and says so.
///
/// There is no push. This app has no server to send from and a sideloaded free-account build
/// cannot carry an APNs entitlement anyway, so the signal is pulled: one read of
/// `medx_vod/_meta` — a single document carrying `lastUploadedAt` — compared against a stored
/// watermark. Nothing else is fetched unless that watermark has actually moved.
///
/// It runs from two places, and the difference matters:
///
/// - **Foreground**, on every launch and every return from background. This is the guarantee.
/// - **A `BGAppRefreshTask`**, roughly every two hours when iOS feels like it. This is the
///   bonus, and it is genuinely opportunistic — iOS may not run it for days on a device that
///   is rarely charged. The Settings row says exactly that rather than implying push.
@MainActor
public final class MedxVodWatcher: ObservableObject {
    public static let shared = MedxVodWatcher()

    /// Recordings uploaded since the feed was last opened. Drives the badge on the Library row.
    @Published public private(set) var unseenCount = 0
    @Published public private(set) var meta: MedxVodMeta?
    @Published public private(set) var lastCheckedAt: Date?

    /// Kept `nonisolated` so `registerBackgroundTask()` and `Info.plist` can be checked against
    /// each other from a launch-time context.
    nonisolated public static let taskIdentifier = "quest.srihari.medxelite.vodcheck"


    private static let seenKey = "medx.vod.seenUploadedAt"
    private static let notifiedKey = "medx.vod.notifiedUploadedAt"

    private var isChecking = false

    private init() {}

    // MARK: - Watermarks

    /// The newest upload the feed has been *shown*. Stored as the raw Firestore timestamp string
    /// so it compares byte-for-byte with the cursor and never loses sub-second precision.
    public var seenWatermark: String? {
        UserDefaults.standard.string(forKey: Self.seenKey)
    }

    /// The newest upload a notification has already been posted for, kept apart from `seen`:
    /// being told about a drop and having looked at it are different things, and conflating them
    /// meant a notification tapped-but-not-scrolled re-notified on the next wake.
    private var notifiedWatermark: String? {
        UserDefaults.standard.string(forKey: Self.notifiedKey)
    }

    /// Called by the feed once its first page has landed. Newest wins, and it never goes
    /// backwards — an offline page served from an older read must not un-see a drop.
    public func markSeen(newestUploadedAt raw: String?) {
        guard let raw else { return }
        if let current = seenWatermark, current >= raw { return }
        UserDefaults.standard.set(raw, forKey: Self.seenKey)
        unseenCount = 0
    }

    /// Only for Settings ▸ Diagnostics, so the notification can be exercised on a device without
    /// waiting for the bucket to actually move.
    public func resetWatermarks() {
        UserDefaults.standard.removeObject(forKey: Self.seenKey)
        UserDefaults.standard.removeObject(forKey: Self.notifiedKey)
        unseenCount = 0
    }

    // MARK: - The check

    @discardableResult
    public func refreshFromForeground() async -> Int {
        await check(postNotification: MedxNotificationManager.shared.enabled.contains(.vodDrops))
    }

    /// One `_meta` read, then a page only if it moved.
    ///
    /// Returns how many new recordings were found, which is what the background task reports as
    /// its completion result.
    @discardableResult
    public func check(postNotification: Bool) async -> Int {
        guard !isChecking, AuthService.shared.currentSession != nil else { return 0 }
        isChecking = true
        defer {
            isChecking = false
            lastCheckedAt = Date()
        }

        guard let token = try? await AuthService.shared.getValidIdToken() else { return 0 }
        guard let latest = try? await FirestoreService.shared.fetchVodMeta(idToken: token) else {
            return 0
        }
        meta = latest

        guard let newest = latest.lastUploadedAtRaw else { return 0 }
        // Nothing has moved since this device last looked at the feed.
        if let seen = seenWatermark, newest <= seen {
            unseenCount = 0
            return 0
        }

        // The watermark moved, so it is worth one page to find out by how much and what the
        // newest one is called. Twelve is enough for a headline and a count; nobody needs the
        // exact number when it is thirty.
        let page = try? await FirestoreService.shared.fetchVodPage(
            pageSize: 12,
            cursor: nil,
            idToken: token
        )
        let fresh = (page?.items ?? []).filter { item in
            guard let raw = item.uploadedAtRaw else { return false }
            guard let seen = seenWatermark else { return true }
            return raw > seen
        }
        unseenCount = fresh.count

        guard postNotification, !fresh.isEmpty else { return fresh.count }
        // Already announced. Being told twice about the same drop is worse than not being told.
        if let notified = notifiedWatermark, newest <= notified { return fresh.count }

        UserDefaults.standard.set(newest, forKey: Self.notifiedKey)
        await MedxNotificationManager.shared.postVodDrop(items: fresh)
        return fresh.count
    }

    // MARK: - Background refresh

    /// Registered once, during launch, and **before** the app finishes launching — a
    /// `BGTaskScheduler` registration after that point traps. The identifier must also appear in
    /// `Info.plist` under `BGTaskSchedulerPermittedIdentifiers`, or the registration itself traps.
    ///
    /// `nonisolated static` on purpose: the only place it can legally be called from is
    /// `MedxEliteApp.init()`, which is not on the main actor. `BGTaskScheduler` is safe to touch
    /// from anywhere, and the handler hops to the main actor itself.
    nonisolated public static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await MedxVodWatcher.shared.handle(refresh)
            }
        }
    }

    private func handle(_ task: BGAppRefreshTask) async {
        // Re-armed first. A task that finishes without scheduling its successor is a feature
        // that works exactly once.
        scheduleBackgroundCheck()

        let work = Task { await check(postNotification: MedxNotificationManager.shared.enabled.contains(.vodDrops)) }
        task.expirationHandler = { work.cancel() }
        _ = await work.value
        task.setTaskCompleted(success: true)
    }

    /// Two hours is the floor, not a promise: iOS decides, and on a device that is rarely
    /// charged it may decide "never". Asking for anything shorter only wastes the budget.
    public func scheduleBackgroundCheck() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(2 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Simulator, or a build without the background mode. The foreground check still runs.
            print("[VodWatcher] background submit refused: \(error)")
        }
    }
}
