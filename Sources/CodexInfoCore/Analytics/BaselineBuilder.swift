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

    public init(
        turns: [TurnMetrics],
        medians: [HealthSignalID: Double],
        mads: [HealthSignalID: Double],
        iqrs: [HealthSignalID: Double],
        model: String?,
        effort: String?,
        serviceTier: String?
    ) {
        self.turns = turns
        self.medians = medians
        self.mads = mads
        self.iqrs = iqrs
        self.model = model
        self.effort = effort
        self.serviceTier = serviceTier
    }
}

/// Builds the local baseline of one model/effort/service-tier combination.
public enum BaselineBuilder {
    public static func build(
        from turns: [TurnMetrics],
        now: Date,
        windowDays: Int = 7,
        maxTurns: Int = 30,
        minTurns: Int = 8,
        model: String? = nil,
        effort: String? = nil,
        serviceTier: String? = nil
    ) -> BaselineStats? {
        let start = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let eligible = turns
            .filter { $0.isCompleted }
            .filter { ($0.completedAt ?? .distantPast) >= start }
            .filter { model == nil || $0.model == model }
            .filter { effort == nil || $0.reasoningEffort == effort }
            .filter { serviceTier == nil || $0.serviceTier == serviceTier }
            .suffix(maxTurns)
        guard eligible.count >= minTurns else { return nil }

        var medians: [HealthSignalID: Double] = [:]
        var mads: [HealthSignalID: Double] = [:]
        var iqrs: [HealthSignalID: Double] = [:]
        for metric in [HealthSignalID.outputRate, .ttft, .reasoningShare, .toolDensity] {
            let values = eligible.compactMap { value(for: metric, turn: $0) }.sorted()
            guard !values.isEmpty else { continue }
            let median = median(values)
            let deviations = values.map { abs($0 - median) }.sorted()
            medians[metric] = median
            // `median` is shadowed by the local value above, so the helper is
            // called through the type.
            mads[metric] = Self.median(deviations)
            let q1 = quartile(values, fraction: 0.25)
            let q3 = quartile(values, fraction: 0.75)
            iqrs[metric] = q3 - q1
        }
        return BaselineStats(
            turns: Array(eligible),
            medians: medians,
            mads: mads,
            iqrs: iqrs,
            model: eligible.last?.model,
            effort: eligible.last?.reasoningEffort,
            serviceTier: eligible.last?.serviceTier
        )
    }

    public static func value(for metric: HealthSignalID, turn: TurnMetrics) -> Double? {
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

    public static func quartile(_ values: [Double], fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = (Double(sorted.count) - 1) * fraction
        let lower = Int(floor(position))
        let upper = Int(ceil(position))
        if lower == upper { return sorted[lower] }
        let weight = position - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    public static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
