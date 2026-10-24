import Foundation

public protocol QuotaSnapshotProviding: Sendable {
    func quotaSnapshot(now: Date) async -> QuotaSnapshot?
}

public protocol QuotaFallbackProviding: Sendable {
    func fallbackQuota(now: Date) async -> QuotaSnapshot?
}

public actor QuotaService: QuotaSnapshotProviding {
    private let official: OfficialUsageClient
    private let fallback: QuotaFallbackProviding?
    private var cache: QuotaSnapshot?
    private var cachedAt: Date?

    public init(official: OfficialUsageClient, fallback: QuotaFallbackProviding?) {
        self.official = official
        self.fallback = fallback
    }

    public func quotaSnapshot(now: Date = Date()) async -> QuotaSnapshot? {
        if let cache, let cachedAt, now.timeIntervalSince(cachedAt) < AppConstants.refreshQuotaSeconds {
            return cache
        }
        if let usage = try? await official.fetchUsage() {
            let snapshotBucket = RateLimitBucketSelector.select(usage.rateLimitsByLimitID) ?? usage.rateLimits
            let weekly = snapshotBucket.flatMap(RateLimitWindowSelector.weekly)
            let snapshot = QuotaSnapshot(
                planType: usage.planType ?? snapshotBucket?.planType,
                weeklyRemainingPercent: weekly?.remainingPercent,
                weeklyResetsAt: weekly?.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                source: .official,
                fetchedAt: now
            )
            cache = snapshot
            cachedAt = now
            return snapshot
        }
        if let fallbackSnapshot = await fallback?.fallbackQuota(now: now) {
            cache = fallbackSnapshot
            cachedAt = now
            return fallbackSnapshot
        }
        return cache
    }
}
