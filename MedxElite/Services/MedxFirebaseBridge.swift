import Foundation

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
/// Two consequences shape this file:
///
/// - **The SDK brings its own auth.** `Firestore` takes its credential from `FirebaseAuth`, not
///   from a token we hold, so signing in to the REST layer is not enough — the same email and
///   password have to go through `Auth.auth()` as well. That second sign-in is fire-and-forget: a
///   failure must never block the app, because everything except the duel runs on the REST path.
/// - **The Playgrounds target has no package.** `MedxElite.swiftpm` cannot build
///   firebase-ios-sdk, so every SDK symbol in the project sits behind `canImport`, this type
///   compiles to an `isReady == false` stub there, and `MedxDuelTransportFactory` falls back to the
///   REST poller. Both copies of the file stay byte-identical, which is what the mirror requires.
@MainActor
public final class MedxFirebaseBridge {
    public static let shared = MedxFirebaseBridge()

    /// Whether the duel may use snapshot listeners. False in a build without the package, and false
    /// on a device where configure or the SDK sign-in failed.
    public private(set) var isReady = false

    /// One line for Settings ▸ Diagnostics, so "why is the duel slow" is answerable on a device.
    public private(set) var status = "Not configured"

    private var isConfigured = false

    private init() {}

    /// Built in code from `FirebaseConfig` rather than from a `GoogleService-Info.plist`, so the
    /// one source of truth about the backend stays `FirebaseConfig.swift` and there is no plist to
    /// fall out of step with it.
    public func configure() {
        #if canImport(FirebaseCore)
        guard !isConfigured else { return }
        isConfigured = true

        let options = FirebaseOptions(
            googleAppID: FirebaseConfig.appId,
            gcmSenderID: FirebaseConfig.messagingSenderId
        )
        options.apiKey = FirebaseConfig.apiKey
        options.projectID = FirebaseConfig.projectId
        options.storageBucket = FirebaseConfig.storageBucket

        if FirebaseApp.app() == nil {
            FirebaseApp.configure(options: options)
        }
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
        try? Auth.auth().signOut()
        #endif
        isReady = false
        status = isConfigured ? "Configured, not signed in" : "Not configured"
    }
}
