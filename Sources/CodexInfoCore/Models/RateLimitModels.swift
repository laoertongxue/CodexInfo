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

    public var remainingPercent: Int {
        Int((100 - usedPercent).rounded()).clamped(to: 0...100)
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
    public static func snapshot(from object: [String: Any]) -> RateLimitSnapshot? {
        guard object["limit_id"] != nil || object["limitId"] != nil || object["primary"] != nil else { return nil }
        return RateLimitSnapshot(
            limitId: object["limit_id"] as? String ?? object["limitId"] as? String,
            primary: window(object["primary"] as? [String: Any]),
            secondary: window(object["secondary"] as? [String: Any]),
            planType: object["plan_type"] as? String ?? object["planType"] as? String
        )
    }

    public static func snapshotMap(from object: [String: Any]) -> [String: RateLimitSnapshot] {
        var result: [String: RateLimitSnapshot] = [:]
        for (key, value) in object {
            if let dictionary = value as? [String: Any], let snapshot = snapshot(from: dictionary) {
                result[key] = snapshot
            }
        }
        return result
    }

    private static func window(_ object: [String: Any]?) -> RateLimitWindow? {
        guard let object, let used = (object["used_percent"] as? NSNumber)?.doubleValue else { return nil }
        return RateLimitWindow(
            usedPercent: used,
            windowDurationMins: (object["window_minutes"] as? NSNumber)?.doubleValue,
            resetsAt: (object["resets_at"] as? NSNumber)?.intValue
        )
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
