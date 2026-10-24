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

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
