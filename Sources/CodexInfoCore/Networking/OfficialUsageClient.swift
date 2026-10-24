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
        let rateLimits = rateLimitsObject.flatMap(Self.decodeSnapshot)
        let byIDObject = object["rate_limits_by_limit_id"] as? [String: Any]
            ?? object["rateLimitsByLimitId"] as? [String: Any]
        var byID: [String: RateLimitSnapshot] = [:]
        for (key, value) in byIDObject ?? [:] {
            if let dict = value as? [String: Any], let snapshot = Self.decodeSnapshot(dict) {
                byID[key] = snapshot
            }
        }
        return OfficialUsage(planType: planType, rateLimits: rateLimits, rateLimitsByLimitID: byID)
    }

    private static func decodeSnapshot(_ object: [String: Any]) -> RateLimitSnapshot? {
        guard object["limit_id"] != nil || object["limitId"] != nil || object["primary"] != nil else { return nil }
        return RateLimitSnapshot(
            limitId: object["limit_id"] as? String ?? object["limitId"] as? String,
            primary: decodeWindow(object["primary"] as? [String: Any]),
            secondary: decodeWindow(object["secondary"] as? [String: Any]),
            planType: object["plan_type"] as? String ?? object["planType"] as? String
        )
    }

    private static func decodeWindow(_ object: [String: Any]?) -> RateLimitWindow? {
        guard let object else { return nil }
        guard let used = object["used_percent"] as? Double ?? (object["used_percent"] as? NSNumber)?.doubleValue else { return nil }
        let duration = (object["window_minutes"] as? NSNumber)?.doubleValue
            ?? (object["windowDurationMins"] as? NSNumber)?.doubleValue
        let resets = (object["resets_at"] as? NSNumber)?.intValue
            ?? (object["resetsAt"] as? NSNumber)?.intValue
        return RateLimitWindow(usedPercent: used, windowDurationMins: duration, resetsAt: resets)
    }
}
