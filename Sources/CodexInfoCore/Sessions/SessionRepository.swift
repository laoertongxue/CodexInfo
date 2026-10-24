import Foundation

public protocol SessionSnapshotProviding: Sendable {
    func currentSnapshot(now: Date) async -> SessionSnapshot?
    func allTurns(now: Date) async -> [TurnMetrics]
}

public actor SessionRepository: SessionSnapshotProviding {
    private let indexer: SessionIndexer
    private var cache: [SessionIndex] = []

    public init(indexer: SessionIndexer) {
        self.indexer = indexer
    }

    public func currentSnapshot(now: Date = Date()) async -> SessionSnapshot? {
        cache = await indexer.scan()
        guard let latest = cache.max(by: { $0.modifiedAt < $1.modifiedAt }) else { return nil }
        let lastTurn = latest.turns.last
        let rate = lastTurn.flatMap(OutputRateCalculator.rate)
        let sameModel = latest.turns.filter {
            $0.model == latest.model && $0.reasoningEffort == latest.reasoningEffort
        }
        let median = OutputRateCalculator.medianRate(sameModel)
        let totalInput = latest.turns.reduce(0) { $0 + $1.inputTokens }
        let totalOutput = latest.turns.reduce(0) { $0 + $1.outputTokens }
        let totalCached = latest.turns.reduce(0) { $0 + $1.cachedInputTokens }
        let totalReasoning = latest.turns.reduce(0) { $0 + $1.reasoningOutputTokens }
        return SessionSnapshot(
            isActive: latest.isActive,
            label: latest.isActive ? "当前会话" : "最近会话",
            model: latest.model,
            effort: latest.reasoningEffort,
            serviceTier: latest.serviceTier,
            contextTokens: latest.contextTokens,
            contextWindow: latest.contextWindow,
            totalTokens: totalInput + totalOutput,
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
        cache = await indexer.scan()
        return cache.flatMap(\.turns)
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

    public func latestRateLimits() async -> RateLimitSnapshot? {
        cache = await indexer.scan()
        return cache.max(by: { $0.modifiedAt < $1.modifiedAt })?.lastRateLimits
    }
}
