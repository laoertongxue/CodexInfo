import Foundation

public enum QuotaSource: String, Codable, Equatable, Sendable {
    case official
    case appServer
    case session
}

public struct QuotaSnapshot: Codable, Equatable, Sendable {
    public let planType: String?
    public let weeklyRemainingPercent: Int?
    public let weeklyResetsAt: Date?
    public let source: QuotaSource
    public let fetchedAt: Date

    public init(planType: String?, weeklyRemainingPercent: Int?, weeklyResetsAt: Date?, source: QuotaSource, fetchedAt: Date) {
        self.planType = planType
        self.weeklyRemainingPercent = weeklyRemainingPercent
        self.weeklyResetsAt = weeklyResetsAt
        self.source = source
        self.fetchedAt = fetchedAt
    }
}
