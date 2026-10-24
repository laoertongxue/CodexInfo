import Foundation

public enum RateLimitWindowSelector {
    public static func weekly(from snapshot: RateLimitSnapshot) -> RateLimitWindow? {
        window(in: snapshot, near: AppConstants.weeklyWindowMinutes)
    }

    public static func fiveHour(from snapshot: RateLimitSnapshot) -> RateLimitWindow? {
        window(in: snapshot, near: AppConstants.fiveHourWindowMinutes)
    }

    private static func window(in snapshot: RateLimitSnapshot, near target: Double) -> RateLimitWindow? {
        [snapshot.primary, snapshot.secondary]
            .compactMap { $0 }
            .first { window in
                guard let duration = window.windowDurationMins else { return false }
                return abs(duration - target) <= target * 0.05
            }
    }
}

public enum RateLimitBucketSelector {
    public static func select(_ buckets: [String: RateLimitSnapshot]) -> RateLimitSnapshot? {
        buckets["codex"] ?? buckets.values.first { $0.limitId == "codex" }
    }
}
