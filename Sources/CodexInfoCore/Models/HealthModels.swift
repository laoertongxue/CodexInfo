import Foundation

/// The local model-health verdict.
///
/// The verdict describes this machine's performance and route. It is not a
/// statement about the model's capability: a local monitor cannot measure IQ
/// without a fixed task set.
public enum HealthStatus: String, Codable, Equatable, Sendable {
    case normal
    /// A performance anomaly was observed.
    case suspected
    /// More than one performance metric moved together.
    case degraded
    /// The actual route is a comparable downgrade of the selected one.
    case route
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
    /// The number of recent turns behind the verdict; older payloads omit it.
    public let recentTurns: Int?
    public let model: String?
    public let effort: String?
    public let signals: [HealthSignal]
    public let disclaimer: String

    public init(
        status: HealthStatus,
        baselineWindowDays: Int,
        sampleTurns: Int,
        recentTurns: Int? = nil,
        model: String?,
        effort: String?,
        signals: [HealthSignal],
        disclaimer: String
    ) {
        self.status = status
        self.baselineWindowDays = baselineWindowDays
        self.sampleTurns = sampleTurns
        self.recentTurns = recentTurns
        self.model = model
        self.effort = effort
        self.signals = signals
        self.disclaimer = disclaimer
    }

    public static let empty = HealthSnapshot(
        status: .insufficient,
        baselineWindowDays: 7,
        sampleTurns: 0,
        recentTurns: 0,
        model: nil,
        effort: nil,
        signals: [],
        disclaimer: "仅比较本机性能与路由，不判断模型能力"
    )
}

/// The thresholds of the abnormal performance signals.
///
/// The standard tier matches the design thresholds; the conservative tier
/// only tightens the speed and time-to-first-token ratios.
public struct HealthThresholds: Equatable, Sendable {
    public let rateRatio: Double
    public let ttftRatio: Double
    public let ttftDeltaMs: Double

    public init(
        rateRatio: Double,
        ttftRatio: Double,
        ttftDeltaMs: Double
    ) {
        self.rateRatio = rateRatio
        self.ttftRatio = ttftRatio
        self.ttftDeltaMs = ttftDeltaMs
    }

    public static let standard = HealthThresholds(
        rateRatio: 0.7, ttftRatio: 2.0, ttftDeltaMs: 2_000
    )
    public static let conservative = HealthThresholds(
        rateRatio: 0.6, ttftRatio: 3.0, ttftDeltaMs: 3_000
    )
}

/// The threshold tier of the verdict.
///
/// The settings offer the two tiers of the design (5.3): the standard tier
/// uses the thresholds of the spec, the conservative tier only tightens the
/// speed and the time to the first token.
public enum HealthThresholdTier: String, Codable, CaseIterable, Equatable, Sendable {
    case standard
    case conservative

    /// The thresholds of the tier.
    public var thresholds: HealthThresholds {
        switch self {
        case .standard: return .standard
        case .conservative: return .conservative
        }
    }

    /// The name of the tier in the settings.
    public var label: String {
        switch self {
        case .standard: return "标准"
        case .conservative: return "保守"
        }
    }
}
