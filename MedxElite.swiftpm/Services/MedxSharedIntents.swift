import Foundation
import AppIntents

// MARK: - Intents the Lock Screen can run
//
// Compiled into **both** the app and the `MedxWidgets` extension, because a button inside a Live
// Activity has to be declared where the activity is drawn — and, like `MedxSharedState.swift`, that
// means this file may import nothing app-specific.
//
// `LiveActivityIntent.perform()` runs in the *app's* process, not the extension's, so it could in
// principle reach straight into `VideoDownloadStore`. It deliberately does not: that type lives in
// `HLSProxyServer.swift`, which is app-only and could not compile here. Instead each intent posts a
// notification the download store observes, which keeps this file's dependencies at Foundation and
// puts the decision about what pausing *means* back where the downloader lives.
//
// `MedxAppIntents.swift` stays where it is — those are Siri shortcuts and are app-only by nature.

public extension Notification.Name {
    static let medxDownloadPauseRequested = Notification.Name("medx.download.pause")
    static let medxDownloadResumeRequested = Notification.Name("medx.download.resume")
    static let medxDownloadCancelRequested = Notification.Name("medx.download.cancel")
}

/// The key the download id travels under in those notifications' `userInfo`.
public enum MedxDownloadIntentKey {
    public static let videoId = "videoId"
}

@available(iOS 17.0, *)
public struct MedxPauseDownloadIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Pause download"
    public static var description = IntentDescription("Pauses a class that is downloading.")
    /// The activity is already on screen and the app has nothing to show for this — bringing it to
    /// the foreground for a pause would be the opposite of the point.
    public static var openAppWhenRun = false

    @Parameter(title: "Class")
    public var videoId: String

    public init() {}

    public init(videoId: String) {
        self.videoId = videoId
    }

    public func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .medxDownloadPauseRequested,
            object: nil,
            userInfo: [MedxDownloadIntentKey.videoId: videoId]
        )
        return .result()
    }
}

@available(iOS 17.0, *)
public struct MedxResumeDownloadIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Resume download"
    public static var description = IntentDescription("Resumes a paused class download.")
    public static var openAppWhenRun = false

    @Parameter(title: "Class")
    public var videoId: String

    public init() {}

    public init(videoId: String) {
        self.videoId = videoId
    }

    public func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .medxDownloadResumeRequested,
            object: nil,
            userInfo: [MedxDownloadIntentKey.videoId: videoId]
        )
        return .result()
    }
}

@available(iOS 17.0, *)
public struct MedxCancelDownloadIntent: LiveActivityIntent {
    public static var title: LocalizedStringResource = "Cancel download"
    public static var description = IntentDescription("Stops a class download and discards it.")
    public static var openAppWhenRun = false

    @Parameter(title: "Class")
    public var videoId: String

    public init() {}

    public init(videoId: String) {
        self.videoId = videoId
    }

    public func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .medxDownloadCancelRequested,
            object: nil,
            userInfo: [MedxDownloadIntentKey.videoId: videoId]
        )
        return .result()
    }
}
