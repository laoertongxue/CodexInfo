import Foundation

public enum SessionLogParser {
    public static func parse(line: Data) -> SessionEvent? {
        guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = root["type"] as? String,
              let payload = root["payload"] as? [String: Any] else {
            return nil
        }
        let timestamp = DateParsing.iso8601(root["timestamp"] as? String)

        switch type {
        case "turn_context":
            return .turnContext(TurnContextEvent(
                turnId: payload["turn_id"] as? String ?? "",
                model: payload["model"] as? String,
                reasoningEffort: payload["effort"] as? String,
                compHash: payload["comp_hash"] as? String
            ))
        case "token_usage_record":
            return .tokenUsageRecord(TokenUsageRecordEvent(
                timestamp: timestamp,
                turnId: payload["turn_id"] as? String ?? "",
                responseId: payload["response_id"] as? String ?? "",
                usage: usage(from: payload["usage"] as? [String: Any]),
                turnTokenUsage: usage(from: payload["turn_token_usage"] as? [String: Any]),
                threadTokenUsage: usage(from: payload["thread_token_usage"] as? [String: Any])
            ))
        case "event_msg":
            return parseEventMessage(payload: payload, timestamp: timestamp)
        case "compacted":
            return .compacted
        default:
            return nil
        }
    }

    private static func parseEventMessage(payload: [String: Any], timestamp: Date?) -> SessionEvent? {
        guard let eventType = payload["type"] as? String else { return nil }
        switch eventType {
        case "task_started":
            return .taskStarted(TaskStartedEvent(
                turnId: payload["turn_id"] as? String ?? "",
                startedAt: DateParsing.epochSeconds(payload["started_at"]) ?? timestamp
            ))
        case "task_complete":
            return .taskComplete(TaskCompleteEvent(
                turnId: payload["turn_id"] as? String ?? "",
                durationMs: double(payload["duration_ms"]),
                ttftMs: double(payload["time_to_first_token_ms"]),
                completedAt: timestamp
            ))
        case "token_count":
            let info = payload["info"] as? [String: Any]
            return .tokenCount(TokenCountEvent(
                lastUsage: usage(from: info?["last_token_usage"] as? [String: Any]),
                totalUsage: usage(from: info?["total_token_usage"] as? [String: Any]),
                modelContextWindow: int(info?["model_context_window"]),
                rateLimits: rateLimits(from: payload["rate_limits"] as? [String: Any])
            ))
        case "item_completed":
            let item = payload["item"] as? [String: Any]
            return .itemCompleted(ItemCompletedEvent(
                turnId: payload["turn_id"] as? String ?? "",
                itemType: item?["type"] as? String ?? "",
                startedAtMs: double(payload["started_at_ms"]),
                completedAtMs: double(payload["completed_at_ms"])
            ))
        case "thread_settings_applied":
            let settings = payload["thread_settings"] as? [String: Any]
            return .threadSettings(ThreadSettingsEvent(
                model: settings?["model"] as? String,
                reasoningEffort: settings?["reasoning_effort"] as? String,
                serviceTier: settings?["service_tier"] as? String,
                provider: settings?["model_provider_id"] as? String
            ))
        default:
            return nil
        }
    }

    private static func usage(from object: [String: Any]?) -> TokenUsage {
        guard let object else { return .zero }
        return TokenUsage(
            inputTokens: int(object["input_tokens"]),
            cachedInputTokens: int(object["cached_input_tokens"]),
            cacheWriteInputTokens: int(object["cache_write_input_tokens"]),
            outputTokens: int(object["output_tokens"]),
            reasoningOutputTokens: int(object["reasoning_output_tokens"]),
            totalTokens: int(object["total_tokens"])
        )
    }

    private static func rateLimits(from object: [String: Any]?) -> RateLimitSnapshot? {
        guard let object else { return nil }
        return RateLimitSnapshot(
            limitId: object["limit_id"] as? String ?? object["limitId"] as? String,
            primary: window(object["primary"] as? [String: Any]),
            secondary: window(object["secondary"] as? [String: Any]),
            planType: object["plan_type"] as? String ?? object["planType"] as? String
        )
    }

    private static func window(_ object: [String: Any]?) -> RateLimitWindow? {
        guard let object else { return nil }
        guard let used = double(object["used_percent"]) else { return nil }
        return RateLimitWindow(
            usedPercent: used,
            windowDurationMins: double(object["window_minutes"]),
            resetsAt: int(object["resets_at"])
        )
    }

    private static func int(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }

    private static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
