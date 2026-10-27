import Foundation

/// The robust statistics of a local baseline sample.
///
/// Medians and MAD (median absolute deviation) drive the signals; the IQR is
/// kept as the fallback scale when the MAD degenerates to zero.
public struct BaselineStats: Equatable, Sendable {
    public let turns: [TurnMetrics]
    public let medians: [HealthSignalID: Double]
    public let mads: [HealthSignalID: Double]
    public let iqrs: [HealthSignalID: Double]
    public let model: String?
    public let effort: String?
    public let serviceTier: String?
    public let provider: String?

    public init(
        turns: [TurnMetrics],
        medians: [HealthSignalID: Double],
        mads: [HealthSignalID: Double],
        iqrs: [HealthSignalID: Double],
        model: String?,
        effort: String?,
        serviceTier: String?,
        provider: String? = nil
    ) {
        self.turns = turns
        self.medians = medians
        self.mads = mads
        self.iqrs = iqrs
        self.model = model
        self.effort = effort
        self.serviceTier = serviceTier
        self.provider = provider
    }
}

/// Builds the local baseline of one model/effort/service-tier/provider route.
///
/// The route key follows the design (5.6.1): the sample only holds turns of
/// the same `model + reasoning_effort + service_tier + provider`, so a baseline
/// never mixes sessions.
public enum BaselineBuilder {
    /// The seconds of one day.
    static let day: TimeInterval = 86_400

    /// The turns of the window that can carry a baseline sample at all.
    ///
    /// This is the sample without any route filter, so it can report how many
    /// turns exist even when the current route is unknown.
    public static func usableTurns(
        from turns: [TurnMetrics],
        now: Date,
        windowDays: Int = 7
    ) -> [TurnMetrics] {
        let start = now.addingTimeInterval(-Double(windowDays) * day)
        return chronological(turns.filter { turn in
            guard isComparable(turn) else { return false }
            return (turn.completedAt ?? .distantPast) >= start
        })
    }

    /// Whether a turn is comparable enough for the performance baseline.
    ///
    /// Short answers and turns dominated by tool execution have a different
    /// rate profile; including them would make a task change look like a
    /// model slowdown.
    static func isComparable(_ turn: TurnMetrics) -> Bool {
        guard turn.isCompleted, let duration = turn.durationMs, duration > 0 else { return false }
        guard turn.inputTokens + turn.outputTokens > 0 else { return false }
        guard turn.outputTokens >= 50 else { return false }
        return turn.toolMs / duration <= 0.5
    }

    /// The turns of one baseline sample, oldest first.
    ///
    /// A sample turn is completed, finished inside the window, has a positive
    /// duration and carries a token usage record (design 5.6.1). The route key
    /// keeps one `model + reasoning_effort + service_tier + provider`
    /// combination: a `nil` model or effort keeps every model or effort, while
    /// a `nil` service tier or provider only keeps the turns that record no
    /// value for it. An unknown key therefore never widens the sample.
    public static func eligibleTurns(
        from turns: [TurnMetrics],
        now: Date,
        windowDays: Int = 7,
        maxTurns: Int = 30,
        model: String? = nil,
        effort: String? = nil,
        serviceTier: String? = nil,
        provider: String? = nil
    ) -> [TurnMetrics] {
        let usable = usableTurns(from: turns, now: now, windowDays: windowDays).filter { turn in
            if let model = model, turn.model != model { return false }
            if let effort = effort, turn.reasoningEffort != effort { return false }
            if let serviceTier = serviceTier {
                guard turn.serviceTier == serviceTier else { return false }
            } else {
                guard turn.serviceTier == nil else { return false }
            }
            if let provider = provider {
                guard turn.provider == provider else { return false }
            } else {
                guard turn.provider == nil else { return false }
            }
            return true
        }
        // The most recent turns win, so the order has to be chronological
        // before the sample is cut.
        return Array(chronological(usable).suffix(maxTurns))
    }

    /// The robust statistics of the sample, or `nil` when it is too small.
    public static func build(
        from turns: [TurnMetrics],
        now: Date,
        windowDays: Int = 7,
        maxTurns: Int = 30,
        minTurns: Int = 8,
        model: String? = nil,
        effort: String? = nil,
        serviceTier: String? = nil,
        provider: String? = nil
    ) -> BaselineStats? {
        let eligible = eligibleTurns(
            from: turns,
            now: now,
            windowDays: windowDays,
            maxTurns: maxTurns,
            model: model,
            effort: effort,
            serviceTier: serviceTier,
            provider: provider
        )
        guard eligible.count >= minTurns else { return nil }

        var medians: [HealthSignalID: Double] = [:]
        var mads: [HealthSignalID: Double] = [:]
        var iqrs: [HealthSignalID: Double] = [:]
        for metric in [HealthSignalID.outputRate, .ttft, .reasoningShare, .toolDensity] {
            let values = eligible.compactMap { value(for: metric, turn: $0) }.sorted()
            guard !values.isEmpty else { continue }
            let center = median(values)
            medians[metric] = center
            let deviations = values.map { abs($0 - center) }.sorted()
            mads[metric] = median(deviations)
            let q1 = quartile(values, fraction: 0.25)
            let q3 = quartile(values, fraction: 0.75)
            iqrs[metric] = q3 - q1
        }
        return BaselineStats(
            turns: eligible,
            medians: medians,
            mads: mads,
            iqrs: iqrs,
            model: eligible.last?.model,
            effort: eligible.last?.reasoningEffort,
            serviceTier: eligible.last?.serviceTier,
            provider: eligible.last?.provider
        )
    }

    /// Sorts turns by completion time, oldest first.
    ///
    /// The session repository hands out the turns of a session in file order,
    /// so the order of the input is not the order of the turns.
    static func chronological(_ turns: [TurnMetrics]) -> [TurnMetrics] {
        turns.enumerated()
            .sorted { lhs, rhs in
                let left = lhs.element.completedAt ?? .distantPast
                let right = rhs.element.completedAt ?? .distantPast
                if left == right { return lhs.offset < rhs.offset }
                return left < right
            }
            .map(\.element)
    }

    /// The value of one signal inside one turn.
    static func value(for metric: HealthSignalID, turn: TurnMetrics) -> Double? {
        switch metric {
        case .outputRate:
            return OutputRateCalculator.rate(for: turn)?.tokensPerSecond
        case .ttft:
            return turn.ttftMs
        case .reasoningShare:
            return OutputRateCalculator.rate(for: turn)?.reasoningShare
        case .toolDensity:
            return OutputRateCalculator.rate(for: turn)?.toolDensity
        case .route:
            return nil
        }
    }

    static func quartile(_ values: [Double], fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = (Double(sorted.count) - 1) * fraction
        let lower = Int(floor(position))
        let upper = Int(ceil(position))
        if lower == upper { return sorted[lower] }
        let weight = position - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
