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
}

public struct TaskStartedEvent: Equatable, Sendable {
    public let turnId: String
    public let startedAt: Date?
}

public struct TaskCompleteEvent: Equatable, Sendable {
    public let turnId: String
    public let durationMs: Double?
    public let ttftMs: Double?
    public let completedAt: Date?
}

public struct TokenCountEvent: Equatable, Sendable {
    public let lastUsage: TokenUsage?
    public let totalUsage: TokenUsage?
    public let modelContextWindow: Int?
    public let rateLimits: RateLimitSnapshot?
}

public struct ItemCompletedEvent: Equatable, Sendable {
    public let turnId: String
    public let itemType: String
    public let startedAtMs: Double?
    public let completedAtMs: Double?
}

public struct TurnContextEvent: Equatable, Sendable {
    public let turnId: String
    public let model: String?
    public let reasoningEffort: String?
    public let compHash: String?
}

public struct ThreadSettingsEvent: Equatable, Sendable {
    public let model: String?
    public let reasoningEffort: String?
    public let serviceTier: String?
    public let provider: String?
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
