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
///
/// Reach for this only where the picture *is* the content: a profile mark, an empty state, the
/// trophy at the end of a duel. Everything that is an **icon** — a row's mark, a card's mark, a
/// section heading, a tile in Library — is a `MedxSymbolMark` instead, because a symbol takes
/// the hue, tracks Dynamic Type and inherits the label's weight, and a 3D emoji does none of
/// those three things.
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
    ///
    /// The SF Symbol beside each sticker is what the app draws in chrome. Where the SF library
    /// has no organ — anatomy, pathology, dermatology — the symbol is the *tool of the trade*
    /// rather than a near-miss glyph, because a wrong-organ icon reads as a mistake while an
    /// instrument reads as a category.
    private static let rules: [(pattern: String, sticker: String, symbol: String)] = [
        ("anatom", "bone", "figure.stand"),
        ("physio", "heart", "heart.fill"),
        ("biochem", "testTube", "testtube.2"),
        ("patho", "microscope", "microbe.fill"),
        ("microbio", "microbe", "allergens"),
        ("pharma", "pill", "pills.fill"),
        ("forensic|fmt|fsm", "skull", "magnifyingglass.circle.fill"),
        ("psm|community|social.*prevent", "bars", "chart.bar.fill"),
        ("medicine", "stethoscope", "stethoscope"),
        ("surg", "knife", "scissors"),
        ("obg|obstet|gyn", "baby", "figure.child"),
        ("ortho", "crutch", "figure.walk"),
        ("paed|pedia", "teddy", "figure.and.child.holdinghands"),
        ("ophthal|eye", "eyes", "eye.fill"),
        ("ent|otorhino", "ear", "ear.fill"),
        ("anaesth|anesth", "syringe", "syringe.fill"),
        ("derma|venereo|skin", "lotion", "hand.raised.fill"),
        ("psych", "thought", "brain.head.profile"),
        ("radio", "radioactive", "waveform.path.ecg.rectangle"),
        ("dent", "tooth", "mouth.fill"),
        ("respir|pulmo", "lungs", "lungs.fill"),
        ("genetic|molecul", "dna", "atom"),
        ("skill|clinic", "bandage", "cross.case.fill"),
    ]
    /// Compiled once. Twenty-three `NSRegularExpression`s rebuilt per row, on a list of
    /// 1,211 modules, is the kind of thing that shows up as a stutter while scrolling.
    private static let compiled: [(regex: NSRegularExpression, sticker: String, symbol: String)] = rules.compactMap {
        guard let regex = try? NSRegularExpression(pattern: $0.pattern, options: [.caseInsensitive]) else {
            return nil
        }
        return (regex, $0.sticker, $0.symbol)
    }

    private static let fallbackPool = ["books", "bulb", "memo", "crystal", "atom", "sparkles"]
    private static let fallbackSymbols = [
        "book.closed.fill", "lightbulb.fill", "text.book.closed.fill",
        "sparkles", "atom", "square.stack.3d.up.fill",
    ]

    public static func sticker(for subject: String?) -> String {
        let label = subject ?? ""
        if let hit = match(label) { return hit.sticker }
        return fallbackPool[Int(fallbackIndex(label) % UInt32(fallbackPool.count))]
    }

    /// The SF Symbol for a subject, on the same table and the same fallback hash — so the
    /// symbol and the sticker for one subject always agree about which rule matched.
    public static func symbol(for subject: String?) -> String {
        let label = subject ?? ""
        if let hit = match(label) { return hit.symbol }
        return fallbackSymbols[Int(fallbackIndex(label) % UInt32(fallbackSymbols.count))]
    }

    /// First rule in table order that matches, and it stops there — the table is walked once
    /// per row on lists a thousand rows long.
    private static func match(_ label: String) -> (regex: NSRegularExpression, sticker: String, symbol: String)? {
        let range = NSRange(label.startIndex..., in: label)
        return compiled.first { $0.regex.firstMatch(in: label, options: [], range: range) != nil }
    }

    /// Deterministic, so the same unknown subject always looks the same rather than changing
    /// mark between launches.
    private static func fallbackIndex(_ label: String) -> UInt32 {
        var hash: UInt32 = 0
        for scalar in label.unicodeScalars {
            hash = hash &* 31 &+ (scalar.value & 0xFFFF)
        }
        return hash
    }
}

// MARK: - Symbol mark

/// An SF Symbol in a rounded, hue-washed square — the app's standard row and card icon.
///
/// This is the shape iOS itself uses wherever a list needs to be scannable by icon: Settings,
/// Shortcuts, Mail's mailbox list. It replaced a 3D sticker in every one of those positions
/// because a symbol inherits the label's weight, respects Dynamic Type, and can be told what
/// it means; the stickers stayed only where the picture *is* the content.
public struct MedxSymbolMark: View {
    private let symbol: String
    private let hue: Color
    private let size: CGFloat
    private let filled: Bool

    /// `filled` washes the square in the hue and inks the glyph in `onSoft`; otherwise the
    /// glyph alone carries the colour, which is what a dense list wants.
    public init(_ symbol: String, hue: Color, size: CGFloat = 36, filled: Bool = true) {
        self.symbol = symbol
        self.hue = hue
        self.size = size
        self.filled = filled
    }

    public var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(filled ? MedxCandy.onSoft(hue) : hue)
            .symbolRenderingMode(.hierarchical)
            .frame(width: size, height: size)
            .background {
                if filled {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .fill(hue.opacity(0.16))
                }
            }
            .accessibilityHidden(true)
    }
}
