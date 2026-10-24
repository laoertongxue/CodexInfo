import Foundation

public enum DateParsing {
    public static func iso8601(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    public static func epochSeconds(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: number.doubleValue)
    }

    /// Parses a date-only value such as `2026-10-24`.
    ///
    /// The reset sources publish the occurrence day without a time, so the day
    /// is read in the time zone the payload declares.
    public static func dateOnly(_ string: String?, timeZone: TimeZone? = nil) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }

    /// Parses an RFC 822 date such as `Sat, 17 Oct 2026 16:21:13 GMT`.
    ///
    /// The RSS feed publishes the publication time in this format. The zone is
    /// read from the string itself (`GMT`, `+0000` or a numeric offset) and
    /// only falls back to GMT when the string carries none.
    public static func rfc822(_ string: String?) -> Date? {
        guard let string else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.date(from: trimmed)
    }
}
