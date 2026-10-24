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

    public func fetchUsage() async throws -> OfficialUsage {
        let request = try authorizedRequest(path: "/wham/usage")
        let response = try await http.send(request)
        guard response.statusCode != 401, response.statusCode != 403 else { throw OfficialUsageError.unauthorized }
        guard (200..<300).contains(response.statusCode) else { throw OfficialUsageError.httpStatus(response.statusCode) }
        guard let object = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            throw OfficialUsageError.invalidPayload
        }
        return try Self.decodeUsage(object)
    }

    /// Fetches the official per-day token usage breakdown and returns the summed
    /// token count for the requested range.
    ///
    /// The payload shape is not fully pinned down by the endpoint, so the decoding
    /// stays tolerant: the rows may live under `days`, `data` or `breakdown`, and the
    /// token count may be spelled `total_tokens`, `tokens` or `total`.
    public func fetchDailyTokenUsage(start: Date, end: Date, calendar: Calendar = .current) async throws -> Int {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        var components = URLComponents(url: baseURL.appendingPathComponent("/wham/usage/daily-token-usage-breakdown"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "start_date", value: formatter.string(from: start)),
            URLQueryItem(name: "end_date", value: formatter.string(from: end)),
            URLQueryItem(name: "group_by", value: "day"),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(try credentials.load().accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "x-openai-codex-usage-categories")
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
        let response = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else { throw OfficialUsageError.httpStatus(response.statusCode) }
        guard let root = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            throw OfficialUsageError.invalidPayload
        }
        let rows = (root["days"] as? [[String: Any]])
            ?? (root["data"] as? [[String: Any]])
            ?? (root["breakdown"] as? [[String: Any]])
            ?? []
        let values = rows.compactMap { row -> Int? in
            (row["total_tokens"] as? NSNumber)?.intValue
                ?? (row["tokens"] as? NSNumber)?.intValue
                ?? (row["total"] as? NSNumber)?.intValue
        }
        if !values.isEmpty { return values.reduce(0, +) }
        return (root["total_tokens"] as? NSNumber)?.intValue ?? 0
    }

    private func authorizedRequest(path: String) throws -> URLRequest {
        let token = try credentials.load().accessToken
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    static func decodeUsage(_ object: [String: Any]) throws -> OfficialUsage {
        let planType = object["plan_type"] as? String ?? object["planType"] as? String
        let rateLimitsObject = object["rate_limits"] as? [String: Any]
            ?? object["rateLimits"] as? [String: Any]
        let rateLimits = rateLimitsObject.flatMap(RateLimitPayloadDecoder.snapshot)
        let byIDObject = object["rate_limits_by_limit_id"] as? [String: Any]
            ?? object["rateLimitsByLimitId"] as? [String: Any]
        let byID = byIDObject.map(RateLimitPayloadDecoder.snapshotMap) ?? [:]
        return OfficialUsage(planType: planType, rateLimits: rateLimits, rateLimitsByLimitID: byID)
    }
}
