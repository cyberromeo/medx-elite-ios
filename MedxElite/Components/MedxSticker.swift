import Foundation

// MARK: - Subject → symbol
//
// The file name is historical: it used to hold the WebP sticker loader and the hue-washed
// symbol mark as well. The stickers went with the design that needed them — an icon tile is a
// `MedxSymbolTile` now — and the one thing every list still asks is which SF Symbol stands for a
// subject.

/// Which mark stands for a subject.
///
/// Matched case-insensitively on a substring, so this one table covers all three naming
/// schemes in the backend at once: the ARISE QBank's ("Community Medicine (PSM)"), the class
/// library's, and the tracker's own list.
public enum MedxSubjectArt {
    /// Order matters. `ortho` has to be tested before `paed`, because the British spelling
    /// "orthopaedics" contains "paed" — the other way round gave every Marrow orthopaedics
    /// paper a child's glyph.
    ///
    /// Where the SF library has no organ — anatomy, pathology, dermatology — the symbol is the
    /// *tool of the trade* rather than a near-miss glyph, because a wrong-organ icon reads as a
    /// mistake while an instrument reads as a category.
    private static let rules: [(pattern: String, symbol: String)] = [
        ("anatom", "figure.stand"),
        ("physio", "heart.fill"),
        ("biochem", "testtube.2"),
        ("patho", "microbe.fill"),
        ("microbio", "allergens"),
        ("pharma", "pills.fill"),
        ("forensic|fmt|fsm", "magnifyingglass.circle.fill"),
        ("psm|community|social.*prevent", "chart.bar.fill"),
        ("medicine", "stethoscope"),
        ("surg", "scissors"),
        ("obg|obstet|gyn", "figure.child"),
        ("ortho", "figure.walk"),
        ("paed|pedia", "figure.and.child.holdinghands"),
        ("ophthal|eye", "eye.fill"),
        ("ent|otorhino", "ear.fill"),
        ("anaesth|anesth", "syringe.fill"),
        ("derma|venereo|skin", "hand.raised.fill"),
        ("psych", "brain.head.profile"),
        ("radio", "waveform.path.ecg.rectangle"),
        ("dent", "mouth.fill"),
        ("respir|pulmo", "lungs.fill"),
        ("genetic|molecul", "atom"),
        ("skill|clinic", "cross.case.fill"),
    ]

    /// Compiled once. Twenty-three `NSRegularExpression`s rebuilt per row, on a list of
    /// 1,211 modules, is the kind of thing that shows up as a stutter while scrolling.
    private static let compiled: [(regex: NSRegularExpression, symbol: String)] = rules.compactMap {
        guard let regex = try? NSRegularExpression(pattern: $0.pattern, options: [.caseInsensitive]) else {
            return nil
        }
        return (regex, $0.symbol)
    }

    private static let fallbackSymbols = [
        "book.closed.fill", "lightbulb.fill", "text.book.closed.fill",
        "sparkles", "atom", "square.stack.3d.up.fill",
    ]

    /// The SF Symbol for a subject. Unknown subjects get one of six marks, picked by a hash of
    /// the name, so the same unknown subject always looks the same between launches.
    public static func symbol(for subject: String?) -> String {
        let label = subject ?? ""
        let range = NSRange(label.startIndex..., in: label)
        if let hit = compiled.first(where: { $0.regex.firstMatch(in: label, options: [], range: range) != nil }) {
            return hit.symbol
        }
        return fallbackSymbols[Int(fallbackIndex(label) % UInt32(fallbackSymbols.count))]
    }

    private static func fallbackIndex(_ label: String) -> UInt32 {
        var hash: UInt32 = 0
        for scalar in label.unicodeScalars {
            hash = hash &* 31 &+ (scalar.value & 0xFFFF)
        }
        return hash
    }
}
