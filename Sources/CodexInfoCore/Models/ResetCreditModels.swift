import Foundation

public struct ResetCredit: Codable, Equatable, Sendable, Identifiable {
    public let idSuffix: String
    public let status: String
    public let grantedAt: Date?
    public let expiresAt: Date?
    public let title: String?

    public init(id: String, status: String, grantedAt: Date?, expiresAt: Date?, title: String?) {
        self.idSuffix = String(id.suffix(6))
        self.status = status
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.title = title
    }

    public var id: String { idSuffix }

    public var isAvailable: Bool {
        status.lowercased() == "available"
    }

    public func isExpired(now: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}

public struct ResetCreditsSnapshot: Codable, Equatable, Sendable {
    public let availableCount: Int
    public let reportedAvailableCount: Int?
    public let items: [ResetCredit]
    public let fetchedAt: Date

    public init(availableCount: Int, reportedAvailableCount: Int?, items: [ResetCredit], fetchedAt: Date) {
        self.availableCount = availableCount
        self.reportedAvailableCount = reportedAvailableCount
        self.items = items
        self.fetchedAt = fetchedAt
    }
}
