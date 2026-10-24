import Foundation

/// Token statistics for the signed-in account.
///
/// `todayTokens` and `totalTokens` are optional so a degraded source can report
/// "unknown" instead of a misleading zero. `source` records which data was used
/// (`official+local` or `local`) so the panel can label the origin.
public struct AccountSnapshot: Codable, Equatable, Sendable {
    public let todayTokens: Int?
    public let totalTokens: Int?
    public let source: String
    public let updatedAt: Date

    public init(todayTokens: Int?, totalTokens: Int?, source: String, updatedAt: Date) {
        self.todayTokens = todayTokens
        self.totalTokens = totalTokens
        self.source = source
        self.updatedAt = updatedAt
    }
}
