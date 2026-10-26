import Foundation
import CodexInfoCore
import CodexInfoLive
import CodexInfoMCPKit

func registerMCPTests() {
    test("MCP initialize advertises tools and resources") { context in
        let router = MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>")
        let responses = await router.handle(line: Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#.utf8))
        guard let data = responses.first,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any] else {
            context.fail("missing initialize response")
            return
        }
        context.expectEqual(result["protocolVersion"] as? String, "2025-06-18")
        context.expectTrue((result["capabilities"] as? [String: Any])?["tools"] != nil)
        context.expectTrue((result["capabilities"] as? [String: Any])?["resources"] != nil)
    }

    test("MCP initialize names the server") { context in
        let router = MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>")
        let responses = await router.handle(line: Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#.utf8))
        guard let data = responses.first,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let info = result["serverInfo"] as? [String: Any] else {
            context.fail("missing serverInfo")
            return
        }
        context.expectEqual(info["name"] as? String, "codexinfo")
        context.expectEqual(info["version"] as? String, "0.1.6")
    }

    test("MCP initialize echoes a supported protocol version") { context in
        let router = MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>")
        for version in ["2025-06-18", "2025-11-21", "2024-11-05"] {
            let line = Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"\#(version)"}}"#.utf8)
            let responses = await router.handle(line: line)
            guard let data = responses.first,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let result = object["result"] as? [String: Any] else {
                context.fail("missing initialize response for \(version)")
                continue
            }
            context.expectEqual(result["protocolVersion"] as? String, version)
        }
    }

    test("MCP initialize falls back to the default protocol version") { context in
        let router = MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>")
        let line = Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"1999-01-01"}}"#.utf8)
        let responses = await router.handle(line: line)
        guard let data = responses.first,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any] else {
            context.fail("missing initialize response")
            return
        }
        context.expectEqual(result["protocolVersion"] as? String, "2025-06-18")
    }

    test("MCP ping answers with an empty result") { context in
        let router = MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>")
        let responses = await router.handle(line: Data(#"{"jsonrpc":"2.0","id":9,"method":"ping"}"#.utf8))
        guard let data = responses.first,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any] else {
            context.fail("missing ping response")
            return
        }
        context.expectEqual(object["id"] as? Int, 9)
        context.expectTrue(result.isEmpty)
    }

    test("MCP notifications get no response") { context in
        let router = MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>")
        let responses = await router.handle(line: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8))
        context.expectTrue(responses.isEmpty, "a notification must stay silent")
    }

    test("MCP unknown method returns method not found") { context in
        let router = MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>")
        let responses = await router.handle(line: Data(#"{"jsonrpc":"2.0","id":7,"method":"does/not/exist"}"#.utf8))
        guard let data = responses.first,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any] else {
            context.fail("missing error response")
            return
        }
        context.expectEqual(error["code"] as? Int, -32601)
    }

    test("MCP malformed JSON returns a parse error") { context in
        let router = MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>")
        let responses = await router.handle(line: Data(#"{"jsonrpc":"2.0","id":1,"method":"#.utf8))
        guard let data = responses.first,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any] else {
            context.fail("missing error response")
            return
        }
        context.expectEqual(error["code"] as? Int, -32700)
    }

    test("MCP tools/list exposes show_usage_panel UI metadata") { context in
        let router = MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>")
        let responses = await router.handle(line: Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#.utf8))
        guard let data = responses.first,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let tools = result["tools"] as? [[String: Any]],
              let show = tools.first(where: { $0["name"] as? String == "show_usage_panel" }),
              let meta = show["_meta"] as? [String: Any] else {
            context.fail("missing show_usage_panel")
            return
        }
        context.expectEqual(meta["ui/resourceUri"] as? String, "ui://codexinfo/panel.html")
        context.expectEqual(meta["openai/outputTemplate"] as? String, "ui://codexinfo/panel.html")
        context.expectEqual((meta["ui"] as? [String: Any])?["resourceUri"] as? String, "ui://codexinfo/panel.html")
    }

    test("MCP tools/list names the five tools") { context in
        let router = MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>")
        let responses = await router.handle(line: Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#.utf8))
        guard let data = responses.first,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let tools = result["tools"] as? [[String: Any]] else {
            context.fail("missing tools")
            return
        }
        let names = tools.compactMap { $0["name"] as? String }
        context.expectEqual(names, [
            "get_usage_snapshot",
            "get_model_health",
            "scan_reset_sources",
            "show_usage_panel",
            "open_dashboard",
        ])
    }

    test("MCP resources/list advertises the panel resource") { context in
        let router = MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>")
        let responses = await router.handle(line: Data(#"{"jsonrpc":"2.0","id":5,"method":"resources/list"}"#.utf8))
        guard let data = responses.first,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let resources = result["resources"] as? [[String: Any]],
              let resource = resources.first else {
            context.fail("missing resources")
            return
        }
        context.expectEqual(resources.count, 1)
        context.expectEqual(resource["uri"] as? String, "ui://codexinfo/panel.html")
        context.expectEqual(resource["mimeType"] as? String, "text/html;profile=mcp-app")
    }

    test("MCP resources/read returns the panel MIME") { context in
        let router = MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>")
        let responses = await router.handle(line: Data(#"{"jsonrpc":"2.0","id":3,"method":"resources/read","params":{"uri":"ui://codexinfo/panel.html"}}"#.utf8))
        guard let data = responses.first,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let contents = result["contents"] as? [[String: Any]] else {
            context.fail("missing resource")
            return
        }
        context.expectEqual(contents.first?["mimeType"] as? String, "text/html;profile=mcp-app")
        context.expectEqual(contents.first?["text"] as? String, "<html>panel</html>")
    }

    test("MCP resources/read refuses another resource") { context in
        let router = MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>")
        let responses = await router.handle(line: Data(#"{"jsonrpc":"2.0","id":3,"method":"resources/read","params":{"uri":"file:///etc/passwd"}}"#.utf8))
        guard let data = responses.first,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any] else {
            context.fail("missing error response")
            return
        }
        context.expectEqual(error["code"] as? Int, -32602)
    }

    test("MCP tools/call returns a structured snapshot") { context in
        let router = MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>")
        let responses = await router.handle(line: Data(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_usage_snapshot","arguments":{}}}"#.utf8))
        guard let data = responses.first,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let structured = result["structuredContent"] as? [String: Any] else {
            context.fail("missing structuredContent")
            return
        }
        context.expectEqual((structured["quota"] as? [String: Any])?["weeklyRemainingPercent"] as? Int, 84)
    }

    test("MCP tools/call publishes the snapshot in the shape the panel reads") { context in
        let router = MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>")
        let responses = await router.handle(line: Data(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_usage_snapshot","arguments":{}}}"#.utf8))
        guard let data = responses.first,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let structured = result["structuredContent"] as? [String: Any] else {
            context.fail("missing structuredContent")
            return
        }
        for section in ["freshness", "quota", "session", "account", "health", "resetRadar"] {
            context.expectTrue(structured[section] != nil, "the panel reads the \(section) section")
        }
        let fetchedAt = (structured["quota"] as? [String: Any])?["fetchedAt"] as? String
        context.expectTrue(fetchedAt?.contains("T") == true, "the dates are ISO-8601: \(fetchedAt ?? "")")
    }

    test("MCP tools/call answers with a readable line and no error") { context in
        let router = MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>")
        let responses = await router.handle(line: Data(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_usage_snapshot","arguments":{}}}"#.utf8))
        guard let data = responses.first,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let content = result["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            context.fail("missing content")
            return
        }
        context.expectEqual(content.first?["type"] as? String, "text")
        context.expectTrue(text.contains("84%"), "the line carries the weekly quota")
        context.expectEqual(result["isError"] as? Bool, false)
    }

    test("MCP tools/call reports a failing tool as an error result") { context in
        let router = MCPRouter(toolService: FailingMCPToolService(), panelHTML: "<html>panel</html>")
        let responses = await router.handle(line: Data(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_usage_snapshot","arguments":{}}}"#.utf8))
        guard let data = responses.first,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let content = result["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            context.fail("missing error result")
            return
        }
        context.expectEqual(result["isError"] as? Bool, true)
        context.expectTrue(text.contains("quota offline"), "the reason is reported: \(text)")
    }

    test("MCP tools/call refuses an unknown tool") { context in
        let router = MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>")
        let responses = await router.handle(line: Data(#"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"rm_minus_rf","arguments":{}}}"#.utf8))
        guard let data = responses.first,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any] else {
            context.fail("missing error response")
            return
        }
        context.expectEqual(error["code"] as? Int, -32602)
    }

    test("MCP get_model_health answers with the verdict") { context in
        let service = RecordingMCPToolService()
        let router = MCPRouter(toolService: service, panelHTML: "<html>panel</html>")
        let responses = await router.handle(line: Data(#"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"get_model_health","arguments":{"windowDays":14}}}"#.utf8))
        guard let data = responses.first,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let structured = result["structuredContent"] as? [String: Any] else {
            context.fail("missing health result")
            return
        }
        context.expectEqual(service.windowDays, 14)
        context.expectEqual(structured["status"] as? String, "insufficient")
    }

    test("MCP scan_reset_sources answers with the source health") { context in
        let router = MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>")
        let responses = await router.handle(line: Data(#"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"scan_reset_sources","arguments":{}}}"#.utf8))
        guard let data = responses.first,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let structured = result["structuredContent"] as? [String: Any] else {
            context.fail("missing radar result")
            return
        }
        context.expectTrue(structured["sources"] != nil)
    }

    test("MCP show_usage_panel returns the snapshot with the UI metadata") { context in
        let router = MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>")
        let responses = await router.handle(line: Data(#"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"show_usage_panel","arguments":{}}}"#.utf8))
        guard let data = responses.first,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let meta = result["_meta"] as? [String: Any],
              let structured = result["structuredContent"] as? [String: Any] else {
            context.fail("missing panel result")
            return
        }
        context.expectEqual((meta["ui"] as? [String: Any])?["resourceUri"] as? String, "ui://codexinfo/panel.html")
        context.expectEqual(structured["quota"] != nil, true)
    }

    test("MCP open_dashboard opens the panel") { context in
        let service = RecordingMCPToolService()
        let router = MCPRouter(toolService: service, panelHTML: "<html>panel</html>")
        let responses = await router.handle(line: Data(#"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"open_dashboard","arguments":{}}}"#.utf8))
        guard let data = responses.first,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any],
              let structured = result["structuredContent"] as? [String: Any] else {
            context.fail("missing dashboard result")
            return
        }
        context.expectEqual(service.openCount, 1)
        context.expectEqual(structured["opened"] as? Bool, true)
    }

    test("MCP open_dashboard reports the missing app instead of a success") { context in
        // Design 6.7: the tool answers with an install and start hint when the
        // menu bar app is not running.
        let service = FailingDashboardToolService()
        let router = MCPRouter(toolService: service, panelHTML: "<html>panel</html>")
        let responses = await router.handle(line: Data(#"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"open_dashboard","arguments":{}}}"#.utf8))
        guard let data = responses.first,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? [String: Any] else {
            context.fail("missing dashboard result")
            return
        }
        context.expectEqual(result["isError"] as? Bool, true, "the tool reports the failure")
        let content = result["content"] as? [[String: Any]]
        let text = content?.first?["text"] as? String ?? ""
        context.expectTrue(text.contains("没有运行"), "the answer names the missing app")
        context.expectTrue(text.contains("dist/CodexInfo.app"), "the answer carries the install hint")
    }

    test("MCP get_usage_snapshot forwards the refresh flag") { context in
        let service = RecordingMCPToolService()
        let router = MCPRouter(toolService: service, panelHTML: "<html>panel</html>")
        _ = await router.handle(line: Data(#"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"get_usage_snapshot","arguments":{"refresh":true}}}"#.utf8))
        context.expectEqual(service.refresh, true)
    }
}

/// A service that records how it was called.
final class RecordingMCPToolService: MCPToolService, @unchecked Sendable {
    private let lock = NSLock()
    private var _refresh: Bool?
    private var _windowDays: Int?
    private var _openCount = 0

    var refresh: Bool? { lock.lock(); defer { lock.unlock() }; return _refresh }
    var windowDays: Int? { lock.lock(); defer { lock.unlock() }; return _windowDays }
    var openCount: Int { lock.lock(); defer { lock.unlock() }; return _openCount }

    func usageSnapshot(refresh: Bool, now: Date) async throws -> UsageSnapshot {
        lock.lock(); _refresh = refresh; lock.unlock()
        return MCPTestFixtures.snapshot
    }
    func modelHealth(windowDays: Int, now: Date) async throws -> HealthSnapshot {
        lock.lock(); _windowDays = windowDays; lock.unlock()
        return .empty
    }
    func scanResetSources(now: Date) async throws -> ResetRadarSnapshot { .empty }
    func openDashboard() async throws {
        lock.lock(); _openCount += 1; lock.unlock()
    }
}

struct FakeMCPToolService: MCPToolService {
    func usageSnapshot(refresh: Bool, now: Date) async throws -> UsageSnapshot { MCPTestFixtures.snapshot }
    func modelHealth(windowDays: Int, now: Date) async throws -> HealthSnapshot { .empty }
    func scanResetSources(now: Date) async throws -> ResetRadarSnapshot { .empty }
    func openDashboard() async throws {}
}

/// A service whose quota area is offline, to prove that a tool failure is reported.
struct FailingMCPToolService: MCPToolService {
    enum Failure: LocalizedError {
        case quotaOffline

        var errorDescription: String? { "quota offline" }
    }

    func usageSnapshot(refresh: Bool, now: Date) async throws -> UsageSnapshot { throw Failure.quotaOffline }
    func modelHealth(windowDays: Int, now: Date) async throws -> HealthSnapshot { .empty }
    func scanResetSources(now: Date) async throws -> ResetRadarSnapshot { .empty }
    func openDashboard() async throws {}
}

/// A service whose dashboard is not there, to prove that the tool reports it.
struct FailingDashboardToolService: MCPToolService {
    func usageSnapshot(refresh: Bool, now: Date) async throws -> UsageSnapshot { MCPTestFixtures.snapshot }
    func modelHealth(windowDays: Int, now: Date) async throws -> HealthSnapshot { .empty }
    func scanResetSources(now: Date) async throws -> ResetRadarSnapshot { .empty }
    func openDashboard() async throws { throw DashboardError.appNotRunning }
}

enum MCPTestFixtures {
    static let snapshot = UsageSnapshot(
        generatedAt: Date(timeIntervalSince1970: 1_790_000_000),
        freshness: Freshness(quota: .fresh, session: .fresh, account: .fresh, sources: .fresh),
        quota: QuotaSnapshot(planType: "pro", weeklyRemainingPercent: 84, weeklyResetsAt: nil, source: .official, fetchedAt: Date(timeIntervalSince1970: 1_790_000_000)),
        resetCredits: ResetCreditsSnapshot(availableCount: 1, reportedAvailableCount: 1, items: [], fetchedAt: Date(timeIntervalSince1970: 1_790_000_000)),
        session: .empty,
        account: AccountSnapshot(todayTokens: 1, totalTokens: 2, source: "local", updatedAt: Date(timeIntervalSince1970: 1_790_000_000)),
        health: .empty,
        resetRadar: .empty
    )
}
