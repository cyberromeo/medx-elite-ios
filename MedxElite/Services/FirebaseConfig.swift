import Foundation

public enum FirebaseConfig {
    public static let apiKey = "AIzaSyCkuExDptljH-kIN555APSeaRboZw06Vaw"
    public static let projectId = "medx-e9acd"
    public static let authDomain = "medx-e9acd.firebaseapp.com"
    public static let storageBucket = "medx-e9acd.firebasestorage.app"
    /// The **web** app registration — the one the PWA runs on. Kept because it is part of what this
    /// file is for, but it is not usable by the Firebase iOS SDK: see `iosAppId`.
    public static let appId = "1:300960747898:web:c8ad40db21d815a6a946c3"

    /// The **iOS** app registration, and the only app ID `FirebaseApp.configure` will accept.
    ///
    /// A Firebase app ID names one *registration* inside a project, not the project, and the SDK
    /// checks the platform segment: `+[FIRApp validateAppIDFormat:withVersion:]` requires it to be
    /// literally `ios`. Handing it `appId` above — the `:web:` one — makes it raise an `NSException`
    /// that Swift cannot catch, which terminates the app during launch.
    ///
    /// Empty until an iOS app exists in the project. To create it, in the Firebase console for
    /// `medx-e9acd`: Project settings ▸ Your apps ▸ Add app ▸ iOS, bundle ID
    /// `quest.srihari.medxelite`. The console then shows an App ID of the form
    /// `1:300960747898:ios:<hex>` — paste it here. No `GoogleService-Info.plist` download is needed;
    /// `MedxFirebaseBridge` builds `FirebaseOptions` from these constants.
    ///
    /// While this is empty the app is fully functional: Faceoff uses `MedxDuelRestTransport`, which
    /// polls instead of listening. Settings ▸ Diagnostics ▸ Faceoff transport says which is live.
    public static let iosAppId = ""

    /// Needed only by `MedxFirebaseBridge`, which builds `FirebaseOptions` in code rather than
    /// from a `GoogleService-Info.plist` — so this file stays the one source of backend truth.
    public static let messagingSenderId = "300960747898"

    public static let firestoreRestBase = "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents"
    public static let identityToolkitBase = "https://identitytoolkit.googleapis.com/v1/accounts"
    public static let secureTokenBase = "https://securetoken.googleapis.com/v1/token"

    public static let imageCdnBase = "https://cdn.jsdelivr.net/gh/cyberromeo/img@main"
    public static let flashcardCdnBase = "https://d2vhwjmp3pf4cn.cloudfront.net"
    public static let backgroundVideoUrl = "https://d8j0ntlcm91z4.cloudfront.net/user_38xzZboKViGWJOttwIXH07lWA1P/hf_20260429_115139_0fc6bd3d-3631-4d26-ab9b-28293887dcc9.mp4"
}
