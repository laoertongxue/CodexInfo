import Foundation

public struct RateLimitWindow: Codable, Equatable, Sendable {
    public let usedPercent: Double
    public let windowDurationMins: Double?
    public let resetsAt: Int?

    public init(usedPercent: Double, windowDurationMins: Double?, resetsAt: Int?) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }

    /// The share of the window that is left.
    ///
    /// The value is clamped in `Double` space and converted afterwards: a
    /// malformed payload can carry a percentage far outside the range of an
    /// `Int` (`1e30`) or a non-finite number, and the conversion to `Int`
    /// traps on both. A non-finite percentage carries no usable value, so the
    /// window counts as fully used.
    public var remainingPercent: Int {
        guard usedPercent.isFinite else { return 0 }
        let remaining = (100 - usedPercent).clamped(to: 0...100)
        return Int(remaining.rounded())
    }
}

public struct RateLimitSnapshot: Codable, Equatable, Sendable {
    public let limitId: String?
    public let primary: RateLimitWindow?
    public let secondary: RateLimitWindow?
    public let planType: String?

    public init(limitId: String?, primary: RateLimitWindow?, secondary: RateLimitWindow?, planType: String?) {
        self.limitId = limitId
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
    }
}

public enum RateLimitPayloadDecoder {
    /// Decodes a rate-limit payload.
    ///
    /// Two shapes are in the wild: the session log publishes `rate_limits` with
    /// `primary`/`secondary` windows, while the official endpoint publishes
    /// `rate_limit` with `primary_window`/`secondary_window`, a window length
    /// in seconds and the reset as an epoch or as a remaining duration.
    public static func snapshot(from object: [String: Any], now: Date = Date()) -> RateLimitSnapshot? {
        let primaryObject = object["primary"] as? [String: Any]
            ?? object["primary_window"] as? [String: Any]
            ?? object["primaryWindow"] as? [String: Any]
        let secondaryObject = object["secondary"] as? [String: Any]
            ?? object["secondary_window"] as? [String: Any]
            ?? object["secondaryWindow"] as? [String: Any]
        guard object["limit_id"] != nil || object["limitId"] != nil
                || primaryObject != nil || secondaryObject != nil else { return nil }
        return RateLimitSnapshot(
            limitId: object["limit_id"] as? String ?? object["limitId"] as? String,
            primary: window(primaryObject, now: now),
            secondary: window(secondaryObject, now: now),
            planType: object["plan_type"] as? String ?? object["planType"] as? String
        )
    }

    public static func snapshotMap(from object: [String: Any], now: Date = Date()) -> [String: RateLimitSnapshot] {
        var result: [String: RateLimitSnapshot] = [:]
        for (key, value) in object {
            if let dictionary = value as? [String: Any], let snapshot = snapshot(from: dictionary, now: now) {
                result[key] = snapshot
            }
        }
        return result
    }

    private static func window(_ object: [String: Any]?, now: Date) -> RateLimitWindow? {
        guard let object else { return nil }
        let used = number(object["used_percent"]) ?? number(object["usedPercent"])
        guard let used else { return nil }
        let minutes = (number(object["window_minutes"]) ?? number(object["windowDurationMins"]))?.doubleValue
            ?? number(object["limit_window_seconds"]).flatMap { $0.doubleValue / 60 }
            ?? number(object["limitWindowSeconds"]).flatMap { $0.doubleValue / 60 }
        var resetsAt = (number(object["resets_at"]) ?? number(object["resetsAt"]))?.intValue
            ?? number(object["reset_at"])?.intValue
        if resetsAt == nil, let after = number(object["reset_after_seconds"])?.doubleValue
            ?? number(object["resetAfterSeconds"])?.doubleValue {
            resetsAt = Int(now.addingTimeInterval(after).timeIntervalSince1970)
        }
        return RateLimitWindow(
            usedPercent: used.doubleValue,
            windowDurationMins: minutes,
            resetsAt: resetsAt
        )
    }

    private static func number(_ value: Any?) -> NSNumber? {
        value as? NSNumber
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
