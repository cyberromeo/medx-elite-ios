import SwiftUI
import UIKit

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

    /// One or two letters used when no profile picture has been set.
    public var initials: String {
        let words = displayName
            .split(separator: " ")
            .compactMap { $0.first }
            .prefix(2)
        let letters = String(words).uppercased()
        return letters.isEmpty ? "?" : letters
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

// MARK: - Profile Pictures

/// Stores a locally chosen profile picture per profile on disk, so the avatar
/// survives relaunches without needing a backend field.
@MainActor
public final class AvatarStore: ObservableObject {
    public static let shared = AvatarStore()

    /// Keyed by `Profile.id`. Published so every avatar on screen refreshes at once.
    @Published public private(set) var images: [String: UIImage] = [:]

    private let fileManager = FileManager.default
    private let directory: URL

    private init() {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var folder = base.appendingPathComponent("Avatars", isDirectory: true)
        if !fileManager.fileExists(atPath: folder.path) {
            try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        self.directory = folder
        loadFromDisk()
    }

    public func image(for profileId: String) -> UIImage? {
        images[profileId]
    }

    public func hasImage(for profileId: String) -> Bool {
        images[profileId] != nil
    }

    /// Accepts raw picker data, downsizes it, then stores it as JPEG.
    public func setImage(data: Data, for profileId: String) {
        guard let picked = UIImage(data: data) else { return }
        let resized = Self.downsized(picked)
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return }
        try? jpeg.write(to: fileURL(for: profileId), options: .atomic)
        images[profileId] = resized
    }

    public func removeImage(for profileId: String) {
        try? fileManager.removeItem(at: fileURL(for: profileId))
        images[profileId] = nil
    }

    private func fileURL(for profileId: String) -> URL {
        directory.appendingPathComponent("\(profileId).jpg")
    }

    private func loadFromDisk() {
        var loaded: [String: UIImage] = [:]
        for profile in Profile.allProfiles {
            let url = fileURL(for: profile.id)
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                loaded[profile.id] = image
            }
        }
        images = loaded
    }

    private static func downsized(_ image: UIImage, maxDimension: CGFloat = 512) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
