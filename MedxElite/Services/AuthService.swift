import Foundation
import Security
import Combine

public struct AuthSession: Codable, Sendable {
    public let idToken: String
    public let refreshToken: String
    public let uid: String
    public let email: String
    public let profileId: String
    public let expirationDate: Date
}

@MainActor
public final class AuthService: ObservableObject {
    public static let shared = AuthService()

    @Published public private(set) var currentSession: AuthSession?
    @Published public private(set) var currentProfile: Profile?
    @Published public private(set) var isAuthenticated = false
    @Published public private(set) var isBusy = false
    @Published public var errorMessage: String?

    private let sessionKey = "medx.auth.session"
    private let keychainService = "quest.srihari.medxelite.passwords"

    private init() {
        loadSavedSession()
    }

    public func hasSavedPassword(for profileId: String) -> Bool {
        return loadPasswordFromKeychain(profileId: profileId) != nil
    }

    public func forgetPassword(for profileId: String) {
        deletePasswordFromKeychain(profileId: profileId)
    }

    public func signIn(profile: Profile, password: String?) async throws {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        let pwd: String
        if let explicit = password, !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pwd = explicit
        } else if let saved = loadPasswordFromKeychain(profileId: profile.id) {
            pwd = saved
        } else {
            let err = NSError(domain: "AuthService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Password required"])
            errorMessage = "Please enter your password."
            throw err
        }

        let urlString = "\(FirebaseConfig.identityToolkitBase):signInWithPassword?key=\(FirebaseConfig.apiKey)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "email": profile.email,
            "password": pwd,
            "returnSecureToken": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if http.statusCode != 200 {
            let msg = parseAuthError(from: data)
            self.errorMessage = msg
            throw NSError(domain: "AuthService", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let idToken = json["idToken"] as? String,
              let refreshToken = json["refreshToken"] as? String,
              let localId = json["localId"] as? String else {
            throw URLError(.cannotParseResponse)
        }

        if localId != profile.uid {
            let mismatch = "Logged-in account does not match \(profile.displayName)."
            self.errorMessage = mismatch
            throw NSError(domain: "AuthService", code: 403, userInfo: [NSLocalizedDescriptionKey: mismatch])
        }

        let expiresInStr = json["expiresIn"] as? String ?? "3600"
        let expiresIn = TimeInterval(expiresInStr) ?? 3600
        let expirationDate = Date().addingTimeInterval(expiresIn - 60)

        let session = AuthSession(
            idToken: idToken,
            refreshToken: refreshToken,
            uid: localId,
            email: profile.email,
            profileId: profile.id,
            expirationDate: expirationDate
        )

        savePasswordToKeychain(profileId: profile.id, password: pwd)
        saveSession(session)

        self.currentSession = session
        self.currentProfile = profile
        self.isAuthenticated = true
    }

    public func getValidIdToken() async throws -> String {
        guard let session = currentSession else {
            throw NSError(domain: "AuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not authenticated"])
        }

        if session.expirationDate > Date() {
            return session.idToken
        }

        // Refresh token
        return try await refreshSession(session)
    }

    private func refreshSession(_ session: AuthSession) async throws -> String {
        let urlString = "\(FirebaseConfig.secureTokenBase)?key=\(FirebaseConfig.apiKey)"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let postString = "grant_type=refresh_token&refresh_token=\(session.refreshToken)"
        request.httpBody = postString.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            signOut()
            throw NSError(domain: "AuthService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Session expired. Please sign in again."])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newIdToken = json["id_token"] as? String,
              let newRefreshToken = json["refresh_token"] as? String,
              let expiresInStr = json["expires_in"] as? String,
              let expiresIn = TimeInterval(expiresInStr) else {
            throw URLError(.cannotParseResponse)
        }

        let newSession = AuthSession(
            idToken: newIdToken,
            refreshToken: newRefreshToken,
            uid: session.uid,
            email: session.email,
            profileId: session.profileId,
            expirationDate: Date().addingTimeInterval(expiresIn - 60)
        )

        saveSession(newSession)
        self.currentSession = newSession
        return newIdToken
    }

    public func signOut() {
        self.currentSession = nil
        self.currentProfile = nil
        self.isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

    // MARK: - Local Session Persistence

    private func saveSession(_ session: AuthSession) {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }

    private func loadSavedSession() {
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let session = try? JSONDecoder().decode(AuthSession.self, from: data) else {
            return
        }
        self.currentSession = session
        self.currentProfile = Profile.byId(session.profileId) ?? Profile.byUid(session.uid)
        self.isAuthenticated = true
    }

    // MARK: - Keychain Helpers

    private func savePasswordToKeychain(profileId: String, password: String) {
        guard let data = password.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: profileId,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadPasswordFromKeychain(profileId: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: profileId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    private func deletePasswordFromKeychain(profileId: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: profileId
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func parseAuthError(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorObj = json["error"] as? [String: Any],
           let message = errorObj["message"] as? String {
            switch message {
            case "INVALID_LOGIN_CREDENTIALS", "INVALID_PASSWORD", "EMAIL_NOT_FOUND":
                return "Incorrect password. Please try again."
            case "USER_DISABLED":
                return "This account has been disabled."
            case "TOO_MANY_ATTEMPTS_TRY_LATER":
                return "Too many attempts. Please try again later."
            default:
                return message.replacingOccurrences(of: "_", with: " ").capitalized
            }
        }
        return "Sign in failed. Please check your connection."
    }
}
