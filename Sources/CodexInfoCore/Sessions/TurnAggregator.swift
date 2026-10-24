import Foundation

public struct TurnMetrics: Codable, Equatable, Sendable {
    public let turnId: String
    public let model: String?
    public let reasoningEffort: String?
    public let serviceTier: String?
    public let provider: String?
    public let compHash: String?
    public let startedAt: Date?
    public let completedAt: Date?
    public let durationMs: Double?
    public let ttftMs: Double?
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let outputTokens: Int
    public let reasoningOutputTokens: Int
    public let modelItemMs: Double
    public let toolMs: Double
    public let toolCallCount: Int
    public let isCompleted: Bool

    public init(
        turnId: String,
        model: String?,
        reasoningEffort: String?,
        serviceTier: String?,
        provider: String?,
        compHash: String?,
        startedAt: Date?,
        completedAt: Date?,
        durationMs: Double?,
        ttftMs: Double?,
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int,
        reasoningOutputTokens: Int,
        modelItemMs: Double,
        toolMs: Double,
        toolCallCount: Int,
        isCompleted: Bool
    ) {
        self.turnId = turnId
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.serviceTier = serviceTier
        self.provider = provider
        self.compHash = compHash
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.durationMs = durationMs
        self.ttftMs = ttftMs
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.modelItemMs = modelItemMs
        self.toolMs = toolMs
        self.toolCallCount = toolCallCount
        self.isCompleted = isCompleted
    }
}

public struct SessionAggregate: Equatable, Sendable {
    public let turns: [TurnMetrics]
    public let lastTokenCount: TokenCountEvent?
    public let compactionCount: Int
}

public enum TurnAggregator {
    public static func aggregate(_ events: [SessionEvent]) -> SessionAggregate {
        var builders: [String: TurnBuilder] = [:]
        var order: [String] = []
        var settings: ThreadSettingsEvent?
        var lastTokenCount: TokenCountEvent?
        var compactions = 0

        func builder(for turnId: String) -> TurnBuilder {
            if let existing = builders[turnId] { return existing }
            let newBuilder = TurnBuilder(turnId: turnId)
            builders[turnId] = newBuilder
            order.append(turnId)
            return newBuilder
        }

        for event in events {
            switch event {
            case .threadSettings(let value):
                settings = value
            case .turnContext(let value):
                var valueBuilder = builder(for: value.turnId)
                valueBuilder.model = value.model
                valueBuilder.reasoningEffort = value.reasoningEffort
                valueBuilder.compHash = value.compHash
                builders[value.turnId] = valueBuilder
            case .taskStarted(let value):
                var valueBuilder = builder(for: value.turnId)
                valueBuilder.startedAt = value.startedAt
                builders[value.turnId] = valueBuilder
            case .tokenUsageRecord(let value):
                var valueBuilder = builder(for: value.turnId)
                valueBuilder.addUsage(value)
                builders[value.turnId] = valueBuilder
            case .itemCompleted(let value):
                var valueBuilder = builder(for: value.turnId)
                valueBuilder.addItem(value)
                builders[value.turnId] = valueBuilder
            case .taskComplete(let value):
                var valueBuilder = builder(for: value.turnId)
                valueBuilder.durationMs = value.durationMs
                valueBuilder.ttftMs = value.ttftMs
                valueBuilder.completedAt = value.completedAt
                builders[value.turnId] = valueBuilder
            case .tokenCount(let value):
                lastTokenCount = value
            case .turnAborted:
                // An aborted turn never completes, so it carries no metrics and
                // stays outside the baseline. It must not create a turn either.
                break
            case .compacted:
                compactions += 1
            }
        }

        let turns = order.compactMap { builders[$0]?.build(settings: settings) }
        return SessionAggregate(turns: turns, lastTokenCount: lastTokenCount, compactionCount: compactions)
    }
}

private struct TurnBuilder {
    let turnId: String
    var model: String?
    var reasoningEffort: String?
    var compHash: String?
    var startedAt: Date?
    var completedAt: Date?
    var durationMs: Double?
    var ttftMs: Double?
    var usages: [String: TokenUsage] = [:]
    var responseOrder: [String] = []
    var modelItemMs: Double = 0
    var toolMs: Double = 0
    var toolCallCount: Int = 0

    mutating func addUsage(_ record: TokenUsageRecordEvent) {
        let key = record.responseId.isEmpty ? UUID().uuidString : record.responseId
        if usages[key] == nil { responseOrder.append(key) }
        usages[key] = record.usage
        if startedAt == nil { startedAt = record.timestamp }
    }

    mutating func addItem(_ item: ItemCompletedEvent) {
        let duration = max((item.completedAtMs ?? 0) - (item.startedAtMs ?? 0), 0)
        switch item.itemType {
        case "AgentMessage", "Reasoning":
            modelItemMs += duration
        case "CommandExecution", "McpToolCall", "FileChange", "Extension":
            toolMs += duration
            toolCallCount += 1
        default:
            break
        }
    }

    func build(settings: ThreadSettingsEvent?) -> TurnMetrics {
        let usages = responseOrder.compactMap { self.usages[$0] }
        return TurnMetrics(
            turnId: turnId,
            model: model ?? settings?.model,
            reasoningEffort: reasoningEffort ?? settings?.reasoningEffort,
            serviceTier: settings?.serviceTier,
            provider: settings?.provider,
            compHash: compHash,
            startedAt: startedAt,
            completedAt: completedAt,
            durationMs: durationMs,
            ttftMs: ttftMs,
            inputTokens: usages.reduce(0) { $0 + $1.inputTokens },
            cachedInputTokens: usages.reduce(0) { $0 + $1.cachedInputTokens },
            outputTokens: usages.reduce(0) { $0 + $1.outputTokens },
            reasoningOutputTokens: usages.reduce(0) { $0 + $1.reasoningOutputTokens },
            modelItemMs: modelItemMs,
            toolMs: toolMs,
            toolCallCount: toolCallCount,
            isCompleted: completedAt != nil && durationMs != nil
        )
    }
}
