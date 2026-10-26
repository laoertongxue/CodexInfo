import Foundation
import CodexInfoCore
import CodexInfoLive

/// Registers the tests of the per-client quota sources.
func registerClientUsageTests() {
    test("Qoder usage reads the last account summary of the log") { context in
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let run = root.appendingPathComponent("2026-10-25T01-30-41", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
            let json = #"{"operation":"account.getQuotaUsage","status":200,"hasQoderUsage":true,"qoderUsage":{"totalUsagePercentage":0.5,"isQuotaExceeded":false,"expiresAt":1795402342646,"userQuota":{"total":2000,"used":826,"remaining":1174,"percentage":0.42,"unit":"credits"},"addOnQuota":{"total":500,"used":400,"remaining":100,"percentage":0.8,"unit":"credits"}}}"#
            let line = "[2026-10-25T01:30:49.939Z] [INFO] [main] [Auth] [AccountUsage] 用量响应摘要 " + json + "\n"
            try line.write(to: run.appendingPathComponent("main.log"), atomically: true, encoding: .utf8)
        } catch {
            context.fail("the log was not written: \(error)")
            return
        }
        let provider = QoderUsageProvider(logRoot: root)
        let snapshot = await provider.snapshot()
        context.expectEqual(snapshot?.quotaPercent, 50)
        context.expectEqual(snapshot?.detail, "剩余 1274 / 2500 积分")
        context.expectEqual(snapshot?.source, "本地用量日志")
        context.expectEqual(snapshot?.limits?.count, 2)
        context.expectEqual(snapshot?.limits?.first?.id, "plan")
        context.expectEqual(snapshot?.limits?.first?.label, "套餐内 Credits")
        context.expectEqual(snapshot?.limits?.first?.usedPoints, 826)
        context.expectEqual(snapshot?.limits?.first?.totalPoints, 2000)
        context.expectEqual(snapshot?.limits?.first?.usedPercent, 42)
        context.expectEqual(snapshot?.limits?.first?.resetAt, Date(timeIntervalSince1970: 1_795_402_342.646))
        context.expectEqual(snapshot?.limits?.first?.resetLabel, "刷新")
        context.expectEqual(snapshot?.limits?.last?.id, "addOn")
        context.expectEqual(snapshot?.limits?.last?.label, "资源包")
        context.expectEqual(snapshot?.limits?.last?.usedPoints, 400)
        context.expectEqual(snapshot?.limits?.last?.totalPoints, 500)
        context.expectEqual(snapshot?.limits?.last?.usedPercent, 80)
        context.expectEqual(snapshot?.limits?.last?.resetAt, nil)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        context.expectEqual(snapshot?.updatedAt, formatter.date(from: "2026-10-25T01:30:49.939Z"))
        context.expectEqual(snapshot?.tone, .normal)
    }

    test("Qoder usage finds a summary beyond the first tail window") { context in
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let run = root.appendingPathComponent("run", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
            let json = #"{"operation":"account.getQuotaUsage","status":200,"hasQoderUsage":true,"qoderUsage":{"totalUsagePercentage":0.52,"isQuotaExceeded":false,"userQuota":{"total":2000,"used":826,"remaining":1174,"unit":"credits"},"addOnQuota":{"total":400,"used":400,"remaining":0,"unit":"credits"}}}"#
            let line = "[2026-10-25T01:30:49.939Z] [INFO] [main] [Auth] [AccountUsage] 用量响应摘要 " + json + "\n"
            // More than the 4 MB first window; the newline keeps the slice at
            // a UTF-8 character boundary even for CJK filler.
            let filler = String(repeating: "日志填充\n", count: 400_000)
            try (line + filler).write(to: run.appendingPathComponent("main.log"), atomically: true, encoding: .utf8)
        } catch {
            context.fail("the log was not written: \(error)")
            return
        }
        let snapshot = await QoderUsageProvider(logRoot: root).snapshot()
        context.expectEqual(snapshot?.quotaPercent, 48)
        context.expectEqual(snapshot?.detail, "剩余 1174 / 2400 积分")
    }

    test("Qoder usage falls back to the two quotas of an older summary") { context in
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let run = root.appendingPathComponent("run", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
            let json = #"{"status":200,"hasQoderUsage":true,"qoderUsage":{"userQuota":{"total":2000,"used":826,"remaining":1174},"addOnQuota":{"total":400,"used":400,"remaining":0}}}"#
            let line = "[AccountUsage] 用量响应摘要 " + json + "\n"
            try line.write(to: run.appendingPathComponent("main.1.log"), atomically: true, encoding: .utf8)
        } catch {
            context.fail("the log was not written: \(error)")
            return
        }
        let snapshot = await QoderUsageProvider(logRoot: root).snapshot()
        context.expectEqual(snapshot?.quotaPercent, 49)
    }

    test("Qoder usage reports a missing log as no quota") { context in
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = await QoderUsageProvider(logRoot: root).snapshot()
        context.expectEqual(snapshot?.quotaPercent, nil)
        context.expectEqual(snapshot?.tone, .muted)
    }

    test("DeepSeek usage sends the local grant and shows the balance") { context in
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let credentials = directory.appendingPathComponent(".credentials.yaml")
        let settings = directory.appendingPathComponent("settings.yaml.imported")
        let yaml = """
        version: 1
        records:
          deepseek-account-platform/default:
            kind: grant
            payload:
              version: 1
              token: tok_test_deepseek
              issuer: https://platform.deepseek.com
        """
        let settingsYAML = """
        agent-default-model:
          provider: deepseek-official
          model: deepseek-v4-flash
          reasoningEffort: max
        """
        do {
            try yaml.write(to: credentials, atomically: true, encoding: .utf8)
            try settingsYAML.write(to: settings, atomically: true, encoding: .utf8)
        } catch {
            context.fail("the credential file was not written: \(error)")
            return
        }
        let json = #"{"code":0,"data":{"biz_data":{"normal_wallets":[{"currency":"CNY","balance":"41.6049165"}],"bonus_wallets":[{"currency":"CNY","balance":"0"}]}}}"#
        let client = MockHTTPClient(response: HTTPResponse(
            data: Data(json.utf8),
            statusCode: 200
        ))
        let provider = DeepSeekUsageProvider(
            credentialsURL: credentials,
            settingsURL: settings,
            http: client
        )
        let snapshot = await provider.snapshot()
        context.expectEqual(snapshot?.quotaText, "¥41.60")
        context.expectEqual(snapshot?.quotaLabel, "余额")
        context.expectEqual(snapshot?.tone, .normal)
        context.expectEqual(snapshot?.model, "DeepSeek V4 Flash")
        context.expectEqual(snapshot?.effort, "Max")
        context.expectEqual(snapshot?.source, "官方钱包")
        context.expectEqual(client.lastRequest?.url?.host, "platform.deepseek.com")
        context.expectEqual(client.lastRequest?.timeoutInterval, AppConstants.clientUsageTimeoutSeconds)
        context.expectEqual(
            client.lastRequest?.value(forHTTPHeaderField: "x-dsh-auth-token"),
            "tok_test_deepseek"
        )
    }

    test("DeepSeek usage refuses a grant of another issuer") { context in
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let credentials = directory.appendingPathComponent(".credentials.yaml")
        let yaml = """
        version: 1
        records:
          deepseek-account-platform/default:
            kind: grant
            payload:
              token: tok_test_deepseek
              issuer: https://evil.example.com
        """
        do {
            try yaml.write(to: credentials, atomically: true, encoding: .utf8)
        } catch {
            context.fail("the credential file was not written: \(error)")
            return
        }
        let client = MockHTTPClient(error: HTTPError.blockedURL)
        let snapshot = await DeepSeekUsageProvider(credentialsURL: credentials, http: client).snapshot()
        context.expectEqual(snapshot?.quotaText, nil)
        context.expectEqual(snapshot?.tone, .muted)
        context.expectEqual(client.requestCount, 0)
    }

    test("DeepSeek usage refuses a grant without an issuer") { context in
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let credentials = directory.appendingPathComponent(".credentials.yaml")
        let yaml = """
        version: 1
        records:
          deepseek-account-platform/default:
            kind: grant
            payload:
              token: tok_test_deepseek
        """
        do {
            try yaml.write(to: credentials, atomically: true, encoding: .utf8)
        } catch {
            context.fail("the credential file was not written: \(error)")
            return
        }
        let client = MockHTTPClient(error: HTTPError.blockedURL)
        let snapshot = await DeepSeekUsageProvider(credentialsURL: credentials, http: client).snapshot()
        context.expectEqual(snapshot?.quotaText, nil)
        context.expectEqual(snapshot?.tone, .muted)
        context.expectEqual(client.requestCount, 0)
    }

    test("MiniMax usage reads the weekly remains of the general model") { context in
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let auth = directory.appendingPathComponent("auth.json")
        let config = directory.appendingPathComponent("config.yaml")
        do {
            let records: [String: Any] = [
                "records": [
                    "com.minimax.mcode.oauth.prod.cn\u{0}abc": [
                        "accessToken": "tok_test_minimax",
                        "expiresAtMs": 9_999_999_999_000
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: records)
            try data.write(to: auth)
            try "defaultModel: minimax/MiniMax-M3.1-Flash\ndefaultModelVariant: thinking\n"
                .write(to: config, atomically: true, encoding: .utf8)
        } catch {
            context.fail("the auth file was not written: \(error)")
            return
        }
        let json = #"{"model_remains":[{"model_name":"general","current_weekly_remaining_percent":93,"current_interval_remaining_percent":100,"weekly_end_time":1792944000000,"end_time":1792911600000,"weekly_boost_permille":1500},{"model_name":"video","current_weekly_remaining_percent":50}]}"#
        let resets = #"{"cards":[{"card_id":"card-1","source_type":"mcode_signin","expire_time":1793030400000,"create_time":1791802739548},{"card_id":"card-2","source_type":"mcode_signin","expire_time":1793116800000,"create_time":1791857201814},{"card_id":"card-3","source_type":"mcode_signin","expire_time":1793203200000,"create_time":1791943848663}],"total":3,"base_resp":{"status_code":0,"status_msg":"success"}}"#
        let client = PathHTTPClient(responses: [
            ("coding_plan/remains", HTTPResponse(data: Data(json.utf8), statusCode: 200)),
            ("reset_card/list", HTTPResponse(data: Data(resets.utf8), statusCode: 200)),
        ])
        let provider = MiniMaxUsageProvider(
            authURL: auth,
            configURL: config,
            http: client,
            now: { Date(timeIntervalSince1970: 1_790_000_000) }
        )
        let snapshot = await provider.snapshot()
        context.expectEqual(snapshot?.quotaPercent, 93)
        context.expectEqual(snapshot?.detail, "5 小时窗口 100%")
        context.expectEqual(snapshot?.model, "MiniMax M3.1 Flash")
        context.expectEqual(snapshot?.effort, "思考")
        context.expectEqual(snapshot?.source, "官方额度接口")
        context.expectEqual(snapshot?.resetsAt, Date(timeIntervalSince1970: 1_792_944_000))
        context.expectEqual(snapshot?.resetCardTotal, 3)
        context.expectEqual(snapshot?.resetCards?.count, 3)
        context.expectEqual(snapshot?.resetCards?.first?.label, "完全重置")
        context.expectEqual(snapshot?.resetCards?.first?.expiresAt, Date(timeIntervalSince1970: 1_793_030_400))
        context.expectEqual(snapshot?.limits?.count, 2)
        context.expectEqual(snapshot?.limits?.first?.id, "fiveHour")
        context.expectEqual(snapshot?.limits?.first?.label, "5 小时限额")
        context.expectEqual(snapshot?.limits?.first?.usedPoints, 0)
        context.expectEqual(snapshot?.limits?.first?.totalPoints, 100)
        context.expectEqual(snapshot?.limits?.first?.resetAt, Date(timeIntervalSince1970: 1_792_911_600))
        context.expectEqual(snapshot?.limits?.last?.id, "weekly")
        context.expectEqual(snapshot?.limits?.last?.label, "周限额")
        context.expectEqual(snapshot?.limits?.last?.usedPoints, 10)
        context.expectEqual(snapshot?.limits?.last?.totalPoints, 150)
        context.expectEqual(snapshot?.limits?.last?.resetAt, Date(timeIntervalSince1970: 1_792_944_000))
        let remains = client.requests.first { $0.url?.path.contains("coding_plan") == true }
        context.expectEqual(remains?.url?.host, "www.minimaxi.com")
        context.expectEqual(remains?.timeoutInterval, AppConstants.clientUsageTimeoutSeconds)
        context.expectEqual(
            remains?.value(forHTTPHeaderField: "Authorization"),
            "Bearer tok_test_minimax"
        )
        let reset = client.requests.first { $0.url?.path.contains("reset_card") == true }
        context.expectEqual(reset?.url?.path, "/backend/account/reset_card/list")
        context.expectEqual(reset?.url?.query, "page=1&size=20")
        context.expectEqual(reset?.timeoutInterval, AppConstants.clientUsageTimeoutSeconds)
        context.expectEqual(
            reset?.value(forHTTPHeaderField: "Authorization"),
            "Bearer tok_test_minimax"
        )
    }

    test("MiniMax usage refuses a payload without the general weekly quota") { context in
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let auth = directory.appendingPathComponent("auth.json")
        let config = directory.appendingPathComponent("config.yaml")
        do {
            let records: [String: Any] = [
                "records": [
                    "com.minimax.mcode.oauth.prod.cn\u{0}abc": [
                        "accessToken": "tok_test_minimax",
                        "expiresAtMs": 9_999_999_999_000
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: records)
            try data.write(to: auth)
            try "defaultModel: minimax/MiniMax-M3.1-Flash\n".write(to: config, atomically: true, encoding: .utf8)
        } catch {
            context.fail("the auth file was not written: \(error)")
            return
        }
        // A video entry must not be shown as the general weekly quota.
        let json = #"{"model_remains":[{"model_name":"video","current_weekly_remaining_percent":50,"current_interval_remaining_percent":80}]}"#
        let client = MockHTTPClient(response: HTTPResponse(data: Data(json.utf8), statusCode: 200))
        let provider = MiniMaxUsageProvider(
            authURL: auth,
            configURL: config,
            http: client,
            now: { Date(timeIntervalSince1970: 1_790_000_000) }
        )
        let snapshot = await provider.snapshot()
        context.expectEqual(snapshot?.quotaPercent, nil)
        context.expectEqual(snapshot?.tone, .muted)
        context.expectEqual(snapshot?.source, "官方额度接口")
    }

    test("MiniMax usage refuses an expired token") { context in        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let auth = directory.appendingPathComponent("auth.json")
        do {
            let records: [String: Any] = [
                "records": [
                    "com.minimax.mcode.oauth.prod.cn\u{0}abc": [
                        "accessToken": "tok_test_minimax",
                        "expiresAtMs": 1_000
                    ]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: records)
            try data.write(to: auth)
        } catch {
            context.fail("the auth file was not written: \(error)")
            return
        }
        let client = MockHTTPClient(error: HTTPError.blockedURL)
        let provider = MiniMaxUsageProvider(
            authURL: auth,
            http: client,
            now: { Date(timeIntervalSince1970: 1_790_000_000) }
        )
        let snapshot = await provider.snapshot()
        context.expectEqual(snapshot?.quotaPercent, nil)
        context.expectEqual(snapshot?.tone, .muted)
        context.expectEqual(client.requestCount, 0)
    }

    test("OpenCode usage reads Go windows, free models and unavailable Zen") { context in
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let auth = directory.appendingPathComponent("auth.json")
        let zen = directory.appendingPathComponent("zen.json")
        do {
            let authJSON = #"{"opencode-go":{"type":"api","key":"tok_test_opencode"}}"#
            try authJSON.write(to: auth, atomically: true, encoding: .utf8)
        } catch {
            context.fail("the auth file was not written: \(error)")
            return
        }
        let goJSON = #"{"usage":{"rolling":{"status":"ok","percent":3,"resetsAt":"2026-10-26T08:00:00Z"},"weekly":{"status":"ok","percent":2,"resetsAt":"2026-10-31T00:00:00Z"},"monthly":{"status":"ok","percent":1,"resetsAt":"2026-11-01T00:00:00Z"}}}"#
        let go = PathHTTPClient(responses: [
            ("zen/go/v1/usage", HTTPResponse(data: Data(goJSON.utf8), statusCode: 200)),
        ])
        let zenHTTP = MockHTTPClient(error: HTTPError.blockedURL)
        let provider = OpenCodeUsageProvider(
            authURL: auth,
            zenTokenURL: zen,
            goHTTP: go,
            zenHTTP: zenHTTP,
            now: { Date(timeIntervalSince1970: 1_790_000_000) },
            freeModels: {
                ["opencode/glm-5.3-flash-free", "opencode-go/space-bunny-free"]
            }
        )
        let snapshot = await provider.snapshot()
        context.expectEqual(snapshot?.quotaPercent, 97)
        context.expectEqual(snapshot?.quotaLabel, "Go 额度")
        context.expectEqual(snapshot?.openCode?.goState, "active")
        context.expectEqual(snapshot?.openCode?.goWindows?.count, 3)
        context.expectEqual(snapshot?.openCode?.goWindows?.first?.label, "5 小时")
        context.expectEqual(snapshot?.openCode?.goWindows?.first?.usedPercent, 3)
        context.expectEqual(
            snapshot?.openCode?.goWindows?.first?.resetAt,
            DateParsing.iso8601("2026-10-26T08:00:00Z")
        )
        context.expectEqual(snapshot?.openCode?.zenState, "signedOut")
        context.expectEqual(
            snapshot?.openCode?.freeModels,
            ["opencode/glm-5.3-flash-free", "opencode-go/space-bunny-free"]
        )
        let request = go.requests.first
        context.expectEqual(request?.url?.host, "opencode.ai")
        context.expectEqual(request?.timeoutInterval, AppConstants.clientUsageTimeoutSeconds)
        context.expectEqual(
            request?.value(forHTTPHeaderField: "Authorization"),
            "Bearer tok_test_opencode"
        )
        context.expectEqual(zenHTTP.requestCount, 0)
    }

    test("OpenCode usage reports an expired Go key") { context in
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let auth = directory.appendingPathComponent("auth.json")
        do {
            let authJSON = #"{"opencode-go":{"type":"api","key":"tok_test_opencode"}}"#
            try authJSON.write(to: auth, atomically: true, encoding: .utf8)
        } catch {
            context.fail("the auth file was not written: \(error)")
            return
        }
        let expired = #"{"error":{"type":"authentication_error","code":"api_key_expired","message":"expired"}}"#
        let go = PathHTTPClient(responses: [
            ("zen/go/v1/usage", HTTPResponse(data: Data(expired.utf8), statusCode: 401)),
        ])
        let provider = OpenCodeUsageProvider(
            authURL: auth,
            zenTokenURL: directory.appendingPathComponent("missing-zen.json"),
            goHTTP: go,
            zenHTTP: MockHTTPClient(error: HTTPError.blockedURL),
            now: { Date(timeIntervalSince1970: 1_790_000_000) },
            freeModels: { ["opencode/space-bunny-free"] }
        )
        let snapshot = await provider.snapshot()
        context.expectEqual(snapshot?.openCode?.goState, "expired")
        context.expectTrue(snapshot?.openCode?.goNote?.contains("过期") == true)
        context.expectEqual(snapshot?.openCode?.goWindows, nil)
        context.expectEqual(snapshot?.quotaPercent, nil)
        context.expectEqual(snapshot?.tone, .muted)
        context.expectEqual(snapshot?.openCode?.freeModels, ["opencode/space-bunny-free"])
    }

    test("OpenCode usage reads the Zen balance with a console token") { context in
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let auth = directory.appendingPathComponent("auth.json")
        let zen = directory.appendingPathComponent("zen.json")
        do {
            let authJSON = #"{"opencode-go":{"type":"api","key":"tok_test_opencode"}}"#
            try authJSON.write(to: auth, atomically: true, encoding: .utf8)
            let zenJSON = #"{"accessToken":"zen_test","refreshToken":"","expires":9999999999999}"#
            try zenJSON.write(to: zen, atomically: true, encoding: .utf8)
        } catch {
            context.fail("the auth files were not written: \(error)")
            return
        }
        let goJSON = #"{"usage":{"rolling":{"percent":3},"weekly":{"percent":2},"monthly":{"percent":1}}}"#
        let go = PathHTTPClient(responses: [
            ("zen/go/v1/usage", HTTPResponse(data: Data(goJSON.utf8), statusCode: 200)),
        ])
        let billing = #"{"availableMicroCents":829000000}"#
        let zenHTTP = PathHTTPClient(responses: [
            ("billing/status", HTTPResponse(data: Data(billing.utf8), statusCode: 200)),
        ])
        let provider = OpenCodeUsageProvider(
            authURL: auth,
            zenTokenURL: zen,
            goHTTP: go,
            zenHTTP: zenHTTP,
            now: { Date(timeIntervalSince1970: 1_790_000_000) },
            freeModels: { [] }
        )
        let snapshot = await provider.snapshot()
        context.expectEqual(snapshot?.openCode?.zenState, "signedIn")
        context.expectEqual(snapshot?.openCode?.zenBalance, "$8.29")
        context.expectEqual(zenHTTP.requests.first?.url?.host, "console.opencode.ai")
        context.expectEqual(
            zenHTTP.requests.first?.value(forHTTPHeaderField: "Authorization"),
            "Bearer zen_test"
        )
        context.expectEqual(zenHTTP.requests.first?.url?.path, "/api/billing/status")
        context.expectEqual(go.requests.first?.url?.host, "opencode.ai")
    }

    test("OpenCode usage reports a missing Go key without a request") { context in
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let go = MockHTTPClient(error: HTTPError.blockedURL)
        let provider = OpenCodeUsageProvider(
            authURL: directory.appendingPathComponent("missing-auth.json"),
            zenTokenURL: directory.appendingPathComponent("missing-zen.json"),
            goHTTP: go,
            zenHTTP: MockHTTPClient(error: HTTPError.blockedURL),
            now: { Date(timeIntervalSince1970: 1_790_000_000) },
            freeModels: { ["opencode/space-bunny-free"] }
        )
        let snapshot = await provider.snapshot()
        context.expectEqual(snapshot?.openCode?.goState, "unavailable")
        context.expectEqual(snapshot?.openCode?.goNote, "未登录 OpenCode Go")
        context.expectEqual(snapshot?.openCode?.zenState, "signedOut")
        context.expectEqual(snapshot?.openCode?.freeModels, ["opencode/space-bunny-free"])
        context.expectEqual(go.requestCount, 0)
    }

}

/// A client that answers by URL path and records every request.
final class PathHTTPClient: HTTPClient, @unchecked Sendable {
    private let responses: [(String, HTTPResponse)]
    private(set) var requests: [URLRequest] = []

    init(responses: [(String, HTTPResponse)]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        requests.append(request)
        guard let path = request.url?.path,
              let response = responses.first(where: { path.contains($0.0) })?.1 else {
            throw HTTPError.emptyResponse
        }
        return response
    }
}

/// A directory the test may write to.
private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("codexinfo-clientusage-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
