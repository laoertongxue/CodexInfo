import Foundation
import CodexInfoCore

func registerCoreTests() {
    test("CredentialStore parses top-level access token") { context in
        let data = #"{"access_token":"tok_test"}"#.data(using: .utf8)!
        let credentials = try FileCredentialStore.parse(data)
        context.expectEqual(credentials.accessToken, "tok_test")
    }

    test("CredentialStore parses nested tokens access token") { context in
        let data = #"{"tokens":{"access_token":"tok_nested"}}"#.data(using: .utf8)!
        let credentials = try FileCredentialStore.parse(data)
        context.expectEqual(credentials.accessToken, "tok_nested")
    }

    test("CredentialStore rejects missing token") { context in
        let data = #"{"tokens":{}}"#.data(using: .utf8)!
        context.expectThrows(try FileCredentialStore.parse(data))
    }

    test("RateLimitWindowSelector finds weekly window in secondary slot") { context in
        let snapshot = RateLimitSnapshot(
            limitId: "codex",
            primary: RateLimitWindow(usedPercent: 10, windowDurationMins: 300, resetsAt: 100),
            secondary: RateLimitWindow(usedPercent: 16, windowDurationMins: 10_080, resetsAt: 200),
            planType: "pro"
        )
        let weekly = RateLimitWindowSelector.weekly(from: snapshot)
        context.expectEqual(weekly?.remainingPercent, 84)
        context.expectEqual(weekly?.resetsAt, 200)
    }

    test("RateLimitWindowSelector finds weekly window in primary slot") { context in
        let snapshot = RateLimitSnapshot(
            limitId: "codex",
            primary: RateLimitWindow(usedPercent: 100, windowDurationMins: 10_080, resetsAt: 300),
            secondary: nil,
            planType: "pro"
        )
        context.expectEqual(RateLimitWindowSelector.weekly(from: snapshot)?.remainingPercent, 0)
    }

    test("RateLimitWindowSelector returns nil when only five-hour window exists") { context in
        let snapshot = RateLimitSnapshot(
            limitId: "codex",
            primary: RateLimitWindow(usedPercent: 5, windowDurationMins: 300, resetsAt: nil),
            secondary: nil,
            planType: "pro"
        )
        context.expectEqual(RateLimitWindowSelector.weekly(from: snapshot), nil)
    }

    test("RateLimitWindowSelector clamps used percent") { context in
        let high = RateLimitWindow(usedPercent: 140, windowDurationMins: 10_080, resetsAt: nil)
        let low = RateLimitWindow(usedPercent: -20, windowDurationMins: 10_080, resetsAt: nil)
        context.expectEqual(high.remainingPercent, 0)
        context.expectEqual(low.remainingPercent, 100)
    }

    test("RateLimitBucketSelector filters limit id codex") { context in
        let codex = RateLimitSnapshot(limitId: "codex", primary: nil, secondary: nil, planType: "pro")
        let decoy = RateLimitSnapshot(limitId: "codex_bengalfox", primary: nil, secondary: nil, planType: "pro")
        let selected = RateLimitBucketSelector.select(["decoy": decoy, "codex": codex])
        context.expectEqual(selected?.limitId, "codex")
    }

    test("Quota official client sends bearer token and maps weekly quota") { context in
        let http = MockHTTPClient(response: HTTPResponse(
            data: #"{"plan_type":"pro","rate_limits":{"limit_id":"codex","primary":{"used_percent":16,"window_minutes":10080,"resets_at":200},"secondary":null}}"#.data(using: .utf8)!,
            statusCode: 200
        ))
        let client = OfficialUsageClient(
            http: http,
            credentials: StubCredentials(token: "tok_test"),
            baseURL: URL(string: "https://chatgpt.com/backend-api")!
        )
        let usage = try await client.fetchUsage()
        context.expectEqual(usage.planType, "pro")
        context.expectEqual(usage.rateLimits?.limitId, "codex")
        context.expectEqual(RateLimitWindowSelector.weekly(from: usage.rateLimits!)?.remainingPercent, 84)
        context.expectEqual(http.lastRequest?.url?.path, "/backend-api/wham/usage")
        context.expectEqual(http.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer tok_test")
    }

    test("QuotaService uses fallback when official request fails") { context in
        let http = MockHTTPClient(error: HTTPError.status(500))
        let client = OfficialUsageClient(http: http, credentials: StubCredentials(token: "tok_test"), baseURL: URL(string: "https://chatgpt.com/backend-api")!)
        let fallback = StubQuotaFallback(snapshot: QuotaSnapshot(
            planType: "pro",
            weeklyRemainingPercent: 72,
            weeklyResetsAt: Date(timeIntervalSince1970: 300),
            source: .session,
            fetchedAt: Date(timeIntervalSince1970: 100)
        ))
        let service = QuotaService(official: client, fallback: fallback)
        let snapshot = await service.quotaSnapshot(now: Date(timeIntervalSince1970: 100))
        context.expectEqual(snapshot?.weeklyRemainingPercent, 72)
        context.expectEqual(snapshot?.source, .session)
    }

    test("QuotaService caches official result for 60 seconds") { context in
        let http = MockHTTPClient(response: HTTPResponse(
            data: #"{"plan_type":"pro","rate_limits":{"limit_id":"codex","primary":{"used_percent":16,"window_minutes":10080,"resets_at":200},"secondary":null}}"#.data(using: .utf8)!,
            statusCode: 200
        ))
        let client = OfficialUsageClient(http: http, credentials: StubCredentials(token: "tok_test"), baseURL: URL(string: "https://chatgpt.com/backend-api")!)
        let service = QuotaService(official: client, fallback: nil)
        _ = await service.quotaSnapshot(now: Date(timeIntervalSince1970: 100))
        _ = await service.quotaSnapshot(now: Date(timeIntervalSince1970: 130))
        context.expectEqual(http.requestCount, 1)
    }

    test("Reset credits sort by expiry and filter expired cards") { context in
        let now = DateParsing.iso8601("2026-10-24T00:00:00Z")!
        let response = #"{"available_count":3,"credits":[{"id":"card_123456","status":"available","granted_at":"2026-10-01T00:00:00Z","expires_at":"2026-11-07T07:55:00+08:00","title":"later"},{"id":"card_654321","status":"available","granted_at":"2026-10-01T00:00:00Z","expires_at":"2026-10-20T07:55:00+08:00","title":"expired"},{"id":"card_999999","status":"redeemed","granted_at":"2026-10-01T00:00:00Z","expires_at":"2026-12-07T07:55:00+08:00","title":"used"}]}"#
        let http = MockHTTPClient(response: HTTPResponse(data: response.data(using: .utf8)!, statusCode: 200))
        let client = OfficialResetCreditsClient(http: http, credentials: StubCredentials(token: "tok_test"), baseURL: URL(string: "https://chatgpt.com/backend-api")!)
        let snapshot = try await client.fetch(now: now)
        context.expectEqual(snapshot.availableCount, 1)
        context.expectEqual(snapshot.reportedAvailableCount, 3)
        context.expectEqual(snapshot.items.first?.title, "later")
        context.expectEqual(snapshot.items.first?.idSuffix, "123456")
        context.expectEqual(http.lastRequest?.url?.path, "/backend-api/wham/rate-limit-reset-credits")
    }

    test("ResetCreditService falls back when official request fails") { context in
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let http = MockHTTPClient(error: HTTPError.status(500))
        let client = OfficialResetCreditsClient(http: http, credentials: StubCredentials(token: "tok_test"), baseURL: URL(string: "https://chatgpt.com/backend-api")!)
        let fallback = StubResetCreditFallback(snapshot: ResetCreditsSnapshot(
            availableCount: 1,
            reportedAvailableCount: nil,
            items: [ResetCredit(id: "fallback000001", status: "available", grantedAt: nil, expiresAt: nil, title: "fallback")],
            fetchedAt: now
        ))
        let service = ResetCreditService(official: client, fallback: fallback)
        let snapshot = await service.creditsSnapshot(now: now)
        context.expectEqual(snapshot?.availableCount, 1)
        context.expectEqual(snapshot?.items.first?.title, "fallback")
    }

    test("SessionLogParser reads token usage and task completion") { context in
        let usageLine = #"{"timestamp":"2026-10-24T02:48:22.880Z","type":"token_usage_record","payload":{"turn_id":"turn-1","response_id":"resp-1","usage":{"input_tokens":100,"cached_input_tokens":80,"cache_write_input_tokens":0,"output_tokens":50,"reasoning_output_tokens":10,"total_tokens":150},"turn_token_usage":{"input_tokens":100,"cached_input_tokens":80,"cache_write_input_tokens":0,"output_tokens":50,"reasoning_output_tokens":10,"total_tokens":150},"thread_token_usage":{"input_tokens":100,"cached_input_tokens":80,"cache_write_input_tokens":0,"output_tokens":50,"reasoning_output_tokens":10,"total_tokens":150}}}"#
        guard case .tokenUsageRecord(let record)? = SessionLogParser.parse(line: Data(usageLine.utf8)) else {
            context.fail("expected tokenUsageRecord")
            return
        }
        context.expectEqual(record.turnId, "turn-1")
        context.expectEqual(record.responseId, "resp-1")
        context.expectEqual(record.usage.outputTokens, 50)
        context.expectEqual(record.usage.cachedInputTokens, 80)

        let completeLine = #"{"timestamp":"2026-10-24T02:51:08.576Z","type":"event_msg","payload":{"type":"task_complete","turn_id":"turn-1","duration_ms":171807,"time_to_first_token_ms":3991}}"#
        guard case .taskComplete(let complete)? = SessionLogParser.parse(line: Data(completeLine.utf8)) else {
            context.fail("expected taskComplete")
            return
        }
        context.expectEqual(complete.turnId, "turn-1")
        context.expectEqual(complete.durationMs, 171807)
        context.expectEqual(complete.ttftMs, 3991)
    }

    test("SessionLogParser reads item durations and thread settings") { context in
        let itemLine = #"{"timestamp":"2026-10-24T02:48:23.000Z","type":"event_msg","payload":{"type":"item_completed","turn_id":"turn-1","item":{"type":"Reasoning"},"started_at_ms":1000,"completed_at_ms":3000}}"#
        guard case .itemCompleted(let item)? = SessionLogParser.parse(line: Data(itemLine.utf8)) else {
            context.fail("expected itemCompleted")
            return
        }
        context.expectEqual(item.itemType, "Reasoning")
        context.expectEqual(item.startedAtMs, 1000)
        context.expectEqual(item.completedAtMs, 3000)

        let settingsLine = #"{"timestamp":"2026-10-24T02:48:18.321Z","type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"model":"gpt-6.1-sol","model_provider_id":"openai","service_tier":"default","reasoning_effort":"xhigh"}}}"#
        guard case .threadSettings(let settings)? = SessionLogParser.parse(line: Data(settingsLine.utf8)) else {
            context.fail("expected threadSettings")
            return
        }
        context.expectEqual(settings.model, "gpt-6.1-sol")
        context.expectEqual(settings.reasoningEffort, "xhigh")
        context.expectEqual(settings.serviceTier, "default")
        context.expectEqual(settings.provider, "openai")
    }

    test("SessionLogParser ignores response content events") { context in
        let line = #"{"timestamp":"2026-10-24T02:48:22.880Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"Text","text":"secret"}]}}"#
        context.expectEqual(SessionLogParser.parse(line: Data(line.utf8)), nil)
    }

    test("SessionLogParser event models accept public initializers") { context in
        let events: [SessionEvent] = [
            .threadSettings(ThreadSettingsEvent(model: "gpt-6.1-sol", reasoningEffort: "xhigh", serviceTier: "default", provider: "openai")),
            .turnContext(TurnContextEvent(turnId: "turn-1", model: "gpt-6.1-sol", reasoningEffort: "xhigh", compHash: "3000")),
            .taskStarted(TaskStartedEvent(turnId: "turn-1", startedAt: Date(timeIntervalSince1970: 100))),
            .tokenUsageRecord(TokenUsageRecordEvent(timestamp: nil, turnId: "turn-1", responseId: "resp-1", usage: .zero, turnTokenUsage: .zero, threadTokenUsage: .zero)),
            .taskComplete(TaskCompleteEvent(turnId: "turn-1", durationMs: 5_000, ttftMs: 500, completedAt: Date(timeIntervalSince1970: 105))),
            .tokenCount(TokenCountEvent(lastUsage: nil, totalUsage: nil, modelContextWindow: nil, rateLimits: nil)),
            .itemCompleted(ItemCompletedEvent(turnId: "turn-1", itemType: "Reasoning", startedAtMs: 1_000, completedAtMs: 2_000)),
            .compacted,
        ]
        context.expectEqual(events.count, 8)
    }

    test("SessionLogParser reads turn context token count and compaction") { context in
        let contextLine = #"{"timestamp":"2026-10-24T02:48:18.000Z","type":"turn_context","payload":{"turn_id":"turn-1","model":"gpt-6.1-sol","effort":"xhigh","comp_hash":"3000"}}"#
        guard case .turnContext(let turn)? = SessionLogParser.parse(line: Data(contextLine.utf8)) else {
            context.fail("expected turnContext")
            return
        }
        context.expectEqual(turn.turnId, "turn-1")
        context.expectEqual(turn.model, "gpt-6.1-sol")
        context.expectEqual(turn.reasoningEffort, "xhigh")
        context.expectEqual(turn.compHash, "3000")

        let countLine = #"{"timestamp":"2026-10-24T02:48:22.880Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"cached_input_tokens":5,"cache_write_input_tokens":1,"output_tokens":7,"reasoning_output_tokens":2,"total_tokens":20},"total_token_usage":{"input_tokens":100,"cached_input_tokens":80,"cache_write_input_tokens":0,"output_tokens":50,"reasoning_output_tokens":10,"total_tokens":150},"model_context_window":258400},"rate_limits":{"limit_id":"codex","primary":{"used_percent":16,"window_minutes":10080,"resets_at":200},"secondary":{"used_percent":5,"window_minutes":300,"resets_at":100},"plan_type":"pro"}}}"#
        guard case .tokenCount(let count)? = SessionLogParser.parse(line: Data(countLine.utf8)) else {
            context.fail("expected tokenCount")
            return
        }
        context.expectEqual(count.lastUsage?.outputTokens, 7)
        context.expectEqual(count.totalUsage?.outputTokens, 50)
        context.expectEqual(count.modelContextWindow, 258_400)
        context.expectEqual(count.rateLimits?.limitId, "codex")
        context.expectEqual(count.rateLimits?.planType, "pro")
        context.expectEqual(count.rateLimits?.primary?.usedPercent, 16)
        context.expectEqual(count.rateLimits?.primary?.windowDurationMins, 10_080)
        context.expectEqual(count.rateLimits?.primary?.resetsAt, 200)
        context.expectEqual(count.rateLimits?.secondary?.windowDurationMins, 300)

        let compactedLine = #"{"timestamp":"2026-10-24T02:50:00.000Z","type":"compacted","payload":{}}"#
        context.expectEqual(SessionLogParser.parse(line: Data(compactedLine.utf8)), SessionEvent.compacted)

        let unknownLine = #"{"timestamp":"2026-10-24T02:50:00.000Z","type":"event_msg","payload":{"type":"agent_reasoning"}}"#
        context.expectEqual(SessionLogParser.parse(line: Data(unknownLine.utf8)), nil)
    }

    test("SessionLogParser keeps missing optional values nil") { context in
        let countLine = #"{"timestamp":"2026-10-24T02:48:22.880Z","type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":null},"rate_limits":{"limit_id":"codex","primary":{"used_percent":16,"window_minutes":10080},"secondary":null,"plan_type":"pro"}}}"#
        guard case .tokenCount(let count)? = SessionLogParser.parse(line: Data(countLine.utf8)) else {
            context.fail("expected tokenCount")
            return
        }
        context.expectEqual(count.lastUsage, nil)
        context.expectEqual(count.totalUsage, nil)
        context.expectEqual(count.modelContextWindow, nil)
        context.expectEqual(count.rateLimits?.primary?.resetsAt, nil)
        context.expectEqual(count.rateLimits?.primary?.usedPercent, 16)
    }

    test("SessionLogParser keeps present empty usage objects as zero") { context in
        let line = #"{"timestamp":"2026-10-24T02:48:22.880Z","type":"token_usage_record","payload":{"turn_id":"turn-1","response_id":"resp-1","usage":{},"turn_token_usage":{},"thread_token_usage":{}}}"#
        guard case .tokenUsageRecord(let record)? = SessionLogParser.parse(line: Data(line.utf8)) else {
            context.fail("expected tokenUsageRecord")
            return
        }
        context.expectEqual(record.usage, TokenUsage.zero)
        context.expectEqual(record.turnTokenUsage, TokenUsage.zero)
        context.expectEqual(record.threadTokenUsage, TokenUsage.zero)
    }

    test("SessionLogParser rejects structurally incomplete events") { context in
        let lines = [
            #"{"type":"turn_context","payload":{"model":"gpt-6.1-sol"}}"#,
            #"{"type":"token_usage_record","payload":{"turn_id":"turn-1","response_id":"resp-1","usage":{}}}"#,
            #"{"type":"token_usage_record","payload":{"turn_id":"turn-1","usage":{},"turn_token_usage":{},"thread_token_usage":{}}}"#,
            #"{"type":"event_msg","payload":{"type":"task_started"}}"#,
            #"{"type":"event_msg","payload":{"type":"task_complete"}}"#,
            #"{"type":"event_msg","payload":{"type":"item_completed","turn_id":"turn-1"}}"#,
            #"{"type":"event_msg","payload":{"type":"item_completed","turn_id":"turn-1","item":{}}}"#,
            #"{"type":"event_msg","payload":{"type":"thread_settings_applied"}}"#,
            #"{"type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{}}}"#,
            #"{"type":"event_msg","payload":{"type":"token_count"}}"#,
        ]
        for line in lines {
            context.expectEqual(SessionLogParser.parse(line: Data(line.utf8)), nil, line)
        }
    }

    test("TurnAggregator deduplicates responses and sums model time") { context in
        let events: [SessionEvent] = [
            .threadSettings(ThreadSettingsEvent(model: "gpt-6.1-sol", reasoningEffort: "xhigh", serviceTier: "default", provider: "openai")),
            .turnContext(TurnContextEvent(turnId: "turn-1", model: "gpt-6.1-sol", reasoningEffort: "xhigh", compHash: "3000")),
            .taskStarted(TaskStartedEvent(turnId: "turn-1", startedAt: Date(timeIntervalSince1970: 100))),
            .tokenUsageRecord(TokenUsageRecordEvent(timestamp: nil, turnId: "turn-1", responseId: "resp-1", usage: TokenUsage(inputTokens: 100, cachedInputTokens: 80, cacheWriteInputTokens: 0, outputTokens: 50, reasoningOutputTokens: 10, totalTokens: 150), turnTokenUsage: .zero, threadTokenUsage: .zero)),
            .tokenUsageRecord(TokenUsageRecordEvent(timestamp: nil, turnId: "turn-1", responseId: "resp-1", usage: TokenUsage(inputTokens: 100, cachedInputTokens: 80, cacheWriteInputTokens: 0, outputTokens: 50, reasoningOutputTokens: 10, totalTokens: 150), turnTokenUsage: .zero, threadTokenUsage: .zero)),
            .tokenUsageRecord(TokenUsageRecordEvent(timestamp: nil, turnId: "turn-1", responseId: "resp-2", usage: TokenUsage(inputTokens: 20, cachedInputTokens: 10, cacheWriteInputTokens: 0, outputTokens: 50, reasoningOutputTokens: 0, totalTokens: 70), turnTokenUsage: .zero, threadTokenUsage: .zero)),
            .itemCompleted(ItemCompletedEvent(turnId: "turn-1", itemType: "Reasoning", startedAtMs: 1_000, completedAtMs: 2_000)),
            .itemCompleted(ItemCompletedEvent(turnId: "turn-1", itemType: "AgentMessage", startedAtMs: 2_000, completedAtMs: 3_000)),
            .itemCompleted(ItemCompletedEvent(turnId: "turn-1", itemType: "CommandExecution", startedAtMs: 3_000, completedAtMs: 4_000)),
            .itemCompleted(ItemCompletedEvent(turnId: "turn-1", itemType: "McpToolCall", startedAtMs: 4_000, completedAtMs: 4_500)),
            .taskComplete(TaskCompleteEvent(turnId: "turn-1", durationMs: 5_000, ttftMs: 500, completedAt: Date(timeIntervalSince1970: 105))),
        ]
        let aggregate = TurnAggregator.aggregate(events)
        context.expectEqual(aggregate.turns.count, 1)
        let turn = aggregate.turns[0]
        context.expectEqual(turn.outputTokens, 100)
        context.expectEqual(turn.inputTokens, 120)
        context.expectEqual(turn.cachedInputTokens, 90)
        context.expectEqual(turn.reasoningOutputTokens, 10)
        context.expectEqual(turn.modelItemMs, 2_000)
        context.expectEqual(turn.toolMs, 1_500)
        context.expectEqual(turn.toolCallCount, 2)
        context.expectTrue(turn.isCompleted)
        context.expectEqual(turn.model, "gpt-6.1-sol")
        context.expectEqual(turn.serviceTier, "default")
    }

    test("OutputRateCalculator uses model item time and median") { context in
        let turn = TurnMetrics(
            turnId: "turn-1",
            model: "gpt-6.1-sol",
            reasoningEffort: "xhigh",
            serviceTier: "default",
            provider: "openai",
            compHash: "3000",
            startedAt: nil,
            completedAt: nil,
            durationMs: 5_000,
            ttftMs: 500,
            inputTokens: 100,
            cachedInputTokens: 0,
            outputTokens: 100,
            reasoningOutputTokens: 20,
            modelItemMs: 2_000,
            toolMs: 1_000,
            toolCallCount: 2,
            isCompleted: true
        )
        let rate = OutputRateCalculator.rate(for: turn)
        context.expectTrue(abs((rate?.tokensPerSecond ?? 0) - 50) < 0.01)
        context.expectTrue(abs((rate?.reasoningShare ?? 0) - 0.2) < 0.0001)
        context.expectTrue(abs((rate?.toolDensity ?? 0) - 20) < 0.0001)

        let clamped = OutputRateCalculator.rate(for: TurnMetrics(
            turnId: "turn-clamp", model: nil, reasoningEffort: nil, serviceTier: nil, provider: nil, compHash: nil,
            startedAt: nil, completedAt: nil, durationMs: 1_000, ttftMs: 0,
            inputTokens: 0, cachedInputTokens: 0, outputTokens: 100, reasoningOutputTokens: 0,
            modelItemMs: 2_000, toolMs: 0, toolCallCount: 0, isCompleted: true
        ))
        context.expectTrue(abs((clamped?.tokensPerSecond ?? 0) - 100) < 0.01)

        context.expectEqual(OutputRateCalculator.medianRate([
            TurnMetrics(turnId: "a", model: nil, reasoningEffort: nil, serviceTier: nil, provider: nil, compHash: nil, startedAt: nil, completedAt: nil, durationMs: 1_000, ttftMs: 0, inputTokens: 0, cachedInputTokens: 0, outputTokens: 10, reasoningOutputTokens: 0, modelItemMs: 1_000, toolMs: 0, toolCallCount: 0, isCompleted: true),
            TurnMetrics(turnId: "b", model: nil, reasoningEffort: nil, serviceTier: nil, provider: nil, compHash: nil, startedAt: nil, completedAt: nil, durationMs: 1_000, ttftMs: 0, inputTokens: 0, cachedInputTokens: 0, outputTokens: 20, reasoningOutputTokens: 0, modelItemMs: 1_000, toolMs: 0, toolCallCount: 0, isCompleted: true),
            TurnMetrics(turnId: "c", model: nil, reasoningEffort: nil, serviceTier: nil, provider: nil, compHash: nil, startedAt: nil, completedAt: nil, durationMs: 1_000, ttftMs: 0, inputTokens: 0, cachedInputTokens: 0, outputTokens: 30, reasoningOutputTokens: 0, modelItemMs: 1_000, toolMs: 0, toolCallCount: 0, isCompleted: true)
        ]), 20)
    }

    test("OutputRateCalculator falls back to wall time minus tool time") { context in
        let turn = TurnMetrics(
            turnId: "turn-2", model: nil, reasoningEffort: nil, serviceTier: nil, provider: nil, compHash: nil,
            startedAt: nil, completedAt: nil, durationMs: 5_000, ttftMs: 500,
            inputTokens: 0, cachedInputTokens: 0, outputTokens: 100, reasoningOutputTokens: 0,
            modelItemMs: 0, toolMs: 1_000, toolCallCount: 1, isCompleted: true
        )
        let rate = OutputRateCalculator.rate(for: turn)
        context.expectTrue(abs((rate?.tokensPerSecond ?? 0) - 28.5714) < 0.01)
    }

    test("AppServerQuotaFallback reads weekly quota from app-server") { context in
        let fake = FakeAppServerTransport(result: [
            "rateLimits": [
                "limitId": "codex",
                "primary": ["used_percent": 10, "window_minutes": 300, "resets_at": 100],
                "secondary": ["used_percent": 30, "window_minutes": 10080, "resets_at": 200],
            ],
        ])
        let client = CodexAppServerClient(transport: fake)
        let fallback = AppServerQuotaFallback(client: client)
        let snapshot = await fallback.fallbackQuota(now: Date(timeIntervalSince1970: 1_790_000_000))
        context.expectEqual(snapshot?.weeklyRemainingPercent, 70)
        context.expectEqual(snapshot?.source, .appServer)
        context.expectEqual(fake.requests.map(\.method), ["initialize", "account/rateLimits/read"])
    }

    test("Quota official client decodes camelCase rate limit fields") { context in
        let http = MockHTTPClient(response: HTTPResponse(
            data: #"{"planType":"pro","rateLimits":{"limitId":"codex","primary":{"usedPercent":16,"windowDurationMins":10080,"resetsAt":200},"secondary":null}}"#.data(using: .utf8)!,
            statusCode: 200
        ))
        let client = OfficialUsageClient(
            http: http,
            credentials: StubCredentials(token: "tok_test"),
            baseURL: URL(string: "https://chatgpt.com/backend-api")!
        )
        let usage = try await client.fetchUsage()
        let weekly = usage.rateLimits.flatMap(RateLimitWindowSelector.weekly)
        context.expectEqual(weekly?.remainingPercent, 84)
        context.expectEqual(weekly?.windowDurationMins, 10_080)
        context.expectEqual(weekly?.resetsAt, 200)
        context.expectEqual(usage.rateLimits?.limitId, "codex")
    }

    test("AppServer client initializes exactly once for concurrent reads") { context in
        let fake = FakeAppServerTransport(
            result: [
                "rateLimits": [
                    "limitId": "codex",
                    "primary": ["used_percent": 10, "window_minutes": 10080, "resets_at": 100],
                ],
            ],
            initializeDelay: 0.05
        )
        let client = CodexAppServerClient(transport: fake)
        async let first = client.readRateLimits()
        async let second = client.readRateLimits()
        let (a, b) = try await (first, second)
        context.expectEqual(a.rateLimits?.limitId, "codex")
        context.expectEqual(b.rateLimits?.limitId, "codex")
        context.expectEqual(fake.requests.filter { $0.method == "initialize" }.count, 1)
        context.expectEqual(fake.requests.filter { $0.method == "account/rateLimits/read" }.count, 2)
    }

    test("AppServer client retries initialization after failure") { context in
        let fake = FakeAppServerTransport(
            result: [
                "rateLimits": [
                    "limitId": "codex",
                    "primary": ["used_percent": 10, "window_minutes": 10080, "resets_at": 100],
                ],
            ],
            initializeFailures: 1
        )
        let client = CodexAppServerClient(transport: fake)
        var firstError: Error?
        do {
            _ = try await client.readRateLimits()
        } catch {
            firstError = error
        }
        context.expectEqual(firstError as? AppServerError, .notRunning)
        let result = try await client.readRateLimits()
        context.expectEqual(result.rateLimits?.limitId, "codex")
        context.expectEqual(fake.requests.filter { $0.method == "initialize" }.count, 2)
    }

    test("AppServerProcessTransport completes a request") { context in
        let script = try makeAppServerScript(
            "#!/bin/sh\nread line\nprintf '{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"ok\":true}}\\n'\n"
        )
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
        let transport = try ProcessAppServerTransport(binaryURL: script, timeout: 5)
        defer { transport.close() }

        let result = try await transport.request(method: "initialize", params: [:])
        context.expectEqual(result["ok"] as? Bool, true)
    }

    test("AppServerProcessTransport times out a non-responsive child") { context in
        let script = try makeAppServerScript("#!/bin/sh\nexec sleep 30\n")
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
        let transport = try ProcessAppServerTransport(binaryURL: script, timeout: 0.3)
        defer { transport.close() }

        let start = Date()
        var caught: Error?
        do {
            _ = try await transport.request(method: "initialize", params: [:])
        } catch {
            caught = error
        }
        let elapsed = Date().timeIntervalSince(start)
        context.expectEqual(caught as? AppServerError, .timeout)
        context.expectTrue(elapsed < 5, "timeout took \(elapsed)s")

        // The blocked serial read must have been released by terminating the
        // child: the next queued request fails fast instead of hanging again.
        let retryStart = Date()
        var retryError: Error?
        do {
            _ = try await transport.request(method: "account/rateLimits/read", params: [:])
        } catch {
            retryError = error
        }
        let retryElapsed = Date().timeIntervalSince(retryStart)
        context.expectEqual(retryError as? AppServerError, .notRunning)
        context.expectTrue(retryElapsed < 2, "second request waited \(retryElapsed)s")
    }

    test("AppServerProcessTransport reports an early exit") { context in
        let transport = try ProcessAppServerTransport(
            binaryURL: URL(fileURLWithPath: "/usr/bin/true"),
            timeout: 5
        )
        defer { transport.close() }

        let start = Date()
        var caught: Error?
        do {
            _ = try await transport.request(method: "initialize", params: [:])
        } catch {
            caught = error
        }
        let elapsed = Date().timeIntervalSince(start)
        context.expectEqual(caught as? AppServerError, .notRunning)
        context.expectTrue(elapsed < 3, "early exit took \(elapsed)s")
    }

    test("AppServerProcessTransport drains stderr without blocking") { context in
        let script = try makeAppServerScript(
            "#!/bin/sh\nyes x | head -c 262144 >&2\nread line\nprintf '{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"ok\":true}}\\n'\n"
        )
        defer { try? FileManager.default.removeItem(at: script.deletingLastPathComponent()) }
        let transport = try ProcessAppServerTransport(binaryURL: script, timeout: 5)
        defer { transport.close() }

        let result = try await transport.request(method: "initialize", params: [:])
        context.expectEqual(result["ok"] as? Bool, true)
    }

    test("SessionIndexer picks the newest session and reports context") { context in
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let older = directory.appendingPathComponent("older.jsonl")
        let newer = directory.appendingPathComponent("newer.jsonl")
        let threadSettings = #"{"timestamp":"2026-10-24T02:48:18.321Z","type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"model":"gpt-6.1-sol","model_provider_id":"openai","service_tier":"default","reasoning_effort":"xhigh"}}}"# + "\n"
        let contextLine = #"{"timestamp":"2026-10-24T02:48:23.310Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":80,"cache_write_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120},"total_token_usage":{"input_tokens":100,"cached_input_tokens":80,"cache_write_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120},"model_context_window":475000}}}"# + "\n"
        let newerContent = threadSettings
            + #"{"timestamp":"2026-10-24T02:48:19.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-1","started_at":1792810096}}"# + "\n"
            + #"{"timestamp":"2026-10-24T02:48:20.000Z","type":"token_usage_record","payload":{"turn_id":"turn-1","response_id":"resp-1","usage":{"input_tokens":100,"cached_input_tokens":80,"cache_write_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120},"turn_token_usage":{"input_tokens":100,"cached_input_tokens":80,"cache_write_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120},"thread_token_usage":{"input_tokens":100,"cached_input_tokens":80,"cache_write_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120}}}"# + "\n"
            + contextLine
        try "".write(to: older, atomically: true, encoding: .utf8)
        try newerContent.write(to: newer, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: older.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: newer.path)

        let indexer = SessionIndexer(rootURL: directory, cacheURL: nil)
        let indexes = await indexer.scan()
        context.expectEqual(indexes.count, 2)
        let latest = indexes.max { $0.modifiedAt < $1.modifiedAt }
        context.expectEqual(latest?.path.hasSuffix("newer.jsonl"), true)
        context.expectEqual(latest?.isActive, true)
        context.expectEqual(latest?.contextTokens, 120)
        context.expectEqual(latest?.contextWindow, 475000)

        let repository = SessionRepository(indexer: indexer)
        let snapshot = await repository.currentSnapshot(now: Date(timeIntervalSince1970: 1_790_000_000))
        context.expectEqual(snapshot?.label, "当前会话")
        context.expectEqual(snapshot?.contextTokens, 120)
        context.expectEqual(snapshot?.totalTokens, 120)
    }

    test("SessionIndex and SessionSnapshot are constructible from the test module") { context in
        let index = SessionIndex(
            path: "/tmp/session.jsonl",
            modifiedAt: Date(timeIntervalSince1970: 1_000),
            turns: [],
            isActive: true,
            model: "gpt-6.1-sol",
            reasoningEffort: "xhigh",
            serviceTier: "default",
            contextTokens: 120,
            contextWindow: 475_000,
            lastRateLimits: nil,
            selectedModel: "gpt-6.1-sol",
            selectedEffort: "xhigh",
            selectedServiceTier: "default",
            routeMismatch: false
        )
        let snapshot = SessionSnapshot(
            isActive: true,
            label: "当前会话",
            model: "gpt-6.1-sol",
            effort: "xhigh",
            serviceTier: "default",
            contextTokens: 120,
            contextWindow: 475_000,
            totalTokens: 120,
            inputTokens: 100,
            outputTokens: 20,
            cachedInputTokens: 80,
            reasoningOutputTokens: 0,
            outputTokensPerSecond: 42.3,
            medianOutputTokensPerSecond: 45.1,
            ttftMs: 3_900,
            turnCount: 1,
            routeMismatch: false
        )
        context.expectEqual(index.path, "/tmp/session.jsonl")
        context.expectEqual(index.contextTokens, 120)
        context.expectEqual(index.contextWindow, 475_000)
        context.expectEqual(index.isActive, true)
        context.expectEqual(snapshot.label, "当前会话")
        context.expectEqual(snapshot.totalTokens, 120)
        context.expectEqual(snapshot.turnCount, 1)
    }

    test("SessionIndexer re-reads a session rewritten with the same byte length") { context in
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("session.jsonl")

        func sessionContent(output: Int, total: Int) -> String {
            let usage = "{\"timestamp\":\"2026-10-24T02:48:20.000Z\",\"type\":\"token_usage_record\",\"payload\":{\"turn_id\":\"turn-1\",\"response_id\":\"resp-1\",\"usage\":{\"input_tokens\":100,\"cached_input_tokens\":80,\"cache_write_input_tokens\":0,\"output_tokens\":\(output),\"reasoning_output_tokens\":0,\"total_tokens\":\(total)},\"turn_token_usage\":{\"input_tokens\":100,\"cached_input_tokens\":80,\"cache_write_input_tokens\":0,\"output_tokens\":\(output),\"reasoning_output_tokens\":0,\"total_tokens\":\(total)},\"thread_token_usage\":{\"input_tokens\":100,\"cached_input_tokens\":80,\"cache_write_input_tokens\":0,\"output_tokens\":\(output),\"reasoning_output_tokens\":0,\"total_tokens\":\(total)}}}"
            let settings = "{\"timestamp\":\"2026-10-24T02:48:18.321Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"thread_settings_applied\",\"thread_settings\":{\"model\":\"gpt-6.1-sol\",\"model_provider_id\":\"openai\",\"service_tier\":\"default\",\"reasoning_effort\":\"xhigh\"}}}"
            let started = "{\"timestamp\":\"2026-10-24T02:48:19.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn-1\",\"started_at\":1792810096}}"
            let count = "{\"timestamp\":\"2026-10-24T02:48:23.310Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"last_token_usage\":{\"input_tokens\":100,\"cached_input_tokens\":80,\"cache_write_input_tokens\":0,\"output_tokens\":\(output),\"reasoning_output_tokens\":0,\"total_tokens\":\(total)},\"total_token_usage\":{\"input_tokens\":100,\"cached_input_tokens\":80,\"cache_write_input_tokens\":0,\"output_tokens\":\(output),\"reasoning_output_tokens\":0,\"total_tokens\":\(total)},\"model_context_window\":475000}}}"
            return [settings, started, usage, count].map { $0 + "\n" }.joined()
        }

        let original = sessionContent(output: 20, total: 120)
        let rewritten = sessionContent(output: 21, total: 121)
        context.expectEqual(rewritten.utf8.count, original.utf8.count)

        try original.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: file.path)
        let indexer = SessionIndexer(rootURL: directory, cacheURL: nil)
        let first = await indexer.scan()
        context.expectEqual(first.count, 1)
        context.expectEqual(first.first?.contextTokens, 120)
        context.expectEqual(first.first?.turns.first?.outputTokens, 20)

        try rewritten.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: file.path)
        let second = await indexer.scan()
        context.expectEqual(second.count, 1)
        context.expectEqual(second.first?.contextTokens, 121)
        context.expectEqual(second.first?.turns.first?.outputTokens, 21)
    }

    test("SessionIndexer counts appended events exactly once") { context in
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("session.jsonl")

        let head = "{\"timestamp\":\"2026-10-24T02:48:19.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn-1\",\"started_at\":1792810096}}\n"
            + "{\"timestamp\":\"2026-10-24T02:48:20.000Z\",\"type\":\"token_usage_record\",\"payload\":{\"turn_id\":\"turn-1\",\"response_id\":\"resp-1\",\"usage\":{\"input_tokens\":100,\"cached_input_tokens\":80,\"cache_write_input_tokens\":0,\"output_tokens\":20,\"reasoning_output_tokens\":0,\"total_tokens\":120},\"turn_token_usage\":{\"input_tokens\":100,\"cached_input_tokens\":80,\"cache_write_input_tokens\":0,\"output_tokens\":20,\"reasoning_output_tokens\":0,\"total_tokens\":120},\"thread_token_usage\":{\"input_tokens\":100,\"cached_input_tokens\":80,\"cache_write_input_tokens\":0,\"output_tokens\":20,\"reasoning_output_tokens\":0,\"total_tokens\":120}}}\n"
            + "{\"timestamp\":\"2026-10-24T02:48:21.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"item_completed\",\"turn_id\":\"turn-1\",\"item\":{\"type\":\"CommandExecution\"},\"started_at_ms\":1000,\"completed_at_ms\":2000}}\n"
            + "{\"timestamp\":\"2026-10-24T02:48:22.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"turn-1\",\"duration_ms\":5000,\"time_to_first_token_ms\":500}}\n"
        try head.write(to: file, atomically: true, encoding: .utf8)

        let indexer = SessionIndexer(rootURL: directory, cacheURL: nil)
        let first = await indexer.scan()
        context.expectEqual(first.count, 1)
        context.expectEqual(first.first?.turns.first?.outputTokens, 20)
        context.expectEqual(first.first?.turns.first?.toolCallCount, 1)

        let appended = "{\"timestamp\":\"2026-10-24T02:48:23.000Z\",\"type\":\"token_usage_record\",\"payload\":{\"turn_id\":\"turn-1\",\"response_id\":\"resp-2\",\"usage\":{\"input_tokens\":10,\"cached_input_tokens\":0,\"cache_write_input_tokens\":0,\"output_tokens\":5,\"reasoning_output_tokens\":0,\"total_tokens\":15},\"turn_token_usage\":{\"input_tokens\":10,\"cached_input_tokens\":0,\"cache_write_input_tokens\":0,\"output_tokens\":5,\"reasoning_output_tokens\":0,\"total_tokens\":15},\"thread_token_usage\":{\"input_tokens\":110,\"cached_input_tokens\":80,\"cache_write_input_tokens\":0,\"output_tokens\":25,\"reasoning_output_tokens\":0,\"total_tokens\":135}}}\n"
            + "{\"timestamp\":\"2026-10-24T02:48:24.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"item_completed\",\"turn_id\":\"turn-1\",\"item\":{\"type\":\"McpToolCall\"},\"started_at_ms\":3000,\"completed_at_ms\":4000}}\n"
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(appended.utf8))
        try handle.close()

        let second = await indexer.scan()
        context.expectEqual(second.count, 1)
        context.expectEqual(second.first?.turns.first?.outputTokens, 25)
        context.expectEqual(second.first?.turns.first?.toolCallCount, 2)

        // A third scan must not re-read or duplicate the appended region.
        let third = await indexer.scan()
        context.expectEqual(third.count, 1)
        context.expectEqual(third.first?.turns.first?.outputTokens, 25)
        context.expectEqual(third.first?.turns.first?.toolCallCount, 2)
    }

    test("SessionRepository prefers thread token totals and falls back to thread usage") { context in
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("session.jsonl")

        let content = "{\"timestamp\":\"2026-10-24T02:48:19.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn-1\",\"started_at\":1792810096}}\n"
            + "{\"timestamp\":\"2026-10-24T02:48:20.000Z\",\"type\":\"token_usage_record\",\"payload\":{\"turn_id\":\"turn-1\",\"response_id\":\"resp-1\",\"usage\":{\"input_tokens\":100,\"cached_input_tokens\":80,\"cache_write_input_tokens\":0,\"output_tokens\":20,\"reasoning_output_tokens\":0,\"total_tokens\":120},\"turn_token_usage\":{\"input_tokens\":200,\"cached_input_tokens\":80,\"cache_write_input_tokens\":0,\"output_tokens\":100,\"reasoning_output_tokens\":0,\"total_tokens\":300},\"thread_token_usage\":{\"input_tokens\":200,\"cached_input_tokens\":80,\"cache_write_input_tokens\":0,\"output_tokens\":100,\"reasoning_output_tokens\":0,\"total_tokens\":300}}}\n"
            + "{\"timestamp\":\"2026-10-24T02:48:23.310Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"model_context_window\":475000}}}\n"
        try content.write(to: file, atomically: true, encoding: .utf8)

        let indexer = SessionIndexer(rootURL: directory, cacheURL: nil)
        let indexes = await indexer.scan()
        // `last_token_usage` is missing, so the context falls back to the thread total.
        context.expectEqual(indexes.first?.contextTokens, 300)
        context.expectEqual(indexes.first?.contextWindow, 475_000)

        let repository = SessionRepository(indexer: indexer)
        let snapshot = await repository.currentSnapshot(now: Date(timeIntervalSince1970: 1_790_000_000))
        // The thread total wins over the deduplicated per-response sum of 120.
        context.expectEqual(snapshot?.totalTokens, 300)
        context.expectEqual(snapshot?.contextTokens, 300)
        context.expectEqual(snapshot?.inputTokens, 100)
        context.expectEqual(snapshot?.outputTokens, 20)
    }

    test("SessionIndexer prunes cache entries of deleted sessions") { context in
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("session.jsonl")
        let cacheURL = directory.appendingPathComponent("cache.json")
        let content = "{\"timestamp\":\"2026-10-24T02:48:19.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn-1\",\"started_at\":1792810096}}\n"
        try content.write(to: file, atomically: true, encoding: .utf8)

        let indexer = SessionIndexer(rootURL: directory, cacheURL: cacheURL)
        let first = await indexer.scan()
        context.expectEqual(first.count, 1)
        let cachedEntries = try JSONSerialization.jsonObject(with: Data(contentsOf: cacheURL)) as? [String: Any]
        context.expectEqual(cachedEntries?.count, 1)

        try FileManager.default.removeItem(at: file)
        let second = await indexer.scan()
        context.expectEqual(second.count, 0)
        let prunedEntries = try JSONSerialization.jsonObject(with: Data(contentsOf: cacheURL)) as? [String: Any]
        context.expectEqual(prunedEntries?.count, 0)
    }

    test("AccountUsageService uses official today total and local cumulative") { context in
        let today = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        let http = MockHTTPClient(response: HTTPResponse(
            data: #"{"days":[{"date":"2026-10-24","total_tokens":1234}]}"#.data(using: .utf8)!,
            statusCode: 200
        ))
        let official = OfficialUsageClient(http: http, credentials: StubCredentials(token: "tok_test"), baseURL: URL(string: "https://chatgpt.com/backend-api")!)
        let local = StubLocalAccount(today: 100, total: 999)
        let service = AccountUsageService(official: official, sessions: local, calendar: accountTestCalendar(timeZone: "UTC"))
        let snapshot = await service.accountSnapshot(now: today)
        context.expectEqual(snapshot?.todayTokens, 1234)
        context.expectEqual(snapshot?.totalTokens, 999)
    }

    test("AccountUsageService falls back to local totals") { context in
        let today = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        let http = MockHTTPClient(error: HTTPError.status(500))
        let official = OfficialUsageClient(http: http, credentials: StubCredentials(token: "tok_test"), baseURL: URL(string: "https://chatgpt.com/backend-api")!)
        let local = StubLocalAccount(today: 100, total: 999)
        let service = AccountUsageService(official: official, sessions: local, calendar: accountTestCalendar(timeZone: "UTC"))
        let snapshot = await service.accountSnapshot(now: today)
        context.expectEqual(snapshot?.todayTokens, 100)
        context.expectEqual(snapshot?.totalTokens, 999)
        context.expectEqual(snapshot?.source, "local")
    }

    test("Official daily usage request keeps the documented shape") { context in
        let http = MockHTTPClient(response: HTTPResponse(data: #"{"days":[]}"#.data(using: .utf8)!, statusCode: 200))
        let client = OfficialUsageClient(http: http, credentials: StubCredentials(token: "tok_test"), baseURL: URL(string: "https://chatgpt.com/backend-api")!)
        let start = DateParsing.iso8601("2026-10-24T00:00:00Z")!
        let end = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        let total = try await client.fetchDailyTokenUsage(start: start, end: end, calendar: accountTestCalendar(timeZone: "UTC"))
        context.expectEqual(total, 0)

        let request = http.lastRequest
        context.expectEqual(request?.httpMethod, "GET")
        context.expectEqual(request?.url?.path, "/backend-api/wham/usage/daily-token-usage-breakdown")
        context.expectEqual(requestQueryValue(request, name: "start_date"), "2026-10-24")
        context.expectEqual(requestQueryValue(request, name: "end_date"), "2026-10-24")
        context.expectEqual(requestQueryValue(request, name: "group_by"), "day")
        context.expectEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer tok_test")
        context.expectEqual(request?.value(forHTTPHeaderField: "Accept"), "application/json")
        context.expectEqual(request?.value(forHTTPHeaderField: "User-Agent"), AppConstants.userAgent)
        context.expectEqual(request?.value(forHTTPHeaderField: "x-openai-codex-usage-categories"), "1")
        context.expectEqual(request?.timeoutInterval, 10)
    }

    test("Official daily usage reads the recognized breakdown shapes") { context in
        let calendar = accountTestCalendar(timeZone: "UTC")
        let start = DateParsing.iso8601("2026-10-24T00:00:00Z")!
        let end = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        // Rows under "days" with the "total_tokens" spelling.
        context.expectEqual(try await officialDailyTotal(#"{"days":[{"date":"2026-10-24","total_tokens":1234}]}"#, calendar: calendar, start: start, end: end), 1234)
        // Rows under "data" with the "tokens" and "total" spellings.
        context.expectEqual(try await officialDailyTotal(#"{"data":[{"tokens":10},{"total":5}]}"#, calendar: calendar, start: start, end: end), 15)
        // Rows under "breakdown" with the "total" spelling.
        context.expectEqual(try await officialDailyTotal(#"{"breakdown":[{"total_tokens":7}]}"#, calendar: calendar, start: start, end: end), 7)
        // A summary payload without rows.
        context.expectEqual(try await officialDailyTotal(#"{"total_tokens":42}"#, calendar: calendar, start: start, end: end), 42)
        // A recognized breakdown without rows is a genuine zero.
        context.expectEqual(try await officialDailyTotal(#"{"days":[]}"#, calendar: calendar, start: start, end: end), 0)
        // A known container without rows is a recognized breakdown without usage.
        context.expectEqual(try await officialDailyTotal(#"{"days":null}"#, calendar: calendar, start: start, end: end), 0)
    }

    test("Official daily usage rejects an unknown payload shape") { context in
        let calendar = accountTestCalendar(timeZone: "UTC")
        let start = DateParsing.iso8601("2026-10-24T00:00:00Z")!
        let end = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        let unknown = [
            #"{"unknown":1}"#,
            #"{"days":{"2026-10-24":1234}}"#,
            #"{"days":[{"date":"2026-10-24"}]}"#,
            #"{"days":[{"date":"2026-10-24","total_tokens":"1234"}]}"#,
            #"{"days":[{"date":"2026-10-24","total_tokens":true}]}"#,
            #"{"total_tokens":"1234"}"#,
        ]
        for payload in unknown {
            do {
                _ = try await officialDailyTotal(payload, calendar: calendar, start: start, end: end)
                context.fail("expected invalidPayload for \(payload)")
            } catch let error as OfficialUsageError {
                context.expectEqual(error, .invalidPayload)
            } catch {
                context.fail("expected invalidPayload for \(payload), got \(error)")
            }
        }

        // An unreadable official payload degrades to the local numbers instead of
        // publishing a false zero.
        let http = MockHTTPClient(response: HTTPResponse(data: #"{"unknown":1}"#.data(using: .utf8)!, statusCode: 200))
        let official = OfficialUsageClient(http: http, credentials: StubCredentials(token: "tok_test"), baseURL: URL(string: "https://chatgpt.com/backend-api")!)
        let service = AccountUsageService(official: official, sessions: StubLocalAccount(today: 100, total: 999), calendar: calendar)
        let snapshot = await service.accountSnapshot(now: end)
        context.expectEqual(snapshot?.todayTokens, 100)
        context.expectEqual(snapshot?.totalTokens, 999)
        context.expectEqual(snapshot?.source, "local")
    }

    test("Official daily usage renders the start date in the injected time zone") { context in
        let instant = DateParsing.iso8601("2026-10-23T20:00:00Z")!
        let utc = MockHTTPClient(response: HTTPResponse(data: #"{"days":[]}"#.data(using: .utf8)!, statusCode: 200))
        let utcClient = OfficialUsageClient(http: utc, credentials: StubCredentials(token: "tok_test"), baseURL: URL(string: "https://chatgpt.com/backend-api")!)
        _ = try await utcClient.fetchDailyTokenUsage(start: instant, end: instant, calendar: accountTestCalendar(timeZone: "UTC"))
        let shanghai = MockHTTPClient(response: HTTPResponse(data: #"{"days":[]}"#.data(using: .utf8)!, statusCode: 200))
        let shanghaiClient = OfficialUsageClient(http: shanghai, credentials: StubCredentials(token: "tok_test"), baseURL: URL(string: "https://chatgpt.com/backend-api")!)
        _ = try await shanghaiClient.fetchDailyTokenUsage(start: instant, end: instant, calendar: accountTestCalendar(timeZone: "Asia/Shanghai"))

        context.expectEqual(requestQueryValue(utc.lastRequest, name: "start_date"), "2026-10-23")
        context.expectEqual(requestQueryValue(shanghai.lastRequest, name: "start_date"), "2026-10-24")
    }

    test("Official daily usage excludes rows of another date") { context in
        let calendar = accountTestCalendar(timeZone: "UTC")
        let start = DateParsing.iso8601("2026-10-24T00:00:00Z")!
        let end = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        // Only the rows of the requested day count.
        let mixed = try await officialDailyTotal(
            #"{"days":[{"date":"2026-10-23","total_tokens":500},{"date":"2026-10-24","total_tokens":1234}]}"#,
            calendar: calendar, start: start, end: end
        )
        context.expectEqual(mixed, 1234)
        // A breakdown whose rows all belong to another day has no usage today.
        let other = try await officialDailyTotal(#"{"days":[{"date":"2026-10-23","total_tokens":500}]}"#, calendar: calendar, start: start, end: end)
        context.expectEqual(other, 0)
        // Without a date on the rows every row is summed.
        let undated = try await officialDailyTotal(#"{"days":[{"total_tokens":10},{"total_tokens":5}]}"#, calendar: calendar, start: start, end: end)
        context.expectEqual(undated, 15)
    }

    test("Account service drops the cached snapshot when the local day changes") { context in
        let calendar = accountTestCalendar(timeZone: "UTC")
        let http = MockHTTPClient(response: HTTPResponse(
            data: #"{"days":[{"date":"2026-10-24","total_tokens":1234}]}"#.data(using: .utf8)!,
            statusCode: 200
        ))
        let official = OfficialUsageClient(http: http, credentials: StubCredentials(token: "tok_test"), baseURL: URL(string: "https://chatgpt.com/backend-api")!)
        let service = AccountUsageService(official: official, sessions: StubLocalAccount(today: 100, total: 999), calendar: calendar)
        // Two minutes apart, but the local day rolled over in between.
        _ = await service.accountSnapshot(now: DateParsing.iso8601("2026-10-24T23:59:00Z")!)
        _ = await service.accountSnapshot(now: DateParsing.iso8601("2026-10-25T00:01:00Z")!)
        context.expectEqual(http.requestCount, 2)
    }

    test("Account service bypasses the cache on a forced refresh") { context in
        let calendar = accountTestCalendar(timeZone: "UTC")
        let http = MockHTTPClient(response: HTTPResponse(
            data: #"{"days":[{"date":"2026-10-24","total_tokens":1234}]}"#.data(using: .utf8)!,
            statusCode: 200
        ))
        let official = OfficialUsageClient(http: http, credentials: StubCredentials(token: "tok_test"), baseURL: URL(string: "https://chatgpt.com/backend-api")!)
        let service = AccountUsageService(official: official, sessions: StubLocalAccount(today: 100, total: 999), calendar: calendar)
        let now = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        _ = await service.accountSnapshot(now: now)
        _ = await service.accountSnapshot(now: now)
        context.expectEqual(http.requestCount, 1)
        _ = await service.accountSnapshot(now: now, force: true)
        context.expectEqual(http.requestCount, 2)
    }

    test("Account service still answers the snapshot provider call") { context in
        let calendar = accountTestCalendar(timeZone: "UTC")
        let http = MockHTTPClient(response: HTTPResponse(
            data: #"{"days":[{"date":"2026-10-24","total_tokens":1234}]}"#.data(using: .utf8)!,
            statusCode: 200
        ))
        let official = OfficialUsageClient(http: http, credentials: StubCredentials(token: "tok_test"), baseURL: URL(string: "https://chatgpt.com/backend-api")!)
        let service = AccountUsageService(official: official, sessions: StubLocalAccount(today: 100, total: 999), calendar: calendar)
        let provider: FutureAccountSnapshotProviding = service
        let snapshot = await provider.accountSnapshot(now: DateParsing.iso8601("2026-10-24T12:00:00Z")!)
        context.expectEqual(snapshot?.todayTokens, 1234)
        context.expectEqual(snapshot?.totalTokens, 999)
    }

    test("SessionIndexer does not duplicate events of a session that grows while it is read") { context in
        // The recorded offset used to be the size observed before the read. A session file that
        // grows while it is read therefore left the offset behind the consumed bytes and the
        // next scan re-parsed the overlap, duplicating the events in it.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("session.jsonl")

        let filler = String(repeating: "x", count: 5_000)
        var content = "{\"timestamp\":\"2026-10-24T02:48:19.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"item_completed\",\"turn_id\":\"turn-1\",\"item\":{\"type\":\"CommandExecution\"},\"started_at_ms\":1000,\"completed_at_ms\":2000}}\n"
        content += String(repeating: filler + "\n", count: 1_000)
        try content.write(to: file, atomically: true, encoding: .utf8)

        let indexer = SessionIndexer(rootURL: directory, cacheURL: nil)
        let appender = SessionAppender(url: file)
        var expectedToolCalls = 1
        for _ in 0..<2 {
            appender.start()
            _ = await indexer.scan()
            await appender.stop()
            expectedToolCalls += appender.appendedCount
            let scanned = await indexer.scan()
            context.expectEqual(scanned.first?.turns.first?.toolCallCount, expectedToolCalls)
        }
    }

    test("DegradationAnalyzer returns normal for a single weak signal") { context in
        let now = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        let baseline = makeTurns(count: 8, model: "gpt-6.1-sol", effort: "xhigh", now: now, severity: 0)
        let current = makeTurns(count: 1, model: "gpt-6.1-sol", effort: "xhigh", now: now, severity: 0)
        let result = DegradationAnalyzer.analyze(
            baselineTurns: baseline,
            currentTurns: current,
            routeMismatch: false,
            now: now,
            windowDays: 7,
            thresholds: .standard
        )
        context.expectEqual(result.status, .normal)
    }

    test("DegradationAnalyzer returns suspected for two performance signals") { context in
        let now = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        let baseline = makeTurns(count: 8, model: "gpt-6.1-sol", effort: "xhigh", now: now, severity: 0)
        let current = makeTurns(count: 1, model: "gpt-6.1-sol", effort: "xhigh", now: now, severity: 2)
        let result = DegradationAnalyzer.analyze(
            baselineTurns: baseline, currentTurns: current, routeMismatch: false,
            now: now, windowDays: 7, thresholds: .standard
        )
        context.expectEqual(result.status, .suspected)
    }

    test("DegradationAnalyzer returns degraded for three performance signals") { context in
        let now = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        let baseline = makeTurns(count: 8, model: "gpt-6.1-sol", effort: "xhigh", now: now, severity: 0)
        let current = makeTurns(count: 3, model: "gpt-6.1-sol", effort: "xhigh", now: now, severity: 3)
        let result = DegradationAnalyzer.analyze(
            baselineTurns: baseline, currentTurns: current, routeMismatch: false,
            now: now, windowDays: 7, thresholds: .standard
        )
        context.expectEqual(result.status, .degraded)
    }

    test("DegradationAnalyzer reports insufficient baseline") { context in
        let now = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        let baseline = makeTurns(count: 3, model: "gpt-6.1-sol", effort: "xhigh", now: now, severity: 0)
        let current = makeTurns(count: 1, model: "gpt-6.1-sol", effort: "xhigh", now: now, severity: 0)
        let result = DegradationAnalyzer.analyze(
            baselineTurns: baseline, currentTurns: current, routeMismatch: false,
            now: now, windowDays: 7, thresholds: .standard
        )
        context.expectEqual(result.status, .insufficient)
    }

    test("DegradationAnalyzer escalates a route anomaly with one performance hit to suspected") { context in
        let now = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        let baseline = makeTurns(count: 8, model: "gpt-6.1-sol", effort: "xhigh", now: now, severity: 0)
        let current = [makeTurn(id: "route-1", completedAt: now, modelItemMs: 8_000)]
        let result = DegradationAnalyzer.analyze(
            baselineTurns: baseline, currentTurns: current, routeMismatch: true,
            now: now, windowDays: 7, thresholds: .standard
        )
        context.expectEqual(result.status, .suspected)
        context.expectEqual(result.signals.first { $0.id == .route }?.flagged, true)
    }

    test("DegradationAnalyzer reports insufficient when no turn finished in the last 24 hours") { context in
        let now = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        let baseline = makeTurns(count: 8, model: "gpt-6.1-sol", effort: "xhigh", now: now, severity: 0)
        let current = [makeTurn(id: "stale-1", completedAt: now.addingTimeInterval(-3 * 86_400))]
        let result = DegradationAnalyzer.analyze(
            baselineTurns: baseline, currentTurns: current, routeMismatch: false,
            now: now, windowDays: 7, thresholds: .standard
        )
        context.expectEqual(result.status, .insufficient)
        context.expectTrue(result.disclaimer.contains("24 小时内没有已完成轮次"))
    }

    test("DegradationAnalyzer needs a signal to persist over the last three turns for degraded") { context in
        let now = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        let baseline = makeTurns(count: 8, model: "gpt-6.1-sol", effort: "xhigh", now: now, severity: 0)
        let current = [
            makeTurn(id: "p-1", completedAt: now.addingTimeInterval(-120)),
            makeTurn(id: "p-2", completedAt: now.addingTimeInterval(-60)),
            makeTurn(id: "p-3", completedAt: now, ttftMs: 3_000, reasoningOutputTokens: 4, modelItemMs: 8_000),
        ]
        let result = DegradationAnalyzer.analyze(
            baselineTurns: baseline, currentTurns: current, routeMismatch: false,
            now: now, windowDays: 7, thresholds: .standard
        )
        context.expectEqual(result.status, .suspected)
    }

    test("DegradationAnalyzer caps the verdict at suspected when fewer than three recent turns exist") { context in
        let now = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        let baseline = makeTurns(count: 8, model: "gpt-6.1-sol", effort: "xhigh", now: now, severity: 0)
        let current = [
            makeTurn(id: "s-1", completedAt: now.addingTimeInterval(-60), ttftMs: 3_000, reasoningOutputTokens: 4, modelItemMs: 8_000),
            makeTurn(id: "s-2", completedAt: now, ttftMs: 3_000, reasoningOutputTokens: 4, modelItemMs: 8_000),
        ]
        let result = DegradationAnalyzer.analyze(
            baselineTurns: baseline, currentTurns: current, routeMismatch: false,
            now: now, windowDays: 7, thresholds: .standard
        )
        context.expectEqual(result.status, .suspected)
    }

    test("DegradationAnalyzer excludes turns without duration or usage from the baseline") { context in
        let now = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        var baseline = makeTurns(count: 8, model: "gpt-6.1-sol", effort: "xhigh", now: now, severity: 0)
        baseline.append(makeTurn(id: "no-duration", completedAt: now, durationMs: 0, modelItemMs: 400))
        baseline.append(makeTurn(id: "no-usage", completedAt: now, inputTokens: 0, outputTokens: 0))
        let current = [makeTurn(id: "ok-1", completedAt: now)]
        let result = DegradationAnalyzer.analyze(
            baselineTurns: baseline, currentTurns: current, routeMismatch: false,
            now: now, windowDays: 7, thresholds: .standard
        )
        context.expectEqual(result.sampleTurns, 8)
        context.expectEqual(result.status, .normal)
    }

    test("DegradationAnalyzer keeps another provider out of the baseline") { context in
        let now = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        var baseline = makeTurns(count: 8, model: "gpt-6.1-sol", effort: "xhigh", now: now, severity: 0)
        baseline += (0..<8).map { index in
            makeTurn(id: "other-\(index)", provider: "other-provider", completedAt: now.addingTimeInterval(-Double(index) * 60))
        }
        let current = [makeTurn(id: "ok-1", completedAt: now)]
        let result = DegradationAnalyzer.analyze(
            baselineTurns: baseline, currentTurns: current, routeMismatch: false,
            now: now, windowDays: 7, thresholds: .standard
        )
        context.expectEqual(result.sampleTurns, 8)
    }

    test("DegradationAnalyzer reports insufficient when the current turn has no model") { context in
        let now = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        let baseline = makeTurns(count: 8, model: "gpt-6.1-sol", effort: "xhigh", now: now, severity: 0)
        let current = [makeTurn(id: "unknown-1", model: nil, completedAt: now)]
        let result = DegradationAnalyzer.analyze(
            baselineTurns: baseline, currentTurns: current, routeMismatch: false,
            now: now, windowDays: 7, thresholds: .standard
        )
        context.expectEqual(result.status, .insufficient)
        context.expectTrue(result.disclaimer.contains("缺少模型或档位信息"))
    }

    test("DegradationAnalyzer conservative thresholds accept a slower turn that standard flags") { context in
        let now = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        let baseline = makeTurns(count: 8, model: "gpt-6.1-sol", effort: "xhigh", now: now, severity: 0)
        let current = [makeTurn(id: "slow-1", completedAt: now, ttftMs: 2_525)]
        let standard = DegradationAnalyzer.analyze(
            baselineTurns: baseline, currentTurns: current, routeMismatch: false,
            now: now, windowDays: 7, thresholds: .standard
        )
        let conservative = DegradationAnalyzer.analyze(
            baselineTurns: baseline, currentTurns: current, routeMismatch: false,
            now: now, windowDays: 7, thresholds: .conservative
        )
        context.expectEqual(standard.signals.first { $0.id == .ttft }?.flagged, true)
        context.expectEqual(conservative.signals.first { $0.id == .ttft }?.flagged, false)
    }

    test("DegradationAnalyzer counts usable turns on the insufficient paths") { context in
        let now = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        let baseline = makeTurns(count: 8, model: "gpt-6.1-sol", effort: "xhigh", now: now, severity: 0)
        let stale = DegradationAnalyzer.analyze(
            baselineTurns: baseline,
            currentTurns: [makeTurn(id: "x-1", completedAt: now.addingTimeInterval(-3 * 86_400))],
            routeMismatch: false, now: now, windowDays: 7, thresholds: .standard
        )
        let unknown = DegradationAnalyzer.analyze(
            baselineTurns: baseline,
            currentTurns: [makeTurn(id: "x-2", model: nil, completedAt: now)],
            routeMismatch: false, now: now, windowDays: 7, thresholds: .standard
        )
        context.expectEqual(stale.status, .insufficient)
        context.expectEqual(stale.sampleTurns, 8)
        context.expectEqual(unknown.status, .insufficient)
        context.expectEqual(unknown.sampleTurns, 8)
    }

    test("DegradationAnalyzer states the baseline disclaimer on every path") { context in
        let now = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        let baseline = makeTurns(count: 8, model: "gpt-6.1-sol", effort: "xhigh", now: now, severity: 0)
        let normal = DegradationAnalyzer.analyze(
            baselineTurns: baseline, currentTurns: [makeTurn(id: "d-1", completedAt: now)],
            routeMismatch: false, now: now, windowDays: 7, thresholds: .standard
        )
        let insufficient = DegradationAnalyzer.analyze(
            baselineTurns: baseline, currentTurns: [], routeMismatch: false,
            now: now, windowDays: 7, thresholds: .standard
        )
        for snapshot in [normal, insufficient] {
            context.expectTrue(snapshot.disclaimer.contains("基于本机近 7 天基线"))
            context.expectTrue(snapshot.disclaimer.contains("不代表官方结论"))
        }
    }

    test("CodexRadarCurrentSource normalizes a confirmed reset") { context in
        let json = #"{"monitored_at":"2026-10-24T12:00:00+08:00","window":{"scope":"Codex 用户","source_url":"https://x.com/example"},"completion_observation":{"status":"completed","confirmation_level":"stationmaster_confirmed","occurred_on":"2026-10-24","title_zh":"Day 18 重置完成","evidence_zh":"站长已确认","announcement_url":"https://x.com/example"}}"#
        let http = MockHTTPClient(response: HTTPResponse(data: json.data(using: .utf8)!, statusCode: 200))
        let source = CodexRadarCurrentSource()
        let signals = try await source.fetch(using: http, now: Date(timeIntervalSince1970: 1_790_000_000))
        context.expectEqual(signals.count, 1)
        context.expectEqual(signals.first?.kind, .reset)
        context.expectEqual(signals.first?.verified, true)
        context.expectEqual(signals.first?.scope, "Codex 用户")
        context.expectEqual(signals.first?.url?.absoluteString, "https://x.com/example")
    }

    test("CodexRadarCurrentSource ignores an unconfirmed announcement") { context in
        let json = #"{"monitored_at":"2026-10-24T12:00:00+08:00","window":{"scope":"Codex 用户"},"completion_observation":{"status":"verifying","confirmation_level":"unconfirmed","occurred_on":"2026-10-24","title_zh":"Day 19 重置预告"}}"#
        let http = MockHTTPClient(response: HTTPResponse(data: json.data(using: .utf8)!, statusCode: 200))
        let source = CodexRadarCurrentSource()
        let signals = try await source.fetch(using: http, now: Date(timeIntervalSince1970: 1_790_000_000))
        context.expectEqual(signals.count, 0)
    }

    test("CodexRadarCurrentSource uses the occurrence day of a date-only record") { context in
        let json = #"{"monitored_at":"2026-10-23T13:10:35+08:00","timezone":"Asia/Shanghai","window":{"scope":"Codex 用户"},"completion_observation":{"status":"completed","confirmation_level":"stationmaster_confirmed","occurred_on":"2026-10-24","title_zh":"Day 18 重置完成"}}"#
        let http = MockHTTPClient(response: HTTPResponse(data: json.data(using: .utf8)!, statusCode: 200))
        let source = CodexRadarCurrentSource()
        let signals = try await source.fetch(using: http, now: Date(timeIntervalSince1970: 1_790_000_000))
        let publishedAt = signals.first?.publishedAt
        context.expectTrue(publishedAt != nil)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        context.expectEqual(publishedAt.map { calendar.component(.year, from: $0) }, 2026)
        context.expectEqual(publishedAt.map { calendar.component(.month, from: $0) }, 10)
        context.expectEqual(publishedAt.map { calendar.component(.day, from: $0) }, 24)
    }

    test("CodexRadarCurrentSource requests the public summary without credentials") { context in
        let json = #"{"completion_observation":{"status":"completed","confirmation_level":"confirmed","occurred_on":"2026-10-24"}}"#
        let http = MockHTTPClient(response: HTTPResponse(data: json.data(using: .utf8)!, statusCode: 200))
        let source = CodexRadarCurrentSource()
        _ = try await source.fetch(using: http, now: Date(timeIntervalSince1970: 1_790_000_000))
        context.expectEqual(http.lastRequest?.httpMethod, "GET")
        context.expectEqual(http.lastRequest?.timeoutInterval, 10)
        context.expectEqual(http.lastRequest?.value(forHTTPHeaderField: "User-Agent"), AppConstants.userAgent)
        context.expectEqual(http.lastRequest?.value(forHTTPHeaderField: "Authorization"), nil)
    }

    test("OpenAIStatusSource reports service status without claiming a reset") { context in
        let json = #"{"status":{"indicator":"none","description":"All Systems Operational"}}"#
        let http = MockHTTPClient(response: HTTPResponse(data: json.data(using: .utf8)!, statusCode: 200))
        let source = OpenAIStatusSource()
        let signals = try await source.fetch(using: http, now: Date(timeIntervalSince1970: 1_790_000_000))
        context.expectEqual(signals.count, 1)
        context.expectEqual(signals.first?.kind, .status)
        context.expectEqual(signals.first?.verified, false)
    }

    test("OpenAIStatusSource keeps a stable id and never marks a strong signal") { context in
        let json = #"{"page":{"id":"page-1","updated_at":"2026-10-24T12:00:00Z"},"status":{"indicator":"major","description":"Partial Outage"}}"#
        // The mock hands out one response per request, so the two scans of the
        // source need one response each.
        let http = MockHTTPClient(responses: [
            HTTPResponse(data: json.data(using: .utf8)!, statusCode: 200),
            HTTPResponse(data: json.data(using: .utf8)!, statusCode: 200),
        ])
        let source = OpenAIStatusSource()
        let first = try await source.fetch(using: http, now: Date(timeIntervalSince1970: 1_790_000_000))
        let second = try await source.fetch(using: http, now: Date(timeIntervalSince1970: 1_790_100_000))
        context.expectEqual(first.first?.id, second.first?.id)
        context.expectEqual(first.first?.severity, "incident")
        context.expectEqual(first.first?.kind, .status)
    }

    test("CodexRadarFeedSource parses verified RSS items") { context in
        let xml = """
        <rss><channel><item><title>官方权益确认：Codex 用量限制重置</title><link>https://codexradar.com/#a</link><guid>a</guid><pubDate>Sat, 17 Oct 2026 16:21:13 GMT</pubDate><description><![CDATA[官方重置卡或权益发放信号。\n适用范围：Codex 用户\n来源：https://x.com/example]]></description></item></channel></rss>
        """
        let http = MockHTTPClient(response: HTTPResponse(data: xml.data(using: .utf8)!, statusCode: 200))
        let source = CodexRadarFeedSource()
        let signals = try await source.fetch(using: http, now: Date(timeIntervalSince1970: 1_790_000_000))
        context.expectEqual(signals.count, 1)
        context.expectEqual(signals.first?.verified, true)
        context.expectEqual(signals.first?.scope, "Codex 用户")
    }

    test("CodexResetsSource parses signal and status") { context in
        let feed = #"{"fetched_at":"2026-10-24T12:00:00Z","signal":{"summary":"Lands tomorrow","at":"2026-10-22T06:55:54Z","url":"https://x.com/example","kind":"signal"},"tweets":[]}"#
        let status = #"{"indicator":"none","description":"All Systems Operational","codex":"operational"}"#
        let http = MockHTTPClient(responses: [
            HTTPResponse(data: feed.data(using: .utf8)!, statusCode: 200),
            HTTPResponse(data: status.data(using: .utf8)!, statusCode: 200),
        ])
        let source = CodexResetsSource()
        let signals = try await source.fetch(using: http, now: Date(timeIntervalSince1970: 1_790_000_000))
        context.expectTrue(signals.contains { $0.kind == .verifying })
        context.expectTrue(signals.contains { $0.kind == .status })
    }

    test("CodexRadarFeedSource keeps an announcement verifying and a closed window a reset") { context in
        let xml = """
        <rss><channel>
        <item><title>速蹬窗口开启：500 万用户庆祝重置</title><guid>p</guid><pubDate>Sat, 24 Oct 2026 04:46:19 GMT</pubDate><description><![CDATA[当前动作：尽快使用剩余额度，等待后续窗口关闭信号。\n适用范围：所有付费计划]]></description></item>
        <item><title>速蹬窗口关闭：Codex 与 ChatGPT Work 用量限制重置</title><guid>c</guid><pubDate>Sat, 24 Oct 2026 08:46:19 GMT</pubDate><description><![CDATA[Tibo 表示重置已全部传播完成。\n适用范围：所有付费计划]]></description></item>
        <item><title>Day 10 重置已预告 · 尚未确认完成</title><guid>u</guid><pubDate>Sat, 24 Oct 2026 02:46:19 GMT</pubDate><description><![CDATA[这是官方预告，尚未确认完成，不增加已完成重置次数。]]></description></item>
        <item><title>权益记录：Codex 用量限制已重置</title><guid>r</guid><pubDate>Sat, 24 Oct 2026 01:46:19 GMT</pubDate><description><![CDATA[确认依据：用户确认已到账。]]></description></item>
        </channel></rss>
        """
        let http = MockHTTPClient(response: HTTPResponse(data: xml.data(using: .utf8)!, statusCode: 200))
        let source = CodexRadarFeedSource()
        let signals = try await source.fetch(using: http, now: Date(timeIntervalSince1970: 1_790_000_000))
        context.expectEqual(signals.count, 4)
        let opening = signals.first { $0.title.contains("窗口开启") }
        let closing = signals.first { $0.title.contains("窗口关闭") }
        let preview = signals.first { $0.title.contains("尚未确认完成") }
        let record = signals.first { $0.title.contains("已重置") }
        context.expectEqual(opening?.kind, .verifying)
        context.expectEqual(opening?.verified, false)
        context.expectEqual(closing?.kind, .reset)
        context.expectEqual(closing?.verified, false)
        context.expectEqual(preview?.kind, .verifying)
        context.expectEqual(record?.kind, .reset)
    }

    test("CodexResetsSource keeps an unconfirmed claim verifying and never fabricates a strong severity") { context in
        let feed = #"{"fetched_at":"2026-10-24T12:00:00Z","stale":false,"signal":{"summary":"Lands tomorrow","at":"2026-10-22T06:55:54Z","url":"https://x.com/example","kind":"signal","active":true},"tweets":[{"id":"t1","url":"https://x.com/t1","text":"That is a reset!","at":"2026-10-23T04:46:19Z","explicit_reset_claim":true,"reset_verification_status":"expired"},{"id":"t2","url":"https://x.com/t2","text":"Shipping notes","at":"2026-10-23T05:00:00Z","explicit_reset_claim":false}]}"#
        let status = #"{"indicator":"none","description":"All Systems Operational","codex":"operational"}"#
        let http = MockHTTPClient(responses: [
            HTTPResponse(data: feed.data(using: .utf8)!, statusCode: 200),
            HTTPResponse(data: status.data(using: .utf8)!, statusCode: 200),
        ])
        let source = CodexResetsSource()
        let signals = try await source.fetch(using: http, now: Date(timeIntervalSince1970: 1_790_000_000))
        let claim = signals.first { $0.id.contains("tweet:t1") }
        context.expectEqual(claim?.kind, .verifying)
        context.expectEqual(claim?.verified, false)
        context.expectEqual(signals.filter { $0.id.contains("tweet:t2") }.count, 0)
        context.expectTrue(signals.allSatisfy { $0.severity != "strong" })
    }

    test("DateParsing reads the RSS time zones") { context in
        context.expectEqual(DateParsing.rfc822("Sat, 17 Oct 2026 16:21:13 GMT")?.timeIntervalSince1970, 1_792_254_073)
        context.expectEqual(DateParsing.rfc822("Sat, 17 Oct 2026 16:21:13 +0800")?.timeIntervalSince1970, 1_792_225_273)
        context.expectEqual(DateParsing.rfc822("not a date"), nil)
    }

    test("ResetRadarService cross-confirms two sources") { context in
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let signalA = ResetSignal(
            id: "reset:a", sourceId: "a", sourceName: "AI 哨兵记录", kind: .reset,
            severity: nil, title: "重置完成", summary: "", publishedAt: now,
            url: nil, verified: true, scope: "所有付费用户",
            confirmingSources: ["AI 哨兵记录"]
        )
        let signalB = ResetSignal(
            id: "reset:b", sourceId: "b", sourceName: "AI 哨兵信号", kind: .reset,
            severity: nil, title: "重置完成", summary: "", publishedAt: now,
            url: nil, verified: true, scope: "所有付费用户",
            confirmingSources: ["AI 哨兵信号"]
        )
        let sourceA = FakeResetSource(id: "a", name: "AI 哨兵记录", signals: [signalA])
        let sourceB = FakeResetSource(id: "b", name: "AI 哨兵信号", signals: [signalB])
        let service = ResetRadarService(sources: [sourceA, sourceB], http: MockHTTPClient(responses: []), interval: 60)
        let snapshot = await service.scan(now: now)
        context.expectEqual(snapshot.latestConfirmed?.confirmingSources.count, 2)
    }

    test("ResetRadarService marks a failed source down") { context in
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let good = FakeResetSource(id: "a", name: "AI 哨兵记录", signals: [])
        let bad = FailingResetSource(id: "b", name: "Codex Resets")
        let service = ResetRadarService(sources: [good, bad], http: MockHTTPClient(responses: []), interval: 60)
        let snapshot = await service.scan(now: now)
        context.expectEqual(snapshot.sourcesAvailable, 1)
        context.expectEqual(snapshot.sources.first { $0.sourceId == "b" }?.state, .down)
    }

    test("ResetRadarService keeps a single source group unconfirmed") { context in
        let calendar = radarCalendar()
        let now = radarDate(2026, 10, 18, 12, in: calendar)
        let signal = radarSignal(
            id: "record", sourceId: "ai-sentinel-records", sourceName: "AI 哨兵记录",
            title: "第 13 天额度重置完成", publishedAt: now
        )
        let service = ResetRadarService(
            sources: [FakeResetSource(id: "ai-sentinel-records", name: "AI 哨兵记录", signals: [signal])],
            http: MockHTTPClient(responses: []), interval: 60, calendar: calendar
        )
        let snapshot = await service.scan(now: now)
        context.expectEqual(snapshot.latestConfirmed, nil)
        context.expectEqual(snapshot.recent.count, 1)
        context.expectEqual(snapshot.recent.first?.confirmingSources.count, 1)
        context.expectEqual(snapshot.recent.first?.confirmingSources, ["AI 哨兵记录"])
    }

    test("ResetRadarService confirms two differently titled signals of the same day") { context in
        let calendar = radarCalendar()
        let now = radarDate(2026, 10, 18, 12, in: calendar)
        let record = radarSignal(
            id: "record", sourceId: "ai-sentinel-records", sourceName: "AI 哨兵记录",
            title: "第 13 天额度重置完成", publishedAt: now
        )
        let feed = radarSignal(
            id: "feed", sourceId: "ai-sentinel-signals", sourceName: "AI 哨兵信号",
            title: "速蹬窗口关闭：Codex 与 ChatGPT Work 用量限制重置",
            publishedAt: radarDate(2026, 10, 18, 8, in: calendar), verified: false
        )
        let service = ResetRadarService(
            sources: [
                FakeResetSource(id: "ai-sentinel-records", name: "AI 哨兵记录", signals: [record]),
                FakeResetSource(id: "ai-sentinel-signals", name: "AI 哨兵信号", signals: [feed]),
            ],
            http: MockHTTPClient(responses: []), interval: 60, calendar: calendar
        )
        let snapshot = await service.scan(now: now)
        // One day is one event, even when the sources title it differently.
        context.expectEqual(snapshot.recent.count, 1)
        context.expectEqual(snapshot.latestConfirmed?.confirmingSources.count, 2)
        context.expectEqual(snapshot.latestConfirmed?.title, "第 13 天额度重置完成")
    }

    test("ResetRadarService never confirms from the official status source") { context in
        let calendar = radarCalendar()
        let now = radarDate(2026, 10, 18, 12, in: calendar)
        let record = radarSignal(
            id: "record", sourceId: "ai-sentinel-records", sourceName: "AI 哨兵记录",
            title: "第 13 天额度重置完成", publishedAt: now
        )
        let status = ResetSignal(
            id: "openai-status:page:none", sourceId: "openai-status", sourceName: "官方状态",
            kind: .status, severity: nil, title: "OpenAI 服务状态：All Systems Operational",
            summary: "", publishedAt: now, url: nil, verified: false, scope: "所有用户",
            confirmingSources: ["官方状态"]
        )
        let service = ResetRadarService(
            sources: [
                FakeResetSource(id: "ai-sentinel-records", name: "AI 哨兵记录", signals: [record]),
                FakeResetSource(id: "openai-status", name: "官方状态", signals: [status]),
            ],
            http: MockHTTPClient(responses: []), interval: 60, calendar: calendar
        )
        let snapshot = await service.scan(now: now)
        context.expectEqual(snapshot.latestConfirmed, nil)
        context.expectEqual(snapshot.recent.first?.confirmingSources.count, 1)
        context.expectTrue(snapshot.recent.first?.confirmingSources.contains("官方状态") == false)
        context.expectEqual(snapshot.sourcesAvailable, 2)
    }

    test("ResetRadarService keeps a same-day status row out of the reset group") { context in
        let calendar = radarCalendar()
        let now = radarDate(2026, 10, 18, 12, in: calendar)
        let record = radarSignal(
            id: "record", sourceId: "ai-sentinel-records", sourceName: "AI 哨兵记录",
            title: "第 13 天额度重置完成", publishedAt: now
        )
        let feed = radarSignal(
            id: "feed", sourceId: "ai-sentinel-signals", sourceName: "AI 哨兵信号",
            title: "速蹬窗口关闭：Codex 与 ChatGPT Work 用量限制重置",
            publishedAt: radarDate(2026, 10, 18, 8, in: calendar), verified: false
        )
        // The status row is published later than the reset, so it would be the
        // newest member of the group and could split the event.
        let status = radarSignal(
            id: "openai-status:page:none", sourceId: "openai-status", sourceName: "官方状态",
            title: "OpenAI 服务状态：All Systems Operational",
            publishedAt: radarDate(2026, 10, 18, 11, in: calendar),
            kind: .status, verified: false
        )
        let service = ResetRadarService(
            sources: [
                FakeResetSource(id: "ai-sentinel-records", name: "AI 哨兵记录", signals: [record]),
                FakeResetSource(id: "ai-sentinel-signals", name: "AI 哨兵信号", signals: [feed]),
                FakeResetSource(id: "openai-status", name: "官方状态", signals: [status]),
            ],
            http: MockHTTPClient(responses: []), interval: 60, calendar: calendar
        )
        let snapshot = await service.scan(now: now)
        context.expectEqual(snapshot.latestConfirmed?.confirmingSources.count, 2)
        context.expectEqual(snapshot.recent.count, 2)
        context.expectTrue(snapshot.recent.contains { $0.kind == .status })
    }

    test("ResetRadarService keeps a source healthy when the monitored service has an incident") { context in
        let calendar = radarCalendar()
        let now = radarDate(2026, 10, 18, 12, in: calendar)
        let incident = radarSignal(
            id: "openai-status:page:major", sourceId: "openai-status", sourceName: "官方状态",
            title: "OpenAI 服务状态：Partial Outage",
            publishedAt: now, kind: .status, severity: "incident", verified: false
        )
        let service = ResetRadarService(
            sources: [FakeResetSource(id: "openai-status", name: "官方状态", signals: [incident])],
            http: MockHTTPClient(responses: []), interval: 60, calendar: calendar
        )
        let snapshot = await service.scan(now: now)
        context.expectEqual(snapshot.sources.first?.state, .ok)
        context.expectEqual(snapshot.sourcesAvailable, 1)
    }

    test("ResetRadarService marks a source degraded when the source itself is degraded") { context in
        let calendar = radarCalendar()
        let now = radarDate(2026, 10, 18, 12, in: calendar)
        let degraded = radarSignal(
            id: "codex-resets:status:unavailable", sourceId: "codex-resets", sourceName: "Codex Resets",
            title: "Codex Resets 服务状态不可用",
            publishedAt: now, kind: .status, severity: "degraded", verified: false
        )
        let service = ResetRadarService(
            sources: [FakeResetSource(id: "codex-resets", name: "Codex Resets", signals: [degraded])],
            http: MockHTTPClient(responses: []), interval: 60, calendar: calendar
        )
        let snapshot = await service.scan(now: now)
        context.expectEqual(snapshot.sources.first?.state, .degraded)
        context.expectEqual(snapshot.sourcesAvailable, 1)
    }

    test("ResetRadarService joins a neighbouring day only inside the window") { context in
        let calendar = radarCalendar()
        let now = radarDate(2026, 10, 18, 12, in: calendar)
        let near = radarSignal(
            id: "near", sourceId: "ai-sentinel-records", sourceName: "AI 哨兵记录",
            title: "第 13 天额度重置完成", publishedAt: radarDate(2026, 10, 18, 23, in: calendar)
        )
        let closeNeighbour = radarSignal(
            id: "close", sourceId: "ai-sentinel-signals", sourceName: "AI 哨兵信号",
            title: "速蹬窗口关闭", publishedAt: radarDate(2026, 10, 19, 1, in: calendar), verified: false
        )
        let service = ResetRadarService(
            sources: [
                FakeResetSource(id: "ai-sentinel-records", name: "AI 哨兵记录", signals: [near]),
                FakeResetSource(id: "ai-sentinel-signals", name: "AI 哨兵信号", signals: [closeNeighbour]),
            ],
            http: MockHTTPClient(responses: []), interval: 60, calendar: calendar
        )
        let snapshot = await service.scan(now: now)
        context.expectEqual(snapshot.recent.count, 1)
        context.expectEqual(snapshot.latestConfirmed?.confirmingSources.count, 2)
    }

    test("ResetRadarService keeps ten signals per source") { context in
        let calendar = radarCalendar()
        let now = radarDate(2026, 10, 24, 12, in: calendar)
        let signals = (0..<15).map { offset in
            radarSignal(
                id: "a:\(offset)", sourceId: "a", sourceName: "AI 哨兵记录",
                title: "第 \(offset) 天重置完成",
                publishedAt: radarDay(now, offset: -offset, in: calendar)
            )
        }
        let service = ResetRadarService(
            sources: [FakeResetSource(id: "a", name: "AI 哨兵记录", signals: signals)],
            http: MockHTTPClient(responses: []), interval: 60, calendar: calendar
        )
        let snapshot = await service.scan(now: now)
        context.expectEqual(snapshot.recent.count, 10)
        context.expectEqual(snapshot.recent.map { $0.id }, (0..<10).map { "a:\($0)" })
    }

    test("ResetRadarService keeps twenty signals in total") { context in
        let calendar = radarCalendar()
        let now = radarDate(2026, 10, 24, 12, in: calendar)
        let names = ["AI 哨兵记录", "AI 哨兵信号", "Codex Resets"]
        var sources: [ResetSource] = []
        for (index, name) in names.enumerated() {
            let signals = (0..<10).map { day in
                radarSignal(
                    id: "\(index):\(day)", sourceId: "source-\(index)", sourceName: name,
                    title: "第 \(day) 天重置完成",
                    publishedAt: radarDay(now, offset: -(index * 10 + day), in: calendar)
                )
            }
            sources.append(FakeResetSource(id: "source-\(index)", name: name, signals: signals))
        }
        let service = ResetRadarService(
            sources: sources, http: MockHTTPClient(responses: []), interval: 60, calendar: calendar
        )
        let snapshot = await service.scan(now: now)
        context.expectEqual(snapshot.recent.count, 20)
        context.expectEqual(snapshot.recent.first?.id, "0:0")
        // The oldest source is dropped, the newest signals win.
        context.expectTrue(snapshot.recent.allSatisfy { !$0.id.hasPrefix("2:") })
    }

    test("ResetRadarService ignores signals older than thirty days") { context in
        let calendar = radarCalendar()
        let now = radarDate(2026, 10, 24, 12, in: calendar)
        let fresh = radarSignal(
            id: "fresh", sourceId: "a", sourceName: "AI 哨兵记录",
            title: "今天重置完成", publishedAt: now
        )
        let old = radarSignal(
            id: "old", sourceId: "a", sourceName: "AI 哨兵记录",
            title: "很久以前的重置", publishedAt: radarDate(2026, 9, 1, 12, in: calendar)
        )
        let service = ResetRadarService(
            sources: [FakeResetSource(id: "a", name: "AI 哨兵记录", signals: [fresh, old])],
            http: MockHTTPClient(responses: []), interval: 60, calendar: calendar
        )
        let snapshot = await service.scan(now: now)
        context.expectEqual(snapshot.recent.count, 1)
        context.expectEqual(snapshot.recent.first?.id, "fresh")
    }

    test("ResetRadarService backs a failed source off and skips it while blocked") { context in
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let good = CountingResetSource(id: "a", name: "AI 哨兵记录", signals: [])
        let bad = CountingResetSource(id: "b", name: "Codex Resets", signals: [], error: HTTPError.status(500))
        let service = ResetRadarService(sources: [good, bad], http: MockHTTPClient(responses: []), interval: 60)
        let first = await service.scan(now: now)
        context.expectEqual(first.sources.first { $0.sourceId == "b" }?.state, .down)
        context.expectEqual(first.sources.first { $0.sourceId == "b" }?.lastError, "HTTP status 500")
        context.expectEqual(first.sources.first { $0.sourceId == "b" }?.nextScanAt, now.addingTimeInterval(60))
        context.expectEqual(bad.fetchCount, 1)

        // The source is blocked for a minute and is not scanned again.
        let second = await service.scan(now: now.addingTimeInterval(30))
        context.expectEqual(bad.fetchCount, 1)
        context.expectEqual(second.sources.first { $0.sourceId == "b" }?.state, .down)
        context.expectEqual(second.sources.first { $0.sourceId == "b" }?.nextScanAt, now.addingTimeInterval(60))

        // After the backoff the source is scanned again and the backoff grows.
        let third = await service.scan(now: now.addingTimeInterval(60))
        context.expectEqual(bad.fetchCount, 2)
        context.expectEqual(third.sources.first { $0.sourceId == "b" }?.nextScanAt, now.addingTimeInterval(60 + 120))
        context.expectEqual(good.fetchCount, 3)
        context.expectEqual(third.sources.first { $0.sourceId == "a" }?.state, .ok)
    }

    test("ResetRadarService keeps a slow source from stalling the others") { context in
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let slow = SlowResetSource(id: "slow", name: "Codex Resets", delay: 5)
        let fast = FakeResetSource(id: "fast", name: "AI 哨兵记录", signals: [])
        let service = ResetRadarService(
            sources: [slow, fast], http: MockHTTPClient(responses: []), interval: 60, sourceTimeout: 0.2
        )
        let started = Date()
        let snapshot = await service.scan(now: now)
        let elapsed = Date().timeIntervalSince(started)
        context.expectTrue(elapsed < 2, "the scan waited for the slow source")
        context.expectEqual(snapshot.sources.first { $0.sourceId == "slow" }?.state, .down)
        context.expectEqual(snapshot.sources.first { $0.sourceId == "fast" }?.state, .ok)
        context.expectEqual(snapshot.sourcesAvailable, 1)
    }

    test("ResetRadarService marks a source with a degraded status degraded") { context in
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let status = ResetSignal(
            id: "codex-resets:status:none:degraded", sourceId: "codex-resets", sourceName: "Codex Resets",
            kind: .status, severity: "degraded", title: "Codex Resets 服务状态：Degraded",
            summary: "", publishedAt: now, url: nil, verified: false, scope: "所有用户",
            confirmingSources: ["Codex Resets"]
        )
        let service = ResetRadarService(
            sources: [FakeResetSource(id: "codex-resets", name: "Codex Resets", signals: [status])],
            http: MockHTTPClient(responses: []), interval: 60
        )
        let snapshot = await service.scan(now: now)
        context.expectEqual(snapshot.sources.first { $0.sourceId == "codex-resets" }?.state, .degraded)
        context.expectEqual(snapshot.sourcesAvailable, 1)
        context.expectEqual(snapshot.latestConfirmed, nil)
    }

    test("ResetRadarService reports the last scan and the next one") { context in
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let source = FakeResetSource(id: "a", name: "AI 哨兵记录", signals: [])
        let service = ResetRadarService(sources: [source], http: MockHTTPClient(responses: []), interval: 60)
        let snapshot = await service.scan(now: now)
        context.expectEqual(snapshot.lastScanAt, now)
        context.expectEqual(snapshot.nextScanAt, now.addingTimeInterval(60))
        context.expectEqual(snapshot.sources.first { $0.sourceId == "a" }?.lastSuccessAt, now)
    }

    test("ResetRadarService raises a strong signal only for a verified reset") { context in
        let calendar = radarCalendar()
        let now = radarDate(2026, 10, 18, 12, in: calendar)
        let strong = radarSignal(
            id: "strong", sourceId: "a", sourceName: "AI 哨兵记录",
            title: "第 13 天额度重置完成", publishedAt: now, severity: "strong"
        )
        let service = ResetRadarService(
            sources: [FakeResetSource(id: "a", name: "AI 哨兵记录", signals: [strong])],
            http: MockHTTPClient(responses: []), interval: 60, calendar: calendar
        )
        let snapshot = await service.scan(now: now)
        context.expectEqual(snapshot.latestStrong?.id, "strong")
        context.expectEqual(snapshot.latestStrong?.isStrongNotificationCandidate, true)
        // A reset that the source did not verify never raises a strong signal.
        let unverified = radarSignal(
            id: "unverified", sourceId: "a", sourceName: "AI 哨兵记录",
            title: "第 13 天额度重置完成", publishedAt: now, severity: "strong", verified: false
        )
        let quiet = ResetRadarService(
            sources: [FakeResetSource(id: "a", name: "AI 哨兵记录", signals: [unverified])],
            http: MockHTTPClient(responses: []), interval: 60, calendar: calendar
        )
        let quietSnapshot = await quiet.scan(now: now)
        context.expectEqual(quietSnapshot.latestStrong, nil)
        context.expectEqual(quietSnapshot.recent.first?.kind, .reset)
    }

    test("ResetRadarService reuses the cached snapshot until the next scan") { context in
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let source = CountingResetSource(id: "a", name: "AI 哨兵记录", signals: [])
        let service = ResetRadarService(sources: [source], http: MockHTTPClient(responses: []), interval: 60)
        _ = await service.scan(now: now)
        let cached = await service.radarSnapshot(now: now.addingTimeInterval(30))
        context.expectEqual(source.fetchCount, 1)
        context.expectEqual(cached.lastScanAt, now)
        let due = await service.radarSnapshot(now: now.addingTimeInterval(60))
        context.expectEqual(source.fetchCount, 2)
        context.expectEqual(due.lastScanAt, now.addingTimeInterval(60))
    }

    test("CodexResetsSource reports a degraded status when the status endpoint fails") { context in
        let feed = #"{"fetched_at":"2026-10-24T12:00:00Z","tweets":[]}"#
        let http = MockHTTPClient(responses: [
            HTTPResponse(data: feed.data(using: .utf8)!, statusCode: 200),
            HTTPResponse(data: Data(), statusCode: 500),
        ])
        let source = CodexResetsSource()
        let signals = try await source.fetch(using: http, now: Date(timeIntervalSince1970: 1_790_000_000))
        context.expectTrue(signals.contains { $0.kind == .status && $0.severity == "degraded" })
    }

    test("Reset sources keep the hash of their raw payload") { context in
        let json = #"{"monitored_at":"2026-10-24T12:00:00+08:00","completion_observation":{"status":"completed","confirmation_level":"confirmed","occurred_on":"2026-10-24"}}"#
        let http = MockHTTPClient(response: HTTPResponse(data: json.data(using: .utf8)!, statusCode: 200))
        let source = CodexRadarCurrentSource()
        let signals = try await source.fetch(using: http, now: Date(timeIntervalSince1970: 1_790_000_000))
        context.expectEqual(signals.first?.rawHash, PayloadHash.short(json.data(using: .utf8)!))
    }

    test("SnapshotBuilder combines services and marks stale data") { context in
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let builder = SnapshotBuilder(
            quota: StubQuotaProvider(snapshot: QuotaSnapshot(
                planType: "pro", weeklyRemainingPercent: 84,
                weeklyResetsAt: now.addingTimeInterval(86_400), source: .official,
                fetchedAt: now.addingTimeInterval(-600)
            )),
            credits: StubCreditsProvider(snapshot: ResetCreditsSnapshot(
                availableCount: 1, reportedAvailableCount: 1, items: [], fetchedAt: now
            )),
            sessions: StubSessionProvider(snapshot: SessionSnapshot(
                isActive: true, label: "当前会话", model: "gpt-6.1-sol", effort: "xhigh",
                serviceTier: "default", contextTokens: 120, contextWindow: 475_000,
                totalTokens: 120, inputTokens: 100, outputTokens: 20,
                cachedInputTokens: 80, reasoningOutputTokens: 0,
                outputTokensPerSecond: 42.3, medianOutputTokensPerSecond: 45.1,
                ttftMs: 3_900, turnCount: 1, routeMismatch: false
            ), turns: []),
            account: StubAccountProvider(snapshot: AccountSnapshot(
                todayTokens: 1_000, totalTokens: 2_000, source: "local", updatedAt: now
            )),
            radar: StubRadarProvider(snapshot: .empty)
        )
        let snapshot = await builder.build(now: now)
        context.expectEqual(snapshot.quota.weeklyRemainingPercent, 84)
        context.expectEqual(snapshot.freshness.quota, .stale)
        context.expectEqual(snapshot.session.label, "当前会话")
        // The account was updated with the snapshot, so it is still fresh.
        context.expectEqual(snapshot.freshness.account, .fresh)
        // The radar was never scanned, so it has no data at all.
        context.expectEqual(snapshot.freshness.sources, .error)
        // The label of the account says which source the numbers came from.
        context.expectEqual(snapshot.account.source, "local")
        context.expectEqual(snapshot.resetCredits.availableCount, 1)
    }

    test("SnapshotBuilder marks data inside the freshness window as fresh") { context in
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let builder = SnapshotBuilder(
            quota: StubQuotaProvider(snapshot: QuotaSnapshot(
                planType: "pro", weeklyRemainingPercent: 84,
                weeklyResetsAt: now.addingTimeInterval(86_400), source: .official,
                fetchedAt: now.addingTimeInterval(-60)
            )),
            credits: StubCreditsProvider(snapshot: nil),
            sessions: StubSessionProvider(snapshot: nil, turns: []),
            account: StubAccountProvider(snapshot: nil),
            radar: StubRadarProvider(snapshot: .empty)
        )
        let snapshot = await builder.build(now: now)
        context.expectEqual(snapshot.freshness.quota, .fresh)
    }

    test("SnapshotBuilder reports an error for an area without data") { context in
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let builder = SnapshotBuilder(
            quota: StubQuotaProvider(snapshot: nil),
            credits: StubCreditsProvider(snapshot: nil),
            sessions: StubSessionProvider(snapshot: nil, turns: []),
            account: StubAccountProvider(snapshot: nil),
            radar: StubRadarProvider(snapshot: .empty)
        )
        let snapshot = await builder.build(now: now)
        context.expectEqual(snapshot.freshness.quota, .error)
        context.expectEqual(snapshot.freshness.session, .error)
        context.expectEqual(snapshot.freshness.account, .error)
        context.expectEqual(snapshot.freshness.sources, .error)
        // The areas without data keep their placeholders instead of faking numbers.
        context.expectEqual(snapshot.quota.weeklyRemainingPercent, nil)
        context.expectEqual(snapshot.session.label, "最近会话")
        context.expectEqual(snapshot.account.todayTokens, nil)
        context.expectEqual(snapshot.account.source, "local")
    }

    test("SnapshotBuilder hands the configured window and minimum to the health verdict") { context in
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        // Two turns outside the 7 day window and three turns inside the last day.
        let turns = [
            makeTurn(id: "old-1", completedAt: now.addingTimeInterval(-10 * 86_400)),
            makeTurn(id: "old-2", completedAt: now.addingTimeInterval(-10 * 86_400 + 60)),
            makeTurn(id: "new-1", completedAt: now.addingTimeInterval(-7_200)),
            makeTurn(id: "new-2", completedAt: now.addingTimeInterval(-3_600)),
            makeTurn(id: "new-3", completedAt: now.addingTimeInterval(-600))
        ]
        let builder = SnapshotBuilder(
            quota: StubQuotaProvider(snapshot: nil),
            credits: StubCreditsProvider(snapshot: nil),
            sessions: StubSessionProvider(snapshot: nil, turns: turns),
            account: StubAccountProvider(snapshot: nil),
            radar: StubRadarProvider(snapshot: .empty)
        )
        // The 30 day window holds the two old turns, so they can carry the baseline.
        let wide = await builder.build(now: now, windowDays: 30, minimumTurns: 2)
        context.expectEqual(wide.health.baselineWindowDays, 30)
        context.expectEqual(wide.health.sampleTurns, 2)
        context.expectEqual(wide.health.status, .normal)
        // The 7 day window drops them, so the baseline stays empty.
        let narrow = await builder.build(now: now, windowDays: 7, minimumTurns: 2)
        context.expectEqual(narrow.health.baselineWindowDays, 7)
        context.expectEqual(narrow.health.sampleTurns, 0)
        context.expectEqual(narrow.health.status, .insufficient)
        // A minimum of eight turns is more than the sample holds.
        let strict = await builder.build(now: now, windowDays: 30, minimumTurns: 8)
        context.expectEqual(strict.health.sampleTurns, 2)
        context.expectEqual(strict.health.status, .insufficient)
    }

    test("SnapshotBuilder asks the providers at the same time") { context in
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let gate = BuildGate()
        let builder = SnapshotBuilder(
            quota: GatedQuotaProvider(gate: gate),
            credits: StubCreditsProvider(snapshot: nil),
            sessions: StubSessionProvider(snapshot: nil, turns: []),
            account: OpeningAccountProvider(gate: gate),
            radar: StubRadarProvider(snapshot: .empty)
        )
        // The quota only answers once the account provider has answered, so the
        // build can only finish when the areas are asked at the same time.
        let snapshot = await withTimeout(seconds: 5) { await builder.build(now: now) }
        context.expectTrue(snapshot != nil, "the build waited for the providers one after the other")
    }

    test("SessionRepository reuses the scan it just did") { context in
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("session.jsonl")
        let content = "{\"timestamp\":\"2026-10-24T02:48:19.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"turn-1\",\"started_at\":1792810096}}\n"
            + "{\"timestamp\":\"2026-10-24T02:48:20.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_usage_record\",\"turn_id\":\"turn-1\",\"response_id\":\"resp-1\",\"usage\":{\"input_tokens\":100,\"cached_input_tokens\":80,\"cache_write_input_tokens\":0,\"output_tokens\":20,\"reasoning_output_tokens\":0,\"total_tokens\":120},\"turn_token_usage\":{\"input_tokens\":100,\"cached_input_tokens\":80,\"cache_write_input_tokens\":0,\"output_tokens\":20,\"reasoning_output_tokens\":0,\"total_tokens\":120},\"thread_token_usage\":{\"input_tokens\":100,\"cached_input_tokens\":80,\"cache_write_input_tokens\":0,\"output_tokens\":20,\"reasoning_output_tokens\":0,\"total_tokens\":120}}}\n"
        try content.write(to: file, atomically: true, encoding: .utf8)

        let indexer = SessionIndexer(rootURL: directory, cacheURL: nil)
        let repository = SessionRepository(indexer: indexer)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        _ = await repository.currentSnapshot(now: now)
        let turns = await repository.allTurns(now: now)
        context.expectEqual(turns.count, 1, "the turns of the session are there")
        context.expectEqual(await indexer.scans, 1, "the session log was scanned once")
    }

    test("SnapshotStore round-trips atomically") { context in
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapshotStore(directory: directory)
        let snapshot = UsageSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_790_000_000),
            freshness: Freshness(quota: .fresh, session: .fresh, account: .fresh, sources: .fresh),
            quota: QuotaSnapshot(planType: "pro", weeklyRemainingPercent: 84, weeklyResetsAt: nil, source: .official, fetchedAt: Date(timeIntervalSince1970: 1_790_000_000)),
            resetCredits: ResetCreditsSnapshot(availableCount: 0, reportedAvailableCount: 0, items: [], fetchedAt: Date(timeIntervalSince1970: 1_790_000_000)),
            session: SessionSnapshot(isActive: false, label: "最近会话", model: nil, effort: nil, serviceTier: nil, contextTokens: nil, contextWindow: nil, totalTokens: nil, inputTokens: nil, outputTokens: nil, cachedInputTokens: nil, reasoningOutputTokens: nil, outputTokensPerSecond: nil, medianOutputTokensPerSecond: nil, ttftMs: nil, turnCount: 0, routeMismatch: false),
            account: AccountSnapshot(todayTokens: nil, totalTokens: nil, source: "local", updatedAt: Date(timeIntervalSince1970: 1_790_000_000)),
            health: .empty,
            resetRadar: .empty
        )
        try store.save(snapshot)
        let loaded = try store.load(maxAge: 60, now: Date(timeIntervalSince1970: 1_790_000_030))
        context.expectEqual(loaded?.quota.weeklyRemainingPercent, 84)
        context.expectEqual(loaded, snapshot)
        let stale = try store.load(maxAge: 10, now: Date(timeIntervalSince1970: 1_790_000_100))
        context.expectEqual(stale, nil)
    }

    test("SnapshotStore returns nil for a missing or unreadable file") { context in
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapshotStore(directory: directory)
        context.expectEqual(try store.load(maxAge: 60, now: Date()), nil)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not a snapshot".utf8).write(to: directory.appendingPathComponent("snapshot.json"))
        context.expectEqual(try store.load(maxAge: 60, now: Date()), nil)
    }

    test("SnapshotStore writes ISO-8601 dates and camelCase keys") { context in
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapshotStore(directory: directory)
        let snapshot = UsageSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_790_000_000),
            freshness: Freshness(quota: .fresh, session: .fresh, account: .fresh, sources: .fresh),
            quota: QuotaSnapshot(planType: "pro", weeklyRemainingPercent: 84, weeklyResetsAt: nil, source: .official, fetchedAt: Date(timeIntervalSince1970: 1_790_000_000)),
            resetCredits: ResetCreditsSnapshot(availableCount: 0, reportedAvailableCount: 0, items: [], fetchedAt: Date(timeIntervalSince1970: 1_790_000_000)),
            session: SessionSnapshot(isActive: false, label: "最近会话", model: nil, effort: nil, serviceTier: nil, contextTokens: nil, contextWindow: nil, totalTokens: nil, inputTokens: nil, outputTokens: nil, cachedInputTokens: nil, reasoningOutputTokens: nil, outputTokensPerSecond: nil, medianOutputTokensPerSecond: nil, ttftMs: nil, turnCount: 0, routeMismatch: false),
            account: AccountSnapshot(todayTokens: nil, totalTokens: nil, source: "local", updatedAt: Date(timeIntervalSince1970: 1_790_000_000)),
            health: .empty,
            resetRadar: .empty
        )
        try store.save(snapshot)
        let text = try String(contentsOf: directory.appendingPathComponent("snapshot.json"), encoding: .utf8)
        context.expectTrue(text.contains("\"generatedAt\""), "the key is not camelCase")
        context.expectTrue(text.contains("\"resetCredits\""), "the key is not camelCase")
        context.expectTrue(text.contains("\"weeklyRemainingPercent\""), "the key is not camelCase")
        context.expectTrue(text.contains("\"2026-09-21T14:13:20Z\""), "the date is not ISO-8601")
        context.expectTrue(text.contains("\"fresh\""), "the state is not a plain string")
    }

    test("WebAssets carries the built panel and its CSP") { context in
        let html = WebAssets.panelHTML
        context.expectTrue(!html.isEmpty, "the generated panel is empty")
        context.expectTrue(html.contains("Content-Security-Policy"), "the panel has no CSP meta")
        context.expectTrue(html.contains("用量"), "the panel title is missing")
        context.expectTrue(html.contains("周额度"), "the quota card is missing")
        context.expectTrue(html.contains("重置追踪"), "the radar card is missing")
        context.expectTrue(html.contains("id=\"root\""), "the mount point is missing")
        context.expectTrue(!html.contains("<script src="), "the panel carries an external script")
        context.expectTrue(!html.contains("<link rel=\"stylesheet\""), "the panel carries an external style")
    }

    test("SnapshotBuilder reads the session log once per build") { context in
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = directory.appendingPathComponent("session.jsonl")
        let line = #"{"timestamp":"2026-10-24T02:48:22.880Z","type":"token_usage_record","payload":{"turn_id":"turn-1","response_id":"resp-1","usage":{"input_tokens":100,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120},"turn_token_usage":{"input_tokens":100,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120},"thread_token_usage":{"input_tokens":100,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120}}}"# + "\n"
        try? line.write(to: session, atomically: true, encoding: .utf8)

        let indexer = SessionIndexer(rootURL: directory, cacheURL: nil)
        let repository = SessionRepository(indexer: indexer)
        let builder = SnapshotBuilder(
            quota: StubQuotaProvider(snapshot: QuotaSnapshot(
                planType: "pro", weeklyRemainingPercent: 84, weeklyResetsAt: nil,
                source: .official, fetchedAt: Date(timeIntervalSince1970: 1_790_000_000)
            )),
            credits: StubCreditsProvider(snapshot: ResetCreditsSnapshot(
                availableCount: 0, reportedAvailableCount: 0, items: [],
                fetchedAt: Date(timeIntervalSince1970: 1_790_000_000)
            )),
            sessions: repository,
            account: StubAccountProvider(snapshot: AccountSnapshot(
                todayTokens: 1, totalTokens: 2, source: "local",
                updatedAt: Date(timeIntervalSince1970: 1_790_000_000)
            )),
            radar: StubRadarProvider(snapshot: .empty)
        )
        _ = await builder.build(now: Date(timeIntervalSince1970: 1_790_000_000))
        let scans = await indexer.scans
        context.expectEqual(scans, 1)
    }

    test("StatusTitleFormatter renders quota, rate and health") { context in
        let snapshot = MCPTestFixtures.snapshot
        let title = StatusTitleFormatter.format(snapshot, segments: [.quota, .rate, .health])
        context.expectEqual(title.text, "84% · — · 数据不足")
    }

    test("StatusTitleFormatter marks low quota") { context in
        let snapshot = MCPTestFixtures.snapshot
        let lowQuota = UsageSnapshot(
            generatedAt: snapshot.generatedAt,
            freshness: snapshot.freshness,
            quota: QuotaSnapshot(
                planType: "pro",
                weeklyRemainingPercent: 7,
                weeklyResetsAt: nil,
                source: .official,
                fetchedAt: snapshot.quota.fetchedAt
            ),
            resetCredits: snapshot.resetCredits,
            session: snapshot.session,
            account: snapshot.account,
            health: snapshot.health,
            resetRadar: snapshot.resetRadar
        )
        let title = StatusTitleFormatter.format(lowQuota, segments: [.quota])
        context.expectEqual(title.parts.first?.color, .danger)
        context.expectEqual(title.text, "7%")
    }
}

/// A source that always returns the same signals.
struct FakeResetSource: ResetSource {
    let id: String
    let displayName: String
    let signals: [ResetSignal]

    init(id: String, name: String, signals: [ResetSignal] = []) {
        self.id = id
        self.displayName = name
        self.signals = signals
    }

    func fetch(using http: HTTPClient, now: Date) async throws -> [ResetSignal] { signals }
}

/// A source that always fails.
struct FailingResetSource: ResetSource {
    let id: String
    let displayName: String

    init(id: String, name: String) {
        self.id = id
        self.displayName = name
    }

    func fetch(using http: HTTPClient, now: Date) async throws -> [ResetSignal] { throw HTTPError.status(500) }
}

/// A source that counts its fetches and can fail.
final class CountingResetSource: ResetSource, @unchecked Sendable {
    let id: String
    let displayName: String
    let signals: [ResetSignal]
    let error: Error?

    private let lock = NSLock()
    private var calls = 0

    init(id: String, name: String, signals: [ResetSignal] = [], error: Error? = nil) {
        self.id = id
        self.displayName = name
        self.signals = signals
        self.error = error
    }

    var fetchCount: Int {
        lock.withLock { calls }
    }

    func fetch(using http: HTTPClient, now: Date) async throws -> [ResetSignal] {
        lock.withLock { calls += 1 }
        if let error { throw error }
        return signals
    }
}

/// A source that answers only after a delay.
struct SlowResetSource: ResetSource {
    let id: String
    let displayName: String
    let delay: TimeInterval

    init(id: String, name: String, delay: TimeInterval) {
        self.id = id
        self.displayName = name
        self.delay = delay
    }

    func fetch(using http: HTTPClient, now: Date) async throws -> [ResetSignal] {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        return []
    }
}

/// Builds one reset signal of the given source.
func radarSignal(
    id: String,
    sourceId: String,
    sourceName: String,
    title: String,
    publishedAt: Date,
    kind: ResetSignalKind = .reset,
    severity: String? = nil,
    verified: Bool = true
) -> ResetSignal {
    ResetSignal(
        id: id,
        sourceId: sourceId,
        sourceName: sourceName,
        kind: kind,
        severity: severity,
        title: title,
        summary: "",
        publishedAt: publishedAt,
        url: nil,
        verified: verified,
        scope: "所有付费用户",
        confirmingSources: [sourceName]
    )
}

/// A Gregorian calendar pinned to the given time zone.
func radarCalendar(_ identifier: String = "UTC") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: identifier)!
    return calendar
}

/// The instant of the given day and hour in the given calendar.
func radarDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, in calendar: Calendar) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    return calendar.date(from: components)!
}

/// The instant of the day that is the given number of days before the day of `date`.
func radarDay(_ date: Date, offset: Int, hour: Int = 12, in calendar: Calendar) -> Date {
    let start = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date))!
    return calendar.date(byAdding: .hour, value: hour, to: start)!
}

/// Builds synthetic completed turns whose degradation severity grows with `severity`.
///
/// - severity 1: half the output rate
/// - severity 2: triple the time to first token
/// - severity 3: a fifth of the reasoning share
func makeTurns(count: Int, model: String, effort: String, now: Date, severity: Int) -> [TurnMetrics] {
    (0..<count).map { index in
        let rateFactor = severity >= 1 ? 0.5 : 1.0
        let ttftFactor = severity >= 2 ? 3.0 : 1.0
        let reasoningFactor = severity >= 3 ? 0.2 : 1.0
        return TurnMetrics(
            turnId: "\(model)-\(effort)-\(index)",
            model: model,
            reasoningEffort: effort,
            serviceTier: "default",
            provider: "openai",
            compHash: "3000",
            startedAt: now.addingTimeInterval(-Double(index + 1) * 60),
            completedAt: now.addingTimeInterval(-Double(index) * 60),
            durationMs: 10_000,
            ttftMs: (1_000 + Double(index % 3) * 10) * ttftFactor,
            inputTokens: 1_000,
            cachedInputTokens: 500,
            outputTokens: 100,
            reasoningOutputTokens: Int(20 * reasoningFactor),
            modelItemMs: (4_000 + Double(index % 3) * 100) / rateFactor,
            toolMs: 1_000,
            toolCallCount: 2,
            isCompleted: true
        )
    }
}

/// Builds one synthetic completed turn with explicit field values.
func makeTurn(
    id: String,
    model: String? = "gpt-6.1-sol",
    effort: String? = "xhigh",
    serviceTier: String? = "default",
    provider: String? = "openai",
    completedAt: Date,
    durationMs: Double = 10_000,
    ttftMs: Double = 1_000,
    inputTokens: Int = 1_000,
    outputTokens: Int = 100,
    reasoningOutputTokens: Int = 20,
    modelItemMs: Double = 4_000,
    toolMs: Double = 1_000,
    toolCallCount: Int = 2
) -> TurnMetrics {
    TurnMetrics(
        turnId: id,
        model: model,
        reasoningEffort: effort,
        serviceTier: serviceTier,
        provider: provider,
        compHash: "3000",
        startedAt: completedAt.addingTimeInterval(-Double(durationMs) / 1_000),
        completedAt: completedAt,
        durationMs: durationMs,
        ttftMs: ttftMs,
        inputTokens: inputTokens,
        cachedInputTokens: 0,
        outputTokens: outputTokens,
        reasoningOutputTokens: reasoningOutputTokens,
        modelItemMs: modelItemMs,
        toolMs: toolMs,
        toolCallCount: toolCallCount,
        isCompleted: true
    )
}

/// Appends session events to a file while the indexer reads it.
final class SessionAppender: @unchecked Sendable {
    private static let filler = String(repeating: "x", count: 5_000)
    private static let lineLimit = 2_000

    private let lock = NSLock()
    private let url: URL
    private var handle: FileHandle?
    private var task: Task<Void, Never>?
    private var count = 0

    init(url: URL) { self.url = url }

    /// Number of events appended since the last `start()`.
    var appendedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard task == nil, let handle = try? FileHandle(forWritingTo: url) else { return }
        try? handle.seekToEnd()
        self.handle = handle
        count = 0
        task = Task { [weak self] in
            while !Task.isCancelled {
                self?.appendLine()
            }
        }
    }

    func stop() async {
        let (running, openHandle) = lock.withLock { () -> (Task<Void, Never>?, FileHandle?) in
            let running = task
            let openHandle = handle
            task = nil
            handle = nil
            return (running, openHandle)
        }
        running?.cancel()
        await running?.value
        try? openHandle?.close()
    }

    private func appendLine() {
        lock.lock()
        defer { lock.unlock() }
        guard let handle, count < Self.lineLimit else { return }
        let line = "{\"timestamp\":\"2026-10-24T02:48:25.000Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"item_completed\",\"turn_id\":\"turn-1\",\"item\":{\"type\":\"McpToolCall\"},\"started_at_ms\":5000,\"completed_at_ms\":6000,\"pad\":\"" + Self.filler + "\"}}\n"
        try? handle.write(contentsOf: Data(line.utf8))
        count += 1
    }
}

final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    private var responses: [HTTPResponse]
    private let error: Error?
    private(set) var lastRequest: URLRequest?
    private(set) var requestCount = 0

    init(response: HTTPResponse) { self.responses = [response]; self.error = nil }
    init(responses: [HTTPResponse]) { self.responses = responses; self.error = nil }
    init(error: Error) { self.responses = []; self.error = error }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        lastRequest = request
        requestCount += 1
        if let error { throw error }
        guard !responses.isEmpty else { throw HTTPError.emptyResponse }
        return responses.removeFirst()
    }
}

struct StubCredentials: CredentialProviding {
    let token: String
    func load() throws -> CodexCredentials { CodexCredentials(accessToken: token) }
}

struct StubQuotaFallback: QuotaFallbackProviding {
    let snapshot: QuotaSnapshot?
    func fallbackQuota(now: Date) async -> QuotaSnapshot? { snapshot }
}

struct StubResetCreditFallback: ResetCreditFallbackProviding {
    let snapshot: ResetCreditsSnapshot?
    func fallbackCredits(now: Date) async -> ResetCreditsSnapshot? { snapshot }
}

struct StubLocalAccount: AccountTotalsProviding {
    let today: Int
    let total: Int
    func accountTotals(now: Date, calendar: Calendar) async -> (today: Int, total: Int) {
        (today, total)
    }
}

/// A quota provider that returns a fixed snapshot.
struct StubQuotaProvider: QuotaSnapshotProviding {
    let snapshot: QuotaSnapshot?
    func quotaSnapshot(now: Date) async -> QuotaSnapshot? { snapshot }
}

/// A reset credit provider that returns a fixed snapshot.
struct StubCreditsProvider: ResetCreditsProviding {
    let snapshot: ResetCreditsSnapshot?
    func creditsSnapshot(now: Date) async -> ResetCreditsSnapshot? { snapshot }
}

/// A session provider that returns a fixed snapshot and a fixed turn list.
struct StubSessionProvider: SessionSnapshotProviding {
    let snapshot: SessionSnapshot?
    let turns: [TurnMetrics]
    func currentSnapshot(now: Date) async -> SessionSnapshot? { snapshot }
    func allTurns(now: Date) async -> [TurnMetrics] { turns }
}

/// An account provider that returns a fixed snapshot.
struct StubAccountProvider: AccountSnapshotProviding {
    let snapshot: AccountSnapshot?
    func accountSnapshot(now: Date) async -> AccountSnapshot? { snapshot }
}

/// A reset radar provider that returns a fixed snapshot.
struct StubRadarProvider: ResetRadarProviding {
    let snapshot: ResetRadarSnapshot
    func radarSnapshot(now: Date) async -> ResetRadarSnapshot { snapshot }
}

/// A gate that one provider opens and another one waits for.
///
/// It proves that two providers are asked at the same time: the waiting one
/// only answers after the opening one has been called.
actor BuildGate {
    private var isOpen = false
    private var waiter: CheckedContinuation<Void, Never>?

    /// Opens the gate and releases the waiting provider.
    func open() {
        isOpen = true
        waiter?.resume()
        waiter = nil
    }

    /// Waits until the gate is opened.
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiter = continuation
        }
    }
}

/// A quota provider that only answers after the gate was opened.
struct GatedQuotaProvider: QuotaSnapshotProviding {
    let gate: BuildGate

    func quotaSnapshot(now: Date) async -> QuotaSnapshot? {
        await gate.wait()
        return nil
    }
}

/// An account provider that opens the gate.
struct OpeningAccountProvider: AccountSnapshotProviding {
    let gate: BuildGate

    func accountSnapshot(now: Date) async -> AccountSnapshot? {
        await gate.open()
        return nil
    }
}

/// A Gregorian calendar pinned to the given time zone.
func accountTestCalendar(timeZone identifier: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: identifier)!
    return calendar
}

/// Mirrors the snapshot provider protocol that a later task consumes.
///
/// The cache bypassing overload of `accountSnapshot` must not take the
/// `accountSnapshot(now:)` call of that protocol away.
protocol FutureAccountSnapshotProviding: Sendable {
    func accountSnapshot(now: Date) async -> AccountSnapshot?
}

extension AccountUsageService: FutureAccountSnapshotProviding {}

/// Asks the official client for the daily total of the given payload.
func officialDailyTotal(_ payload: String, calendar: Calendar, start: Date, end: Date) async throws -> Int {
    let http = MockHTTPClient(response: HTTPResponse(data: Data(payload.utf8), statusCode: 200))
    let client = OfficialUsageClient(http: http, credentials: StubCredentials(token: "tok_test"), baseURL: URL(string: "https://chatgpt.com/backend-api")!)
    return try await client.fetchDailyTokenUsage(start: start, end: end, calendar: calendar)
}

/// The value of a query item of the recorded request.
func requestQueryValue(_ request: URLRequest?, name: String) -> String? {
    guard let url = request?.url,
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    return components.queryItems?.first { $0.name == name }?.value
}

final class FakeAppServerTransport: AppServerTransport, @unchecked Sendable {
    struct Request { let method: String; let params: [String: Any] }

    private let lock = NSLock()
    private var recorded: [Request] = []
    private let result: [String: Any]
    private let initializeDelay: TimeInterval
    private var remainingInitializeFailures: Int

    init(result: [String: Any], initializeDelay: TimeInterval = 0, initializeFailures: Int = 0) {
        self.result = result
        self.initializeDelay = initializeDelay
        self.remainingInitializeFailures = initializeFailures
    }

    var requests: [Request] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func request(method: String, params: [String: Any]) async throws -> [String: Any] {
        let request = Request(method: method, params: params)
        let failsInitialize = lock.withLock {
            recorded.append(request)
            let fails = method == "initialize" && remainingInitializeFailures > 0
            if fails { remainingInitializeFailures -= 1 }
            return fails
        }

        if method == "initialize" {
            if initializeDelay > 0 {
                try await Task.sleep(nanoseconds: UInt64(initializeDelay * 1_000_000_000))
            }
            if failsInitialize { throw AppServerError.notRunning }
            return [:]
        }
        return result
    }

    func notify(method: String, params: [String: Any]) async throws {}
    func close() {}
}

func makeAppServerScript(_ contents: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("codexinfo-appserver-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("fake-app-server.sh")
    try contents.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}
