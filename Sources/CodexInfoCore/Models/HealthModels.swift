import Foundation

/// The four-state local model-health verdict.
///
/// The verdict only reflects this machine's own history. It is never an
/// official statement about the upstream model.
public enum HealthStatus: String, Codable, Equatable, Sendable {
    case normal
    case suspected
    case degraded
    case insufficient
}

/// The signals the verdict is built from.
public enum HealthSignalID: String, Codable, Equatable, Sendable {
    case outputRate
    case ttft
    case reasoningShare
    case toolDensity
    case route
}

/// One piece of evidence behind the verdict.
public struct HealthSignal: Codable, Equatable, Sendable {
    public let id: HealthSignalID
    public let label: String
    public let current: Double
    public let baseline: Double
    public let flagged: Bool
    public let detail: String

    public init(
        id: HealthSignalID,
        label: String,
        current: Double,
        baseline: Double,
        flagged: Bool,
        detail: String
    ) {
        self.id = id
        self.label = label
        self.current = current
        self.baseline = baseline
        self.flagged = flagged
        self.detail = detail
    }
}

/// The verdict plus the evidence the panel shows.
public struct HealthSnapshot: Codable, Equatable, Sendable {
    public let status: HealthStatus
    public let baselineWindowDays: Int
    public let sampleTurns: Int
    public let model: String?
    public let effort: String?
    public let signals: [HealthSignal]
    public let disclaimer: String

    public init(
        status: HealthStatus,
        baselineWindowDays: Int,
        sampleTurns: Int,
        model: String?,
        effort: String?,
        signals: [HealthSignal],
        disclaimer: String
    ) {
        self.status = status
        self.baselineWindowDays = baselineWindowDays
        self.sampleTurns = sampleTurns
        self.model = model
        self.effort = effort
        self.signals = signals
        self.disclaimer = disclaimer
    }

    public static let empty = HealthSnapshot(
        status: .insufficient,
        baselineWindowDays: 7,
        sampleTurns: 0,
        model: nil,
        effort: nil,
        signals: [],
        disclaimer: "基于本机近 7 天基线，不代表官方结论"
    )
}

/// The thresholds of the abnormal signals.
///
/// The standard tier matches the design thresholds; the conservative tier
/// only tightens the speed and time-to-first-token ratios.
public struct HealthThresholds: Equatable, Sendable {
    public let rateRatio: Double
    public let ttftRatio: Double
    public let ttftDeltaMs: Double
    public let reasoningRatio: Double
    public let toolDensityRatio: Double

    public init(
        rateRatio: Double,
        ttftRatio: Double,
        ttftDeltaMs: Double,
        reasoningRatio: Double,
        toolDensityRatio: Double
    ) {
        self.rateRatio = rateRatio
        self.ttftRatio = ttftRatio
        self.ttftDeltaMs = ttftDeltaMs
        self.reasoningRatio = reasoningRatio
        self.toolDensityRatio = toolDensityRatio
    }

    public static let standard = HealthThresholds(
        rateRatio: 0.7, ttftRatio: 2.0, ttftDeltaMs: 2_000,
        reasoningRatio: 0.5, toolDensityRatio: 0.6
    )
    public static let conservative = HealthThresholds(
        rateRatio: 0.6, ttftRatio: 3.0, ttftDeltaMs: 3_000,
        reasoningRatio: 0.5, toolDensityRatio: 0.6
    )
}
