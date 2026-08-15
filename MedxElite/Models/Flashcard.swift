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
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        slug = try container.decodeIfPresent(String.self, forKey: .slug)
        cardCount = try container.decodeIfPresent(Int.self, forKey: .cardCount) ?? 0
        cards = try container.decodeIfPresent([FlashcardCard].self, forKey: .cards)
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
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        description = try container.decodeIfPresent(String.self, forKey: .description)
        chapter = try container.decodeIfPresent(String.self, forKey: .chapter)
        variants = try container.decodeIfPresent(FlashcardVariants.self, forKey: .variants)
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
