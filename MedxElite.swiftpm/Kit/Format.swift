import Foundation

// MARK: - Dates

/// One parser for every timestamp the backend hands back.
///
/// Firestore's REST shape and the PWA's `toISOString()` both write RFC 3339, but one with
/// fractional seconds and one without, and a single `ISO8601DateFormatter` accepts exactly one
/// spelling. Four models each kept their own formatter and each silently answered `nil` for half
/// the rows — a sitting written by the PWA counted for nothing on Home, and a lobby it dealt never
/// went stale. Everything parses here now, and everything this app writes is stamped here too.
public enum MedxDates {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// RFC 3339 with or without fractional seconds; `nil` for anything else, including `nil`.
    public static func parse(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return fractional.date(from: value) ?? plain.date(from: value)
    }

    /// The spelling this app writes: RFC 3339, whole seconds, UTC.
    public static func stamp(_ date: Date = Date()) -> String {
        plain.string(from: date)
    }

    /// Whole calendar days from the start of today to the start of `date`, never negative.
    /// The one days-to-exam formula: Home, Profile, the widgets and Siri all read this.
    public static func daysUntil(_ date: Date, from now: Date = Date(), calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: date)
        return max(calendar.dateComponents([.day], from: today, to: target).day ?? 0, 0)
    }
}

// MARK: - Figures

/// Every figure the app prints goes through one door, so a screen cannot say "Zero KB" beside
/// "0 KB", or "in 0 seconds" under a sync that just happened.
public enum MedxFormat {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        // "0 KB", never "Zero KB".
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    public static func bytes(_ count: Int64) -> String {
        byteFormatter.string(fromByteCount: max(count, 0))
    }

    /// "Just now" inside a minute, then the system's abbreviated relative form; "Never" for `nil`.
    public static func relative(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Never" }
        if now.timeIntervalSince(date) < 60 { return "Just now" }
        return relativeFormatter.localizedString(for: date, relativeTo: now)
    }

    /// Grouped, in the current locale: 17,890.
    public static func count(_ value: Int) -> String {
        value.formatted(.number)
    }

    /// "1 day" / "21 days".
    public static func days(_ value: Int) -> String {
        value == 1 ? "1 day" : "\(count(value)) days"
    }

    /// "3 of 12", both grouped.
    public static func ratio(_ part: Int, of whole: Int) -> String {
        "\(count(part)) of \(count(whole))"
    }

    /// A clock reading: "07:12", or "1:07:12" past the hour.
    public static func clock(_ seconds: Int) -> String {
        let total = max(seconds, 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%02d:%02d", minutes, secs)
    }

    /// A duration in words: "2h 36m", "48m", "30s".
    public static func duration(_ seconds: Int) -> String {
        let total = max(seconds, 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(total)s"
    }

    /// A percentage of a whole, rounded; 0 when the whole is empty.
    public static func percent(_ part: Int, of whole: Int) -> Int {
        guard whole > 0 else { return 0 }
        return Int((Double(part) / Double(whole) * 100).rounded())
    }
}
