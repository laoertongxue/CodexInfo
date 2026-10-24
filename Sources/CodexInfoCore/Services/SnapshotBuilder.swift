import Foundation

/// Supplies the token statistics of the signed-in account.
public protocol AccountSnapshotProviding: Sendable {
    func accountSnapshot(now: Date) async -> AccountSnapshot?
}

/// Supplies the state of the reset sources.
public protocol ResetRadarProviding: Sendable {
    func radarSnapshot(now: Date) async -> ResetRadarSnapshot
}

extension AccountUsageService: AccountSnapshotProviding {}

extension ResetRadarService: ResetRadarProviding {}

/// Combines the services into one snapshot.
///
/// The builder never fails: an area without data keeps an empty placeholder
/// and is reported as an error in the freshness, so the panel shows the gap
/// instead of a number that looks real.
public actor SnapshotBuilder {
    /// The number of recent turns that are compared with the baseline.
    ///
    /// The degradation analyzer judges the persistence of a signal over the
    /// last three turns, so the builder hands over the three newest ones.
    static let currentTurnCount = 3

    private let quota: any QuotaSnapshotProviding
    private let credits: any ResetCreditsProviding
    private let sessions: any SessionSnapshotProviding
    private let account: any AccountSnapshotProviding
    private let radar: any ResetRadarProviding

    /// Creates the builder.
    ///
    /// - Parameters:
    ///   - quota: the provider of the quota.
    ///   - credits: the provider of the reset credits.
    ///   - sessions: the provider of the session and its turns.
    ///   - account: the provider of the account statistics.
    ///   - radar: the provider of the reset sources.
    public init(
        quota: any QuotaSnapshotProviding,
        credits: any ResetCreditsProviding,
        sessions: any SessionSnapshotProviding,
        account: any AccountSnapshotProviding,
        radar: any ResetRadarProviding
    ) {
        self.quota = quota
        self.credits = credits
        self.sessions = sessions
        self.account = account
        self.radar = radar
    }

    /// Builds the snapshot of the given moment.
    ///
    /// - Parameters:
    ///   - now: the moment the snapshot belongs to.
    ///   - windowDays: the size of the baseline window in days; the app
    ///     offers 7, 14 and 30 days.
    ///   - minimumTurns: the number of turns the baseline needs at least.
    /// - Returns: the snapshot of every area.
    public func build(
        now: Date = Date(),
        windowDays: Int = 7,
        minimumTurns: Int = 8
    ) async -> UsageSnapshot {
        let quotaProvided = await quota.quotaSnapshot(now: now)
        let creditsProvided = await credits.creditsSnapshot(now: now)
        let sessionProvided = await sessions.currentSnapshot(now: now)
        let turns = await sessions.allTurns(now: now)
        let accountProvided = await account.accountSnapshot(now: now)
        let radarSnapshot = await radar.radarSnapshot(now: now)

        // An area without data keeps an empty placeholder. The placeholder
        // carries the moment of the build, so it is never shown as a value
        // that was measured.
        let quotaSnapshot = quotaProvided ?? QuotaSnapshot(
            planType: nil, weeklyRemainingPercent: nil, weeklyResetsAt: nil, source: .official, fetchedAt: now
        )
        let creditsSnapshot = creditsProvided ?? ResetCreditsSnapshot(
            availableCount: 0, reportedAvailableCount: nil, items: [], fetchedAt: now
        )
        let sessionSnapshot = sessionProvided ?? .empty
        let accountSnapshot = accountProvided ?? AccountSnapshot(
            todayTokens: nil, totalTokens: nil, source: "local", updatedAt: now
        )

        // The newest turns are the current ones, the rest is the baseline.
        // The analyzer decides on its own which of the current turns are
        // fresh enough and whether a signal persists over them.
        let completed = BaselineBuilder.chronological(turns.filter(\.isCompleted))
        let currentCount = min(Self.currentTurnCount, completed.count)
        let currentTurns = Array(completed.suffix(currentCount))
        let baselineTurns = Array(completed.dropLast(currentCount))
        let health = DegradationAnalyzer.analyze(
            baselineTurns: baselineTurns,
            currentTurns: currentTurns,
            routeMismatch: sessionSnapshot.routeMismatch,
            now: now,
            windowDays: windowDays,
            minimumTurns: minimumTurns
        )

        return UsageSnapshot(
            generatedAt: now,
            freshness: Freshness(
                quota: quotaProvided.map { state($0.fetchedAt, now: now) } ?? .error,
                // The session comes from the local index, so it is as old as
                // the last scan of the log files.
                session: sessionProvided == nil ? .error : .fresh,
                account: accountProvided.map { state($0.updatedAt, now: now) } ?? .error,
                sources: radarSnapshot.lastScanAt.map { state($0, now: now) } ?? .error,
                // The reset cards have their own state, so a failed read shows
                // "—" in the panel instead of an empty list that looks like
                // a real zero.
                resetCredits: creditsProvided.map { state($0.fetchedAt, now: now) } ?? .error
            ),
            quota: quotaSnapshot,
            resetCredits: creditsSnapshot,
            session: sessionSnapshot,
            account: accountSnapshot,
            health: health,
            resetRadar: radarSnapshot
        )
    }

    /// The state of an area that is measured at the given moment.
    ///
    /// Data that is younger than the freshness window is fresh, older data
    /// is stale and an area without a moment has no data at all.
    private func state(_ moment: Date?, now: Date) -> DataState {
        guard let moment else { return .error }
        return now.timeIntervalSince(moment) > AppConstants.staleSeconds ? .stale : .fresh
    }
}
