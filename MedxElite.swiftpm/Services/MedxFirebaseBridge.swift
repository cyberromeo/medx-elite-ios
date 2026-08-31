import Foundation
import Combine

#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

/// The Firebase SDK, if this build has it.
///
/// Every other screen in this app talks to Firestore over plain REST with a hand-held ID token,
/// and that stays true: the SDK is here for exactly one feature, Faceoff, because a duel needs both
/// devices to see each other's moves within a second and REST has no equivalent of
/// `onSnapshot`.
///
/// Three consequences shape this file:
///
/// - **The SDK brings its own auth.** `Firestore` takes its credential from `FirebaseAuth`, not
///   from a token we hold, so signing in to the REST layer is not enough — the same email and
///   password have to go through `Auth.auth()` as well. That second sign-in is fire-and-forget: a
///   failure must never block the app, because everything except the duel runs on the REST path.
/// - **The SDK needs an *iOS* app registration.** `FirebaseConfig.appId` is the PWA's `:web:` one
///   and the SDK rejects it — by raising an `NSException`, which is not something a Swift `do/catch`
///   can absorb. So the app ID is checked against Firebase's own format rule *before* being handed
///   over, and an unusable one is a status line rather than a launch crash. See `iosAppId`.
/// - **The Playgrounds target has no package.** `MedxElite.swiftpm` cannot build
///   firebase-ios-sdk, so every SDK symbol in the project sits behind `canImport`, this type
///   compiles to an `isReady == false` stub there, and `MedxDuelTransportFactory` falls back to the
///   REST poller. Both copies of the file stay byte-identical, which is what the mirror requires.
///
/// `isReady` is `@Published` for one specific reason: it flips *late*. The SDK sign-in is
/// fire-and-forget from `AuthService`, so anything that asked "are we ready" during launch got
/// `false` and, when it cached that answer, was stuck with the poller for the life of the process.
/// `MedxLobbyWatcher` now subscribes to this instead and swaps its stream when the answer changes.
@MainActor
public final class MedxFirebaseBridge: ObservableObject {
    public static let shared = MedxFirebaseBridge()

    /// Whether the duel may use snapshot listeners. False in a build without the package, false
    /// while `FirebaseConfig.iosAppId` is unset, and false on a device where the SDK sign-in failed.
    @Published public private(set) var isReady = false

    /// One line for Settings ▸ Diagnostics, so "why is the duel slow" is answerable on a device.
    @Published public private(set) var status = "Not configured"

    private var isConfigured = false

    private init() {}

    /// Whether `FirebaseApp.configure` will accept this as a `GOOGLE_APP_ID`.
    ///
    /// A port of `+[FIRApp validateAppIDFormat:withVersion:]`, and it exists for one reason: that
    /// method's rejection path is an `NSException`, raised from `+[FIRApp addAppToAppDictionary:]`,
    /// and **Swift cannot catch an `NSException`**. There is no `try?` that makes `configure()`
    /// survive a bad value, so the only way this call can be the fire-and-forget thing the rest of
    /// this file promises is to never hand Firebase something it will refuse.
    ///
    /// The shape is `1:<project number>:ios:<hex>`. The platform segment has to be exactly `ios` —
    /// which is what a `:web:` app ID copied from the PWA's config fails, and that failure is a
    /// launch crash rather than a degraded feature.
    static func isAcceptableAppId(_ appId: String) -> Bool {
        let parts = appId.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        guard parts[0] == "1" else { return false }
        guard !parts[1].isEmpty, parts[1].allSatisfy({ $0.isNumber }) else { return false }
        guard parts[2] == "ios" else { return false }
        return !parts[3].isEmpty && parts[3].allSatisfy { $0.isHexDigit }
    }

    /// Built in code from `FirebaseConfig` rather than from a `GoogleService-Info.plist`, so the
    /// one source of truth about the backend stays `FirebaseConfig.swift` and there is no plist to
    /// fall out of step with it.
    ///
    /// Returns silently when there is nothing usable to configure with. That is a supported state,
    /// not an error path: `isReady` stays false, `MedxDuelTransportFactory` hands Faceoff the REST
    /// poller, and every other screen was on REST regardless.
    public func configure() {
        #if canImport(FirebaseCore)
        guard !isConfigured else { return }

        let appId = FirebaseConfig.iosAppId
        guard Self.isAcceptableAppId(appId) else {
            status = appId.isEmpty
                ? "No iOS app ID in FirebaseConfig — Faceoff polls instead"
                : "iOS app ID is not in Firebase's 1:…:ios:… form — Faceoff polls instead"
            return
        }

        let options = FirebaseOptions(
            googleAppID: appId,
            gcmSenderID: FirebaseConfig.messagingSenderId
        )
        options.apiKey = FirebaseConfig.apiKey
        options.projectID = FirebaseConfig.projectId
        options.storageBucket = FirebaseConfig.storageBucket

        if FirebaseApp.app() == nil {
            FirebaseApp.configure(options: options)
        }
        isConfigured = true
        status = "Configured, not signed in"
        #else
        status = "Built without the Firebase package — Faceoff polls instead"
        #endif
    }

    /// Signs the SDK in with the same credentials the REST layer just used.
    ///
    /// Deliberately never throws to the caller: the REST session is already good at this point, so
    /// a failure here costs the duel its listeners and nothing else.
    public func signIn(email: String, password: String) async {
        #if canImport(FirebaseAuth)
        configure()
        // `Auth.auth()` raises — again uncatchably — when there is no configured default app, so an
        // unusable app ID has to stop the chain here rather than one frame later.
        guard isConfigured else { return }
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            isReady = true
            status = "Signed in as \(result.user.uid)"
        } catch {
            isReady = false
            status = "SDK sign-in refused — Faceoff polls instead"
            print("[FirebaseBridge] SDK sign-in failed: \(error)")
        }
        #endif
    }

    public func signOut() {
        #if canImport(FirebaseAuth)
        if isConfigured {
            try? Auth.auth().signOut()
        }
        #endif
        isReady = false
        // Only overwritten when there is a configured app to describe. When `configure()` declined,
        // its reason is the one line Diagnostics has to explain itself with, so it is left standing.
        if isConfigured {
            status = "Configured, not signed in"
        }
    }
}
