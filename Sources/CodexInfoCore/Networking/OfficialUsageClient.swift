import Foundation

public struct OfficialUsage: Equatable, Sendable {
    public let planType: String?
    public let rateLimits: RateLimitSnapshot?
    public let rateLimitsByLimitID: [String: RateLimitSnapshot]
}

public enum OfficialUsageError: Error, Equatable {
    case unauthorized
    case httpStatus(Int)
    case invalidPayload
}

public struct OfficialUsageClient: Sendable {
    private let http: HTTPClient
    private let credentials: CredentialProviding
    private let baseURL: URL

    public init(http: HTTPClient, credentials: CredentialProviding, baseURL: URL = AppConstants.baseURL) {
        self.http = http
        self.credentials = credentials
        self.baseURL = baseURL
    }

    public func fetchUsage(now: Date = Date()) async throws -> OfficialUsage {
        let request = try authorizedRequest(path: "/wham/usage")
        let response = try await http.send(request)
        guard response.statusCode != 401, response.statusCode != 403 else { throw OfficialUsageError.unauthorized }
        guard (200..<300).contains(response.statusCode) else { throw OfficialUsageError.httpStatus(response.statusCode) }
        guard let object = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            throw OfficialUsageError.invalidPayload
        }
        return try Self.decodeUsage(object, now: now)
    }

    /// Fetches the official per-day token usage breakdown and returns the token
    /// count of the requested local day.
    ///
    /// The payload shape is not fully pinned down by the endpoint, so the decoding
    /// stays tolerant of the spellings that are known today: the rows may live under
    /// `days`, `data` or `breakdown`, the token count may be spelled `total_tokens`,
    /// `tokens` or `total`, and a summary payload may carry a top-level `total_tokens`.
    ///
    /// A payload that does not match any of those shapes is *not* reported as a zero:
    /// it throws `OfficialUsageError.invalidPayload` so the caller can fall back to the
    /// local numbers instead of publishing a misleading "0 tokens today".
    ///
    /// Rows carry the day they belong to. When at least one row carries a parseable
    /// `date`, only the rows of the requested day are summed; when no row carries a
    /// date, all rows are summed.
    public func fetchDailyTokenUsage(start: Date, end: Date, calendar: Calendar = .current) async throws -> Int {
        let formatter = Self.dayFormatter(calendar: calendar)
        let request = try authorizedRequest(
            path: "/wham/usage/daily-token-usage-breakdown",
            queryItems: [
                URLQueryItem(name: "start_date", value: formatter.string(from: start)),
                URLQueryItem(name: "end_date", value: formatter.string(from: end)),
                URLQueryItem(name: "group_by", value: "day"),
            ],
            extraHeaders: ["x-openai-codex-usage-categories": "1"]
        )
        let response = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else { throw OfficialUsageError.httpStatus(response.statusCode) }
        guard let root = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            throw OfficialUsageError.invalidPayload
        }
        return try Self.decodeDailyTokenTotal(root, targetDay: start, calendar: calendar, formatter: formatter)
    }

    /// Builds an authorized `GET` request for the given path.
    ///
    /// The token, `Accept`, `User-Agent` and the timeout are shared by every
    /// official endpoint, so the callers only add what is specific to them:
    /// query items and extra headers.
    private func authorizedRequest(
        path: String,
        queryItems: [URLQueryItem] = [],
        extraHeaders: [String: String] = [:]
    ) throws -> URLRequest {
        let token = try credentials.load().accessToken
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty { components.queryItems = queryItems }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
        for (name, value) in extraHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    static func decodeUsage(_ object: [String: Any], now: Date = Date()) throws -> OfficialUsage {
        let planType = object["plan_type"] as? String ?? object["planType"] as? String
        let rateLimitsObject = object["rate_limits"] as? [String: Any]
            ?? object["rateLimits"] as? [String: Any]
        // The official endpoint publishes one limit under `rate_limit` with
        // `primary_window`/`secondary_window`; the session log publishes
        // `rate_limits` with `primary`/`secondary`.
        let singularObject = object["rate_limit"] as? [String: Any]
            ?? object["rateLimit"] as? [String: Any]
        let rateLimits = rateLimitsObject.flatMap { RateLimitPayloadDecoder.snapshot(from: $0, now: now) }
            ?? singularObject.flatMap { RateLimitPayloadDecoder.snapshot(from: $0, now: now) }
        let byIDObject = object["rate_limits_by_limit_id"] as? [String: Any]
            ?? object["rateLimitsByLimitId"] as? [String: Any]
        let byID = byIDObject.map { RateLimitPayloadDecoder.snapshotMap(from: $0, now: now) } ?? [:]
        return OfficialUsage(planType: planType, rateLimits: rateLimits, rateLimitsByLimitID: byID)
    }

    // MARK: - Daily breakdown decoding

    /// Containers that are known to hold the rows of the daily breakdown.
    private static let breakdownRowKeys = ["days", "data", "breakdown"]

    /// Spellings that are known to hold the token count of a breakdown row.
    private static let breakdownTokenKeys = ["total_tokens", "tokens", "total"]

    /// A formatter that renders a day in the given calendar's time zone.
    static func dayFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        // The locale is set first: assigning it can re-derive the formatter's
        // calendar, so the calendar and the time zone are pinned afterwards.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    /// Sums the token counts of the breakdown rows that belong to `targetDay`.
    ///
    /// Throws `OfficialUsageError.invalidPayload` when the payload does not match a
    /// known shape. Only a recognized breakdown without usable rows reports zero.
    static func decodeDailyTokenTotal(
        _ root: [String: Any],
        targetDay: Date,
        calendar: Calendar,
        formatter: DateFormatter
    ) throws -> Int {
        for key in breakdownRowKeys {
            guard let container = root[key] else { continue }
            if container is NSNull {
                // A known container without rows is a recognized breakdown without usage.
                return 0
            }
            guard let rows = container as? [[String: Any]] else {
                // A known container with an unknown shape, e.g. a date keyed dictionary.
                throw OfficialUsageError.invalidPayload
            }
            return try total(for: rows, targetDay: targetDay, calendar: calendar, formatter: formatter)
        }
        if let summary = root["total_tokens"] {
            // A summary payload without rows carries the token count directly.
            guard let value = integer(summary) else { throw OfficialUsageError.invalidPayload }
            return value
        }
        throw OfficialUsageError.invalidPayload
    }

    /// Sums the token counts of the rows that belong to the requested day.
    ///
    /// When at least one row carries a parseable date, only the rows of the requested
    /// day are summed. When no row carries a date, every row is summed.
    private static func total(
        for rows: [[String: Any]],
        targetDay: Date,
        calendar: Calendar,
        formatter: DateFormatter
    ) throws -> Int {
        var interpreted: [(day: Date?, tokens: Int)] = []
        for row in rows {
            guard let tokens = try tokens(in: row) else {
                // A row without a known token spelling means the shape is unknown.
                throw OfficialUsageError.invalidPayload
            }
            interpreted.append((day: day(in: row, formatter: formatter), tokens: tokens))
        }
        let dated = interpreted.filter { $0.day != nil }
        let selected = dated.isEmpty
            ? interpreted
            : dated.filter { calendar.isDate($0.day!, inSameDayAs: targetDay) }
        return selected.reduce(0) { $0 + $1.tokens }
    }

    /// The token count of a row, or `nil` when the row carries no known spelling.
    private static func tokens(in row: [String: Any]) throws -> Int? {
        for key in breakdownTokenKeys {
            guard let value = row[key] else { continue }
            guard let count = integer(value) else {
                // The spelling is known but the value is not a number, e.g. "1234".
                throw OfficialUsageError.invalidPayload
            }
            return count
        }
        return nil
    }

    /// The day of a row, or `nil` when the row carries no parseable date.
    private static func day(in row: [String: Any], formatter: DateFormatter) -> Date? {
        guard let text = row["date"] as? String else { return nil }
        return formatter.date(from: text)
    }

    /// Reads a JSON number as an integer. Strings and booleans are not numbers.
    private static func integer(_ value: Any) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        // JSON booleans bridge to `NSNumber` as well, but they are not token counts.
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        return number.intValue
    }
}
