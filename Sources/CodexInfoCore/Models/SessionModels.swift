import Foundation

public struct TokenUsage: Codable, Equatable, Sendable {
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let cacheWriteInputTokens: Int
    public let outputTokens: Int
    public let reasoningOutputTokens: Int
    public let totalTokens: Int

    public init(inputTokens: Int, cachedInputTokens: Int, cacheWriteInputTokens: Int, outputTokens: Int, reasoningOutputTokens: Int, totalTokens: Int) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteInputTokens = cacheWriteInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }

    public static let zero = TokenUsage(inputTokens: 0, cachedInputTokens: 0, cacheWriteInputTokens: 0, outputTokens: 0, reasoningOutputTokens: 0, totalTokens: 0)
}

public struct TokenUsageRecordEvent: Equatable, Sendable {
    public let timestamp: Date?
    public let turnId: String
    public let responseId: String
    public let usage: TokenUsage
    public let turnTokenUsage: TokenUsage
    public let threadTokenUsage: TokenUsage

    public init(timestamp: Date?, turnId: String, responseId: String, usage: TokenUsage, turnTokenUsage: TokenUsage, threadTokenUsage: TokenUsage) {
        self.timestamp = timestamp
        self.turnId = turnId
        self.responseId = responseId
        self.usage = usage
        self.turnTokenUsage = turnTokenUsage
        self.threadTokenUsage = threadTokenUsage
    }
}

public struct TaskStartedEvent: Equatable, Sendable {
    public let turnId: String
    public let startedAt: Date?

    public init(turnId: String, startedAt: Date?) {
        self.turnId = turnId
        self.startedAt = startedAt
    }
}

public struct TaskCompleteEvent: Equatable, Sendable {
    public let turnId: String
    public let durationMs: Double?
    public let ttftMs: Double?
    public let completedAt: Date?

    public init(turnId: String, durationMs: Double?, ttftMs: Double?, completedAt: Date?) {
        self.turnId = turnId
        self.durationMs = durationMs
        self.ttftMs = ttftMs
        self.completedAt = completedAt
    }
}

public struct TokenCountEvent: Equatable, Sendable {
    public let lastUsage: TokenUsage?
    public let totalUsage: TokenUsage?
    public let modelContextWindow: Int?
    public let rateLimits: RateLimitSnapshot?

    public init(lastUsage: TokenUsage?, totalUsage: TokenUsage?, modelContextWindow: Int?, rateLimits: RateLimitSnapshot?) {
        self.lastUsage = lastUsage
        self.totalUsage = totalUsage
        self.modelContextWindow = modelContextWindow
        self.rateLimits = rateLimits
    }
}

public struct ItemCompletedEvent: Equatable, Sendable {
    public let turnId: String
    public let itemType: String
    public let startedAtMs: Double?
    public let completedAtMs: Double?

    public init(turnId: String, itemType: String, startedAtMs: Double?, completedAtMs: Double?) {
        self.turnId = turnId
        self.itemType = itemType
        self.startedAtMs = startedAtMs
        self.completedAtMs = completedAtMs
    }
}

public struct TurnContextEvent: Equatable, Sendable {
    public let turnId: String
    public let model: String?
    public let reasoningEffort: String?
    public let compHash: String?

    public init(turnId: String, model: String?, reasoningEffort: String?, compHash: String?) {
        self.turnId = turnId
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.compHash = compHash
    }
}

public struct ThreadSettingsEvent: Equatable, Sendable {
    public let model: String?
    public let reasoningEffort: String?
    public let serviceTier: String?
    public let provider: String?

    public init(model: String?, reasoningEffort: String?, serviceTier: String?, provider: String?) {
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.serviceTier = serviceTier
        self.provider = provider
    }
}

public enum SessionEvent: Equatable, Sendable {
    case tokenUsageRecord(TokenUsageRecordEvent)
    case taskStarted(TaskStartedEvent)
    case taskComplete(TaskCompleteEvent)
    case tokenCount(TokenCountEvent)
    case itemCompleted(ItemCompletedEvent)
    case turnContext(TurnContextEvent)
    case threadSettings(ThreadSettingsEvent)
    case compacted
}

public struct SessionIndex: Codable, Equatable, Sendable {
    public let path: String
    public let modifiedAt: Date
    public let turns: [TurnMetrics]
    public let isActive: Bool
    public let model: String?
    public let reasoningEffort: String?
    public let serviceTier: String?
    public let contextTokens: Int?
    public let contextWindow: Int?
    public let lastRateLimits: RateLimitSnapshot?
    public let selectedModel: String?
    public let selectedEffort: String?
    public let selectedServiceTier: String?
    public let routeMismatch: Bool

    public init(
        path: String,
        modifiedAt: Date,
        turns: [TurnMetrics],
        isActive: Bool,
        model: String?,
        reasoningEffort: String?,
        serviceTier: String?,
        contextTokens: Int?,
        contextWindow: Int?,
        lastRateLimits: RateLimitSnapshot?,
        selectedModel: String?,
        selectedEffort: String?,
        selectedServiceTier: String?,
        routeMismatch: Bool
    ) {
        self.path = path
        self.modifiedAt = modifiedAt
        self.turns = turns
        self.isActive = isActive
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.serviceTier = serviceTier
        self.contextTokens = contextTokens
        self.contextWindow = contextWindow
        self.lastRateLimits = lastRateLimits
        self.selectedModel = selectedModel
        self.selectedEffort = selectedEffort
        self.selectedServiceTier = selectedServiceTier
        self.routeMismatch = routeMismatch
    }
}

public struct SessionSnapshot: Codable, Equatable, Sendable {
    public let isActive: Bool
    public let label: String
    public let model: String?
    public let effort: String?
    public let serviceTier: String?
    public let contextTokens: Int?
    public let contextWindow: Int?
    public let totalTokens: Int?
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cachedInputTokens: Int?
    public let reasoningOutputTokens: Int?
    public let outputTokensPerSecond: Double?
    public let medianOutputTokensPerSecond: Double?
    public let ttftMs: Double?
    public let turnCount: Int
    public let routeMismatch: Bool

    public init(
        isActive: Bool,
        label: String,
        model: String?,
        effort: String?,
        serviceTier: String?,
        contextTokens: Int?,
        contextWindow: Int?,
        totalTokens: Int?,
        inputTokens: Int?,
        outputTokens: Int?,
        cachedInputTokens: Int?,
        reasoningOutputTokens: Int?,
        outputTokensPerSecond: Double?,
        medianOutputTokensPerSecond: Double?,
        ttftMs: Double?,
        turnCount: Int,
        routeMismatch: Bool
    ) {
        self.isActive = isActive
        self.label = label
        self.model = model
        self.effort = effort
        self.serviceTier = serviceTier
        self.contextTokens = contextTokens
        self.contextWindow = contextWindow
        self.totalTokens = totalTokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedInputTokens = cachedInputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.outputTokensPerSecond = outputTokensPerSecond
        self.medianOutputTokensPerSecond = medianOutputTokensPerSecond
        self.ttftMs = ttftMs
        self.turnCount = turnCount
        self.routeMismatch = routeMismatch
    }
}

extension TokenCountEvent: Codable {}
