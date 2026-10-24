import Foundation

public protocol ResetCreditsProviding: Sendable {
    func creditsSnapshot(now: Date) async -> ResetCreditsSnapshot?
}

public protocol ResetCreditFallbackProviding: Sendable {
    func fallbackCredits(now: Date) async -> ResetCreditsSnapshot?
}

public struct OfficialResetCreditsClient: Sendable {
    private let http: HTTPClient
    private let credentials: CredentialProviding
    private let baseURL: URL

    public init(http: HTTPClient, credentials: CredentialProviding, baseURL: URL = AppConstants.baseURL) {
        self.http = http
        self.credentials = credentials
        self.baseURL = baseURL
    }

    public func fetch(now: Date = Date()) async throws -> ResetCreditsSnapshot {
        let token = try credentials.load().accessToken
        var request = URLRequest(url: baseURL.appendingPathComponent("/wham/rate-limit-reset-credits"))
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")

        let response = try await http.send(request)
        guard response.statusCode != 401, response.statusCode != 403 else { throw OfficialUsageError.unauthorized }
        guard (200..<300).contains(response.statusCode) else { throw OfficialUsageError.httpStatus(response.statusCode) }
        guard let root = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            throw OfficialUsageError.invalidPayload
        }

        let credits = (root["credits"] as? [[String: Any]] ?? []).compactMap { item -> ResetCredit? in
            guard let id = item["id"] as? String, let status = item["status"] as? String else { return nil }
            return ResetCredit(
                id: id,
                status: status,
                grantedAt: DateParsing.iso8601(item["granted_at"] as? String) ?? DateParsing.epochSeconds(item["granted_at"]),
                expiresAt: DateParsing.iso8601(item["expires_at"] as? String) ?? DateParsing.epochSeconds(item["expires_at"]),
                title: item["title"] as? String
            )
        }
        let available = credits
            .filter { $0.isAvailable && !$0.isExpired(now: now) }
            .sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
        let reported = (root["available_count"] as? NSNumber)?.intValue
        return ResetCreditsSnapshot(
            availableCount: available.count,
            reportedAvailableCount: reported,
            items: available,
            fetchedAt: now
        )
    }
}

public actor ResetCreditService: ResetCreditsProviding {
    private let official: OfficialResetCreditsClient
    private let fallback: ResetCreditFallbackProviding?
    private var cache: ResetCreditsSnapshot?
    private var cachedAt: Date?

    public init(official: OfficialResetCreditsClient, fallback: ResetCreditFallbackProviding?) {
        self.official = official
        self.fallback = fallback
    }

    public func creditsSnapshot(now: Date = Date()) async -> ResetCreditsSnapshot? {
        if let cache, let cachedAt, now.timeIntervalSince(cachedAt) < AppConstants.refreshQuotaSeconds {
            return cache
        }
        if let snapshot = try? await official.fetch(now: now) {
            cache = snapshot
            cachedAt = now
            return snapshot
        }
        if let snapshot = await fallback?.fallbackCredits(now: now) {
            cache = snapshot
            cachedAt = now
            return snapshot
        }
        return cache
    }
}
