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
