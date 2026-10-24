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
            guard let turnId = nonEmptyString(payload["turn_id"] as? String) else { return nil }
            return .turnContext(TurnContextEvent(
                turnId: turnId,
                model: nonEmptyString(payload["model"] as? String),
                reasoningEffort: nonEmptyString(payload["effort"] as? String),
                compHash: nonEmptyString(payload["comp_hash"] as? String)
            ))
        case "token_usage_record":
            // TokenUsageRecordEvent has non-optional usage snapshots. A record missing
            // any of them is structurally incomplete, so fail closed instead of
            // inventing zero usage. Zero is only produced for a present-but-empty object.
            guard let turnId = nonEmptyString(payload["turn_id"] as? String),
                  let responseId = nonEmptyString(payload["response_id"] as? String),
                  let usageObject = payload["usage"] as? [String: Any],
                  let turnUsageObject = payload["turn_token_usage"] as? [String: Any],
                  let threadUsageObject = payload["thread_token_usage"] as? [String: Any] else {
                return nil
            }
            return .tokenUsageRecord(TokenUsageRecordEvent(
                timestamp: timestamp,
                turnId: turnId,
                responseId: responseId,
                usage: usage(from: usageObject),
                turnTokenUsage: usage(from: turnUsageObject),
                threadTokenUsage: usage(from: threadUsageObject)
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
            guard let turnId = nonEmptyString(payload["turn_id"] as? String) else { return nil }
            return .taskStarted(TaskStartedEvent(
                turnId: turnId,
                startedAt: DateParsing.epochSeconds(payload["started_at"]) ?? timestamp
            ))
        case "task_complete":
            guard let turnId = nonEmptyString(payload["turn_id"] as? String) else { return nil }
            return .taskComplete(TaskCompleteEvent(
                turnId: turnId,
                durationMs: double(payload["duration_ms"]),
                ttftMs: double(payload["time_to_first_token_ms"]),
                completedAt: timestamp
            ))
        case "token_count":
            let info = payload["info"] as? [String: Any]
            let rateLimits = rateLimits(from: payload["rate_limits"] as? [String: Any])
            guard info != nil || rateLimits != nil else { return nil }
            return .tokenCount(TokenCountEvent(
                lastUsage: usageIfPresent(from: info?["last_token_usage"] as? [String: Any]),
                totalUsage: usageIfPresent(from: info?["total_token_usage"] as? [String: Any]),
                modelContextWindow: intIfPresent(info?["model_context_window"]),
                rateLimits: rateLimits
            ))
        case "item_completed":
            guard let turnId = nonEmptyString(payload["turn_id"] as? String),
                  let item = payload["item"] as? [String: Any],
                  let itemType = nonEmptyString(item["type"] as? String) else {
                return nil
            }
            return .itemCompleted(ItemCompletedEvent(
                turnId: turnId,
                itemType: itemType,
                startedAtMs: double(payload["started_at_ms"]),
                completedAtMs: double(payload["completed_at_ms"])
            ))
        case "thread_settings_applied":
            guard let settings = payload["thread_settings"] as? [String: Any] else { return nil }
            let model = nonEmptyString(settings["model"] as? String)
            let reasoningEffort = nonEmptyString(settings["reasoning_effort"] as? String)
            let serviceTier = nonEmptyString(settings["service_tier"] as? String)
            let provider = nonEmptyString(settings["model_provider_id"] as? String)
            guard model != nil || reasoningEffort != nil || serviceTier != nil || provider != nil else {
                return nil
            }
            return .threadSettings(ThreadSettingsEvent(
                model: model,
                reasoningEffort: reasoningEffort,
                serviceTier: serviceTier,
                provider: provider
            ))
        default:
            return nil
        }
    }

    private static func usageIfPresent(from object: [String: Any]?) -> TokenUsage? {
        guard let object else { return nil }
        return usage(from: object)
    }

    private static func usage(from object: [String: Any]) -> TokenUsage {
        TokenUsage(
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
            resetsAt: intIfPresent(object["resets_at"])
        )
    }

    private static func int(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }

    private static func intIfPresent(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func nonEmptyString(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
