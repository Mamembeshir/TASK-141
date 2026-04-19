import Foundation

enum DateFormatters {

    /// MM/DD/YYYY — used for user-facing date display and input parsing.
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd/yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// MM/DD/YYYY h:mm a — 12-hour with AM/PM.
    static let shortDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd/yyyy h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// h:mm a — time only, 12-hour.
    static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// ISO 8601 — for HMAC payload construction and internal storage.
    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// ISO 8601 date-only — YYYY-MM-DD.
    static let iso8601DateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    /// Friendly relative time string ("2 min ago", "Yesterday", "Mar 15").
    static func relativeString(for date: Date) -> String {
        let now = Date()
        let diff = now.timeIntervalSince(date)

        if diff < 60 { return "Just now" }
        if diff < 3600 {
            let min = Int(diff / 60)
            return "\(min) min ago"
        }
        if diff < 86400 {
            let hr = Int(diff / 3600)
            return "\(hr) hr ago"
        }
        if diff < 172800 { return "Yesterday" }

        let f = DateFormatter()
        f.dateFormat = diff < 31_536_000 ? "MMM d" : "MMM d, yyyy"
        return f.string(from: date)
    }
}
