import CoreGraphics
import Foundation

public struct FlashcardSubject: Identifiable, Hashable, Codable, Sendable {
    public var id: Int { subjectId }
    public let subjectId: Int
    public let name: String
    public let slug: String?
    public let cardCount: Int
    public let cards: [FlashcardCard]?

    enum CodingKeys: String, CodingKey {
        case id, subjectId, name, slug, cardCount, cards
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let sid = try? container.decode(Int.self, forKey: .subjectId) {
            subjectId = sid
        } else if let idVal = try? container.decode(Int.self, forKey: .id) {
            subjectId = idVal
        } else if let strId = try? container.decode(String.self, forKey: .subjectId), let sid = Int(strId) {
            subjectId = sid
        } else {
            subjectId = 0
        }
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        slug = try? container.decodeIfPresent(String.self, forKey: .slug)
        cardCount = (try? container.decodeIfPresent(Int.self, forKey: .cardCount)) ?? 0
        cards = try? container.decodeIfPresent([FlashcardCard].self, forKey: .cards)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(subjectId, forKey: .subjectId)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(slug, forKey: .slug)
        try container.encode(cardCount, forKey: .cardCount)
        try container.encodeIfPresent(cards, forKey: .cards)
    }

    public init(subjectId: Int, name: String, slug: String?, cardCount: Int, cards: [FlashcardCard]?) {
        self.subjectId = subjectId
        self.name = name
        self.slug = slug
        self.cardCount = cardCount
        self.cards = cards
    }
}

public struct FlashcardCard: Identifiable, Hashable, Codable, Sendable {
    public let id: Int
    public let name: String
    public let description: String?
    public let chapter: String?
    public let variants: FlashcardVariants?

    enum CodingKeys: String, CodingKey {
        case id, name, description, chapter, variants
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? container.decode(Int.self, forKey: .id) {
            id = intId
        } else if let strId = try? container.decode(String.self, forKey: .id), let intId = Int(strId) {
            id = intId
        } else {
            id = 0
        }
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? ""
        description = try? container.decodeIfPresent(String.self, forKey: .description)
        chapter = try? container.decodeIfPresent(String.self, forKey: .chapter)
        variants = try? container.decodeIfPresent(FlashcardVariants.self, forKey: .variants)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(chapter, forKey: .chapter)
        try container.encodeIfPresent(variants, forKey: .variants)
    }

    public init(id: Int, name: String, description: String? = nil, chapter: String? = nil, variants: FlashcardVariants? = nil) {
        self.id = id
        self.name = name
        self.description = description
        self.chapter = chapter
        self.variants = variants
    }
}

public struct FlashcardVariants: Hashable, Codable, Sendable {
    public let mobilePortrait: String?
    public let mobileLandscape: String?
    public let tabletPortrait: String?
    public let tabletLandscape: String?

    public var anyVariantUrl: String? {
        mobilePortrait ?? tabletPortrait ?? mobileLandscape ?? tabletLandscape
    }

    public func urlFor(device: FlashcardDevice, orientation: FlashcardOrientation) -> String? {
        switch (device, orientation) {
        case (.mobile, .portrait):
            return mobilePortrait ?? anyVariantUrl
        case (.mobile, .landscape):
            return mobileLandscape ?? anyVariantUrl
        case (.tablet, .portrait):
            return tabletPortrait ?? anyVariantUrl
        case (.tablet, .landscape):
            return tabletLandscape ?? anyVariantUrl
        }
    }

    /// Preferred artwork for the layout the app detected for itself.
    public func url(for layout: FlashcardLayout) -> String? {
        urlFor(device: layout.device, orientation: layout.orientation)
    }
}

public enum FlashcardDevice: String, CaseIterable, Identifiable, Sendable {
    case mobile = "Mobile"
    case tablet = "Tablet"
    public var id: String { rawValue }
}

public enum FlashcardOrientation: String, CaseIterable, Identifiable, Sendable {
    case portrait = "Portrait"
    case landscape = "Landscape"
    public var id: String { rawValue }
}

/// Which artwork a flashcard should use, worked out from the running device instead of
/// asking the student to pick Mobile/Tablet × Portrait/Landscape by hand.
public struct FlashcardLayout: Hashable, Sendable {
    public let device: FlashcardDevice
    public let orientation: FlashcardOrientation

