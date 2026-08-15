import SwiftUI

/// Profile model representing authorized Medx-elite users
public struct Profile: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let handle: String
    public let displayName: String
    public let email: String
    public let uid: String
    public let hexAccent: String
    public let gradientStart: String
    public let gradientEnd: String

    public var accentColor: Color {
        Color(hex: hexAccent)
    }

    public var gradient: LinearGradient {
        LinearGradient(
            colors: [Color(hex: gradientStart), Color(hex: gradientEnd)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public static let graveyard = Profile(
        id: "graveyard",
        handle: "Graveyard",
        displayName: "Mathu",
        email: "mathumithasweety123@gmail.com",
        uid: "EDf3H09qcpRYtaErh0PEmbY6SNE2",
        hexAccent: "#FF4D6D",
        gradientStart: "#FF5F8F",
        gradientEnd: "#B5179E"
    )

    public static let quantumGuy = Profile(
        id: "quantumguy",
        handle: "QuantumGuy",
        displayName: "Sri",
        email: "psrihari238@gmail.com",
        uid: "NpFFvozZSFWnCKdmutkISEGPf8o2",
        hexAccent: "#0A84FF",
        gradientStart: "#4FACFE",
        gradientEnd: "#4361EE"
    )

    public static let allProfiles: [Profile] = [.graveyard, .quantumGuy]

    public static func byId(_ id: String) -> Profile? {
        allProfiles.first { $0.id == id }
    }

    public static func byUid(_ uid: String) -> Profile? {
        allProfiles.first { $0.uid == uid }
    }
}
