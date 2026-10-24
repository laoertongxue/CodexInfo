import Foundation

public struct TurnRate: Equatable, Sendable {
    public let tokensPerSecond: Double
    public let ttftMs: Double?
    public let reasoningShare: Double?
    public let toolDensity: Double?
}

public enum OutputRateCalculator {
    public static func rate(for turn: TurnMetrics) -> TurnRate? {
        guard turn.isCompleted, turn.outputTokens > 0, let duration = turn.durationMs else { return nil }
        let ttft = turn.ttftMs ?? 0
        let wallMs = max(duration - ttft, 1)
        let generationMs: Double
        if turn.modelItemMs > 0 {
            // Model item time cannot exceed the observable generation window.
            generationMs = min(turn.modelItemMs, wallMs)
        } else {
            generationMs = max(wallMs - turn.toolMs, 1)
        }
        guard generationMs > 0 else { return nil }
        let reasoningShare = Double(turn.reasoningOutputTokens) / Double(turn.outputTokens)
        let toolDensity = turn.outputTokens > 0
            ? Double(turn.toolCallCount) / (Double(turn.outputTokens) / 1_000)
            : nil
        return TurnRate(
            tokensPerSecond: Double(turn.outputTokens) / generationMs * 1_000,
            ttftMs: turn.ttftMs,
            reasoningShare: reasoningShare,
            toolDensity: toolDensity
        )
    }

    public static func medianRate(_ turns: [TurnMetrics], count: Int = 5) -> Double? {
        let values = turns
            .filter(\.isCompleted)
            .suffix(count)
            .compactMap { rate(for: $0)?.tokensPerSecond }
            .sorted()
        guard !values.isEmpty else { return nil }
        let middle = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[middle - 1] + values[middle]) / 2
        }
        return values[middle]
    }
}