    public init(device: FlashcardDevice, orientation: FlashcardOrientation) {
        self.device = device
        self.orientation = orientation
    }

    /// - Parameters:
    ///   - size: the space the cards are actually drawn in, so a rotation or a resized
    ///     Split View window re-reads as landscape/portrait on its own.
    ///   - isRegularWidth: an iPad squeezed into a compact column is served the phone
    ///     artwork, which is drawn for narrow layouts and stays legible.
    ///   - isPadIdiom: true on iPad hardware (including an iPad app on macOS/Vision).
    public static func detect(in size: CGSize, isRegularWidth: Bool, isPadIdiom: Bool) -> FlashcardLayout {
        FlashcardLayout(
            device: (isPadIdiom && isRegularWidth) ? .tablet : .mobile,
            orientation: size.width > size.height ? .landscape : .portrait
        )
    }

    /// Aspect ratio to reserve for a thumbnail before the image has loaded.
    public var aspectRatio: CGFloat {
        orientation == .landscape ? 4.0 / 3.0 : 3.0 / 4.0
    }

    public var iconName: String {
        switch (device, orientation) {
        case (.mobile, .portrait): return "iphone"
        case (.mobile, .landscape): return "iphone.landscape"
        case (.tablet, .portrait): return "ipad"
        case (.tablet, .landscape): return "ipad.landscape"
        }
    }

    /// Shown as a read-only hint — there is no picker to change it any more.
    public var label: String {
        "\(device.rawValue) · \(orientation.rawValue)"
    }
}

// MARK: - Artwork preference

/// Which artwork variant to draw. `auto` keeps the old device/window detection; the
/// explicit cases exist because the detection cannot know what the student wants — a
/// landscape card is often easier to read as landscape artwork rotated on a portrait
/// phone than as the phone-portrait crop.
public enum FlashcardArtworkPreference: String, CaseIterable, Identifiable, Sendable {
    case auto
    case phonePortrait
    case phoneLandscape
    case tabletPortrait
    case tabletLandscape

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .auto: return "Automatic"
        case .phonePortrait: return "Phone · Portrait"
        case .phoneLandscape: return "Phone · Landscape"
        case .tabletPortrait: return "Tablet · Portrait"
        case .tabletLandscape: return "Tablet · Landscape"
        }
    }

    public var iconName: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .phonePortrait: return "iphone"
        case .phoneLandscape: return "iphone.landscape"
        case .tabletPortrait: return "ipad"
        case .tabletLandscape: return "ipad.landscape"
        }
    }

    /// Resolves against what the app detected for the current window.
    public func layout(detected: FlashcardLayout) -> FlashcardLayout {
        switch self {
        case .auto: return detected
        case .phonePortrait: return FlashcardLayout(device: .mobile, orientation: .portrait)
        case .phoneLandscape: return FlashcardLayout(device: .mobile, orientation: .landscape)
        case .tabletPortrait: return FlashcardLayout(device: .tablet, orientation: .portrait)
        case .tabletLandscape: return FlashcardLayout(device: .tablet, orientation: .landscape)
        }
    }
}

/// One place for the flashcard viewing preferences so the contact sheet and the
/// full-screen viewer can never disagree about which artwork is on screen.
@MainActor
public final class FlashcardSettings: ObservableObject {
    public static let shared = FlashcardSettings()

    private static let artworkKey = "medx.flashcards.artwork"
    private static let rotationKey = "medx.flashcards.rotateLandscape"

    @Published public var artwork: FlashcardArtworkPreference {
        didSet { UserDefaults.standard.set(artwork.rawValue, forKey: Self.artworkKey) }
    }

    /// Rotates landscape artwork a quarter turn so it fills a portrait screen. Off by
    /// default — it is a reading aid, not the default presentation.
    @Published public var rotatesLandscapeArtwork: Bool {
        didSet { UserDefaults.standard.set(rotatesLandscapeArtwork, forKey: Self.rotationKey) }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.artworkKey) ?? ""
        artwork = FlashcardArtworkPreference(rawValue: raw) ?? .auto
        rotatesLandscapeArtwork = UserDefaults.standard.bool(forKey: Self.rotationKey)
    }
}
