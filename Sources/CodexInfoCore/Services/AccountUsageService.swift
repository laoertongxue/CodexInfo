import Foundation

/// Supplies locally indexed token totals for the account statistics.
public protocol AccountTotalsProviding: Sendable {
    func accountTotals(now: Date, calendar: Calendar) async -> (today: Int, total: Int)
}

/// Aggregates account token statistics.
///
/// The official daily breakdown provides "today"; the cumulative total always
/// comes from the local session index. When the official request fails the
/// service degrades to the local numbers instead of returning nothing.
public actor AccountUsageService {
    private let official: OfficialUsageClient
    private let sessions: AccountTotalsProviding
    private let calendar: Calendar
    private var cache: AccountSnapshot?
    private var cachedAt: Date?

    public init(official: OfficialUsageClient, sessions: AccountTotalsProviding, calendar: Calendar = .current) {
        self.official = official
        self.sessions = sessions
        self.calendar = calendar
    }

    public func accountSnapshot(now: Date = Date()) async -> AccountSnapshot? {
        if let cache, let cachedAt, now.timeIntervalSince(cachedAt) < AppConstants.refreshAccountSeconds {
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
