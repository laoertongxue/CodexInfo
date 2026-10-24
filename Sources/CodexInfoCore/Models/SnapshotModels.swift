import Foundation

/// The state of one area of the snapshot.
///
/// The panel shows the state next to the numbers, so a value that is old or
/// missing is never presented as if it were current.
public enum DataState: String, Codable, Equatable, Sendable {
    /// The data is younger than the freshness window.
    case fresh
    /// The data is older than the freshness window.
    case stale
    /// The data is still being loaded.
    case loading
    /// The area has no data at all.
    case error
}

/// The state of every area of a snapshot.
public struct Freshness: Codable, Equatable, Sendable {
    /// The state of the quota.
    public let quota: DataState
    /// The state of the session.
    public let session: DataState
    /// The state of the account statistics.
    public let account: DataState
    /// The state of the reset sources.
    public let sources: DataState
    /// The state of the reset cards.
    public let resetCredits: DataState

    public init(
        quota: DataState,
        session: DataState,
        account: DataState,
        sources: DataState,
        resetCredits: DataState = .fresh
    ) {
        self.quota = quota
        self.session = session
        self.account = account
        self.sources = sources
        self.resetCredits = resetCredits
    }
}

/// Everything the panel and the MCP server show.
///
/// The snapshot is the single source of truth of the app: the menu bar and
/// the MCP server read the same numbers, so a snapshot carries the state of
/// every area next to the values themselves.
public struct UsageSnapshot: Codable, Equatable, Sendable {
    /// The moment the snapshot was built.
    public let generatedAt: Date
    /// The state of every area of the snapshot.
    public let freshness: Freshness
    /// The quota of the account.
    public let quota: QuotaSnapshot
    /// The reset credits of the account.
    public let resetCredits: ResetCreditsSnapshot
    /// The current or the most recent session.
    public let session: SessionSnapshot
    /// The token statistics of the account.
    public let account: AccountSnapshot
    /// The local model-health verdict.
    public let health: HealthSnapshot
    /// The state of the reset sources.
    public let resetRadar: ResetRadarSnapshot

    public init(
        generatedAt: Date,
        freshness: Freshness,
        quota: QuotaSnapshot,
        resetCredits: ResetCreditsSnapshot,
        session: SessionSnapshot,
        account: AccountSnapshot,
        health: HealthSnapshot,
        resetRadar: ResetRadarSnapshot
    ) {
        self.generatedAt = generatedAt
        self.freshness = freshness
        self.quota = quota
        self.resetCredits = resetCredits
        self.session = session
        self.account = account
        self.health = health
        self.resetRadar = resetRadar
    }
}

extension SessionSnapshot {
    /// The placeholder of an area without session data.
    ///
    /// The numbers stay empty, so the panel can tell "no session" from a
    /// session without tokens.
    public static let empty = SessionSnapshot(
        isActive: false, label: "最近会话", model: nil, effort: nil, serviceTier: nil,
        contextTokens: nil, contextWindow: nil, totalTokens: nil, inputTokens: nil,
        outputTokens: nil, cachedInputTokens: nil, reasoningOutputTokens: nil,
        outputTokensPerSecond: nil, medianOutputTokensPerSecond: nil,
        ttftMs: nil, turnCount: 0, routeMismatch: false
    )
}
