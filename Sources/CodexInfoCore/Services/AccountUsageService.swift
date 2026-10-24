import Foundation

/// Supplies locally indexed token totals for the account statistics.
public protocol AccountTotalsProviding: Sendable {
    func accountTotals(now: Date, calendar: Calendar) async -> (today: Int, total: Int)
}

/// Aggregates account token statistics.
///
/// The official daily breakdown provides "today"; the cumulative total always
/// comes from the local session index. When the official request fails — including
/// when the official payload has a shape that cannot be read — the service degrades
/// to the local numbers instead of returning nothing.
///
/// The cached snapshot is only reused inside the same local day: after the calendar
/// day rolls over, yesterday's "today" must not be served for the new day.
public actor AccountUsageService {
    private let official: OfficialUsageClient
    private let sessions: AccountTotalsProviding
    private let calendar: Calendar
    private var cache: AccountSnapshot?
    private var cachedAt: Date?
    private var cachedDay: Date?

    public init(official: OfficialUsageClient, sessions: AccountTotalsProviding, calendar: Calendar = .current) {
        self.official = official
        self.sessions = sessions
        self.calendar = calendar
    }

    /// The cached snapshot when it is still fresh for the current local day.
    ///
    /// The signature stays `accountSnapshot(now:)` because the snapshot builder
    /// consumes the service through that method; the cache bypassing variant below
    /// is a separate overload so it cannot break that call site.
    public func accountSnapshot(now: Date = Date()) async -> AccountSnapshot? {
        await accountSnapshot(now: now, force: false)
    }

    /// Same as `accountSnapshot(now:)`, but `force` bypasses the cache so a manual
    /// refresh always asks the official endpoint again.
    public func accountSnapshot(now: Date, force: Bool) async -> AccountSnapshot? {
        if !force, let cache, let cachedAt, cachedDay == calendar.startOfDay(for: now),
           now.timeIntervalSince(cachedAt) < AppConstants.refreshAccountSeconds {
            return cache
        }
        let local = await sessions.accountTotals(now: now, calendar: calendar)
        let start = calendar.startOfDay(for: now)
        let officialToday = try? await official.fetchDailyTokenUsage(start: start, end: now, calendar: calendar)
        let snapshot: AccountSnapshot
        if let officialToday {
            snapshot = AccountSnapshot(todayTokens: officialToday, totalTokens: local.total, source: "official+local", updatedAt: now)
        } else {
            snapshot = AccountSnapshot(todayTokens: local.today, totalTokens: local.total, source: "local", updatedAt: now)
        }
        cache = snapshot
        cachedAt = now
        cachedDay = calendar.startOfDay(for: now)
        return snapshot
    }
}

extension SessionRepository: AccountTotalsProviding {
    public func accountTotals(now: Date, calendar: Calendar) async -> (today: Int, total: Int) {
        let daily = await dailyTokens(calendar: calendar)
        let today = daily[calendar.startOfDay(for: now)] ?? 0
        let total = daily.values.reduce(0, +)
        return (today, total)
    }
}
