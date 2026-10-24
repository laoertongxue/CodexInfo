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
}

final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    let response: HTTPResponse?
    let error: Error?
    private(set) var lastRequest: URLRequest?
    private(set) var requestCount = 0

    init(response: HTTPResponse) { self.response = response; self.error = nil }
    init(error: Error) { self.response = nil; self.error = error }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        lastRequest = request
        requestCount += 1
        if let error { throw error }
        return response!
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
