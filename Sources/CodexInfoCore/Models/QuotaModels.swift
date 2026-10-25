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
    /// Whether the official read failed because the login expired.
    ///
    /// The panel shows the re-login hint in that case, even when the session
    /// fallback still provides the weekly quota.
    public let authExpired: Bool
    /// The length of the weekly window, when the payload reports it.
    ///
    /// The panel uses it to derive the previous reset from `weeklyResetsAt`.
    public let weeklyWindowMinutes: Double?
    /// The moment the current weekly window started.
    ///
    /// It is derived from the reset moment and the window length, so the
    /// previous reset is a domain fact instead of arithmetic in the panel.
    public let weeklyWindowStartedAt: Date?

    public init(
        planType: String?,
        weeklyRemainingPercent: Int?,
        weeklyResetsAt: Date?,
        source: QuotaSource,
        fetchedAt: Date,
        authExpired: Bool = false,
        weeklyWindowMinutes: Double? = nil,
        weeklyWindowStartedAt: Date? = nil
    ) {
        self.planType = planType
        self.weeklyRemainingPercent = weeklyRemainingPercent
        self.weeklyResetsAt = weeklyResetsAt
        self.source = source
        self.fetchedAt = fetchedAt
        self.authExpired = authExpired
        self.weeklyWindowMinutes = weeklyWindowMinutes
        if let weeklyWindowStartedAt {
            self.weeklyWindowStartedAt = weeklyWindowStartedAt
        } else if let weeklyResetsAt, let weeklyWindowMinutes, weeklyWindowMinutes > 0 {
            self.weeklyWindowStartedAt = weeklyResetsAt.addingTimeInterval(-weeklyWindowMinutes * 60)
        } else {
            self.weeklyWindowStartedAt = nil
        }
    }
}
