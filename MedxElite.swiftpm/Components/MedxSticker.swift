import SwiftUI
import UIKit

// MARK: - Sticker art
//
// The 3D marks are Microsoft's Fluent Emoji (MIT), vendored from the PWA rather than
// fetched: art that needs a CDN is the wrong trade for an app whose whole premise is that
// it works with no signal, and 397 KB in the bundle buys a first paint with no network.
//
// They live as **data sets** inside `Assets.xcassets/Stickers`, not as an image set and not
// as a loose folder. An asset catalogue will not take WebP in an image set, and a folder
// reference would need its own pbxproj entry in one target and a `resources:` declaration
// in the other — a data set is handled by both toolchains already, and `UIImage(data:)`
// decodes WebP natively from iOS 14.

@MainActor
public enum MedxStickerStore {
    /// Decoded once per key. A screen like Home draws ten of these, and several redraw on
    /// every timer tick, so decoding in `body` was never an option.
    private static var cache: [String: UIImage] = [:]

    /// Unknown keys fall back to the brand sparkle, which is what stops a stale key —
    /// a subject icon picked in the PWA's admin console and later renamed — drawing a gap.
    public static func image(_ name: String) -> UIImage? {
        if let hit = cache[name] { return hit }
        guard let image = load(name) ?? load("sparkles") else { return nil }
        cache[name] = image
        return image
    }

    private static func load(_ name: String) -> UIImage? {
        guard let asset = NSDataAsset(name: "Stickers/\(name)") else { return nil }
        return UIImage(data: asset.data)
    }
}

/// One sticker. Always decorative — the label beside it carries the meaning, so this is
/// hidden from VoiceOver without exception.
public struct MedxSticker: View {
    private let name: String
    private let size: CGFloat
    private let tilt: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ name: String, size: CGFloat = 28, tilt: Double = 0) {
        self.name = name
        self.size = size
        self.tilt = tilt
    }
    public var body: some View {
        Group {
            if let image = MedxStickerStore.image(name) {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                // The bundle is missing the catalogue entirely — a build that skipped its
                // resources. A tinted glyph is better than an empty rectangle.
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.72))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(reduceMotion ? 0 : tilt))
        .accessibilityHidden(true)
    }
}

// MARK: - Subject → sticker

/// Which mark stands for a subject.
///
/// Matched case-insensitively on a substring, so this one table covers all three naming
/// schemes in the backend at once: the ARISE QBank's ("Community Medicine (PSM)"), the class
/// library's, and the tracker's own list.
public enum MedxSubjectArt {
    /// Order matters. `ortho` has to be tested before `paed`, because the British spelling
    /// "orthopaedics" contains "paed" — the other way round gave every Marrow orthopaedics
    /// paper a teddy bear.
    private static let rules: [(pattern: String, sticker: String)] = [
        ("anatom", "bone"),
        ("physio", "heart"),
        ("biochem", "testTube"),
        ("patho", "microscope"),
        ("microbio", "microbe"),
        ("pharma", "pill"),
        ("forensic|fmt|fsm", "skull"),
        ("psm|community|social.*prevent", "bars"),
        ("medicine", "stethoscope"),
        ("surg", "knife"),
        ("obg|obstet|gyn", "baby"),
        ("ortho", "crutch"),
        ("paed|pedia", "teddy"),
        ("ophthal|eye", "eyes"),
        ("ent|otorhino", "ear"),
        ("anaesth|anesth", "syringe"),
        ("derma|venereo|skin", "lotion"),
        ("psych", "thought"),
        ("radio", "radioactive"),
        ("dent", "tooth"),
        ("respir|pulmo", "lungs"),
        ("genetic|molecul", "dna"),
        ("skill|clinic", "bandage"),
    ]
    /// Compiled once. Twenty-three `NSRegularExpression`s rebuilt per row, on a list of
    /// 1,211 modules, is the kind of thing that shows up as a stutter while scrolling.
    private static let compiled: [(regex: NSRegularExpression, sticker: String)] = rules.compactMap {
        guard let regex = try? NSRegularExpression(pattern: $0.pattern, options: [.caseInsensitive]) else {
            return nil
        }
        return (regex, $0.sticker)
    }

    private static let fallbackPool = ["books", "bulb", "memo", "crystal", "atom", "sparkles"]

    public static func sticker(for subject: String?) -> String {
        let label = subject ?? ""
        let range = NSRange(label.startIndex..., in: label)
        for entry in compiled where entry.regex.firstMatch(in: label, options: [], range: range) != nil {
            return entry.sticker
        }
        // Deterministic, so the same unknown subject always looks the same rather than
        // changing mark between launches.
        var hash: UInt32 = 0
        for scalar in label.unicodeScalars {
            hash = hash &* 31 &+ (scalar.value & 0xFFFF)
        }
        return fallbackPool[Int(hash % UInt32(fallbackPool.count))]
    }
}
