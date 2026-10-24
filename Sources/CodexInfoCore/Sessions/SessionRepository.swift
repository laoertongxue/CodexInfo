import Foundation

public protocol SessionSnapshotProviding: Sendable {
    func currentSnapshot(now: Date) async -> SessionSnapshot?
    func allTurns(now: Date) async -> [TurnMetrics]
}

/// The indexed sessions of the machine.
///
/// The repository keeps the result of the last scan, so a build does not read
/// the session log twice: the snapshot, the turns and the rate limits of one
/// build all come from the same scan. A scan that is already running is
/// shared by every caller, so the areas of a build never queue up behind each
/// other.
public actor SessionRepository: SessionSnapshotProviding {
    /// The window in which the result of a scan is reused.
    ///
    /// The window is the refresh interval of the session area, so a build
    /// that runs right after another one does not read the log again.
    public static let scanReuseInterval: TimeInterval = AppConstants.refreshSessionSeconds

    /// The result of one scan of the session log.
    private struct ScanResult: Sendable {
        let indexes: [SessionIndex]
        let threadTotals: [String: Int]
    }

    private let indexer: SessionIndexer
    private var cache: [SessionIndex] = []
    private var threadTotals: [String: Int] = [:]
    private var scannedAt: Date?
    private var pendingScan: Task<ScanResult, Never>?

    public init(indexer: SessionIndexer) {
        self.indexer = indexer
    }

    public func currentSnapshot(now: Date = Date()) async -> SessionSnapshot? {
        let result = await scan(now: now)
        guard let latest = result.indexes.max(by: { $0.modifiedAt < $1.modifiedAt }) else { return nil }
        let lastTurn = latest.turns.last
        let rate = lastTurn.flatMap(OutputRateCalculator.rate)
        // The median window only covers turns that ran on the same route.
        let sameRoute = latest.turns.filter {
            $0.model == latest.model
                && $0.reasoningEffort == latest.reasoningEffort
                && $0.serviceTier == latest.serviceTier
        }
        let median = OutputRateCalculator.medianRate(sameRoute)
        let totalInput = latest.turns.reduce(0) { $0 + $1.inputTokens }
        let totalOutput = latest.turns.reduce(0) { $0 + $1.outputTokens }
        let totalCached = latest.turns.reduce(0) { $0 + $1.cachedInputTokens }
        let totalReasoning = latest.turns.reduce(0) { $0 + $1.reasoningOutputTokens }
        // The thread total is authoritative when present; otherwise fall back to the
        // per-response sum, which is already deduplicated by response id.
        let totalTokens = result.threadTotals[latest.path] ?? (totalInput + totalOutput)
        return SessionSnapshot(
            isActive: latest.isActive,
            label: latest.isActive ? "当前会话" : "最近会话",
            model: latest.model,
            effort: latest.reasoningEffort,
            serviceTier: latest.serviceTier,
            contextTokens: latest.contextTokens,
            contextWindow: latest.contextWindow,
            totalTokens: totalTokens,
            inputTokens: totalInput,
            outputTokens: totalOutput,
            cachedInputTokens: totalCached,
            reasoningOutputTokens: totalReasoning,
            outputTokensPerSecond: rate?.tokensPerSecond,
            medianOutputTokensPerSecond: median,
            ttftMs: lastTurn?.ttftMs,
            turnCount: latest.turns.count,
            routeMismatch: latest.routeMismatch
        )
    }

    public func allTurns(now: Date = Date()) async -> [TurnMetrics] {
        if let scannedAt, now.timeIntervalSince(scannedAt) <= Self.scanReuseInterval {
            return cache.flatMap(\.turns)
        }
        let result = await scan(now: now)
        return result.indexes.flatMap(\.turns)
    }

    public func dailyTokens(calendar: Calendar = .current) async -> [Date: Int] {
        let turns = await allTurns()
        var result: [Date: Int] = [:]
        for turn in turns {
            guard let date = turn.completedAt else { continue }
            let day = calendar.startOfDay(for: date)
            result[day, default: 0] += turn.inputTokens + turn.outputTokens
        }
        return result
    }

    public func latestRateLimits(now: Date = Date()) async -> RateLimitSnapshot? {
        if let scannedAt, now.timeIntervalSince(scannedAt) <= Self.scanReuseInterval {
            return cache.max(by: { $0.modifiedAt < $1.modifiedAt })?.lastRateLimits
        }
        let result = await scan(now: now)
        return result.indexes.max(by: { $0.modifiedAt < $1.modifiedAt })?.lastRateLimits
    }

    /// Reads the session log, unless the last scan is still fresh.
    ///
    /// A scan that is already running is shared, so a caller that arrives
    /// while the log is read waits for that scan instead of starting a second
    /// one.
    private func scan(now: Date) async -> ScanResult {
        if let scannedAt, now.timeIntervalSince(scannedAt) <= Self.scanReuseInterval {
            return ScanResult(indexes: cache, threadTotals: threadTotals)
        }
        if let pendingScan {
            return await pendingScan.value
        }
        let indexer = self.indexer
        let scan = Task { () -> ScanResult in
            let result = await indexer.scanWithTotals()
            return ScanResult(indexes: result.indexes, threadTotals: result.threadTotals)
        }
        pendingScan = scan
        let result = await scan.value
        pendingScan = nil
        cache = result.indexes
        threadTotals = result.threadTotals
        scannedAt = now
        return result
    }
}
