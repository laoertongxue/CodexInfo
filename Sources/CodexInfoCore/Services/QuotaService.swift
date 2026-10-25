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
        var authExpired = false
        var officialSnapshot: QuotaSnapshot?
        do {
            let usage = try await official.fetchUsage(now: now)
            let snapshotBucket = RateLimitBucketSelector.select(usage.rateLimitsByLimitID) ?? usage.rateLimits
            let weekly = snapshotBucket.flatMap(RateLimitWindowSelector.weekly)
            if let weekly {
                officialSnapshot = QuotaSnapshot(
                    planType: usage.planType ?? snapshotBucket?.planType,
                    weeklyRemainingPercent: weekly.remainingPercent,
                    weeklyResetsAt: weekly.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                    source: .official,
                    fetchedAt: now
                )
            }
            // A response without a weekly window carries no quota, so the
            // fallback below provides it instead of publishing an empty value.
        } catch OfficialUsageError.unauthorized {
            // The login expired: the session fallback may still answer, but the
            // panel has to tell the user to sign in again.
            authExpired = true
        } catch HTTPError.status(let code) where code == 401 || code == 403 {
            authExpired = true
        } catch {
            authExpired = false
        }
        if let officialSnapshot {
            cache = officialSnapshot
            cachedAt = now
            return officialSnapshot
        }
        if let fallbackSnapshot = await fallback?.fallbackQuota(now: now) {
            let snapshot = QuotaSnapshot(
                planType: fallbackSnapshot.planType,
                weeklyRemainingPercent: fallbackSnapshot.weeklyRemainingPercent,
                weeklyResetsAt: fallbackSnapshot.weeklyResetsAt,
                source: fallbackSnapshot.source,
                fetchedAt: fallbackSnapshot.fetchedAt,
                authExpired: authExpired
            )
            cache = snapshot
            cachedAt = now
            return snapshot
        }
        return cache
    }
}
