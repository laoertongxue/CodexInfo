import Foundation
import CodexInfoCore
import CodexInfoLive
import CodexInfoMCPKit

/// Registers the tests of the live services and of the MCP stdio loop.
func registerLiveTests() {
    test("Live tool service answers with the snapshot of the environment") { context in
        let builder = RecordingSnapshotBuilder(snapshot: MCPTestFixtures.snapshot)
        let service = LiveMCPToolService(
            builder: builder,
            radar: RecordingRadarScanner(),
            dashboard: RecordingDashboard()
        )
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let snapshot = try await service.usageSnapshot(refresh: true, now: now)
        context.expectEqual(snapshot.quota.weeklyRemainingPercent, 84)
        context.expectEqual(builder.refresh, true, "the refresh flag reaches the environment")
        context.expectEqual(builder.windowDays, 7, "the snapshot uses the default baseline window")
    }

    test("Live tool service answers with the health verdict of the snapshot") { context in
        let builder = RecordingSnapshotBuilder(snapshot: MCPTestFixtures.snapshot)
        let service = LiveMCPToolService(
            builder: builder,
            radar: RecordingRadarScanner(),
            dashboard: RecordingDashboard()
        )
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let health = try await service.modelHealth(windowDays: 14, now: now)
        context.expectEqual(health.status, .insufficient)
        context.expectEqual(builder.windowDays, 14, "the requested baseline window reaches the environment")
    }

    test("Live tool service scans the reset sources") { context in
        let radar = RecordingRadarScanner()
        let service = LiveMCPToolService(
            builder: RecordingSnapshotBuilder(snapshot: MCPTestFixtures.snapshot),
            radar: radar,
            dashboard: RecordingDashboard()
        )
        let snapshot = try await service.scanResetSources(now: Date(timeIntervalSince1970: 1_790_000_000))
        context.expectEqual(radar.scanCount, 1, "the radar was scanned once")
        context.expectEqual(snapshot.sources.count, radar.snapshot.sources.count)
    }

    test("Live tool service opens the dashboard") { context in
        let dashboard = RecordingDashboard()
        let service = LiveMCPToolService(
            builder: RecordingSnapshotBuilder(snapshot: MCPTestFixtures.snapshot),
            radar: RecordingRadarScanner(),
            dashboard: dashboard
        )
        try await service.openDashboard()
        context.expectEqual(dashboard.openCount, 1, "the dashboard was opened once")
    }

    test("The dashboard opens the codexinfo URL") { context in
        context.expectEqual(SystemBrowserDashboard.dashboardURL.absoluteString, "codexinfo://show")
    }

    test("MCP stdio server answers every request with one line") { context in
        let input = ScriptedLineReader(lines: [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"resources/read","params":{"uri":"ui://codexinfo/panel.html"}}"#,
        ])
        let output = RecordingLineWriter()
        let server = MCPStdioServer(router: MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>"))
        await server.run(input: input, output: output)
        let lines = await output.lines
        context.expectEqual(lines.count, 3, "every request answered with one line")
        let ids = lines.compactMap { line -> Int? in
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return nil }
            return object["id"] as? Int
        }
        context.expectEqual(ids, [1, 2, 3], "the answers keep the order of the requests")
        for line in lines {
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
            context.expectTrue(object?["result"] != nil, "every line carries a result")
        }
    }

    test("MCP stdio server stays silent for a notification") { context in
        let input = ScriptedLineReader(lines: [
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
        ])
        let output = RecordingLineWriter()
        let server = MCPStdioServer(router: MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>"))
        await server.run(input: input, output: output)
        context.expectEqual(await output.lines.count, 0, "a notification has no answer")
    }

    test("MCP stdio server reports a malformed line as a parse error") { context in
        let input = ScriptedLineReader(lines: [#"{"jsonrpc":"2.0","id":1,"method":"#])
        let output = RecordingLineWriter()
        let server = MCPStdioServer(router: MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>"))
        await server.run(input: input, output: output)
        let lines = await output.lines
        context.expectEqual(lines.count, 1, "the malformed line is answered")
        guard let line = lines.first,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let error = object["error"] as? [String: Any] else {
            context.fail("missing error response")
            return
        }
        context.expectEqual(error["code"] as? Int, -32700)
    }

    test("MCP stdio server stops when the input ends") { context in
        let input = ScriptedLineReader(lines: [])
        let output = RecordingLineWriter()
        let server = MCPStdioServer(router: MCPRouter(toolService: FakeMCPToolService(), panelHTML: "<html>panel</html>"))
        await server.run(input: input, output: output)
        context.expectEqual(await output.lines.count, 0, "the end of the input ends the server")
    }
}

/// A snapshot builder that records how it was called.
final class RecordingSnapshotBuilder: SnapshotBuilding, @unchecked Sendable {
    private let lock = NSLock()
    private var _refresh: Bool?
    private var _windowDays: Int?
    private let snapshot: UsageSnapshot

    init(snapshot: UsageSnapshot) {
        self.snapshot = snapshot
    }

    var refresh: Bool? { lock.withLock { _refresh } }
    var windowDays: Int? { lock.withLock { _windowDays } }

    func buildSnapshot(now: Date, refresh: Bool, windowDays: Int) async -> UsageSnapshot {
        lock.withLock {
            _refresh = refresh
            _windowDays = windowDays
        }
        return snapshot
    }
}

/// A radar that records how often it was scanned.
final class RecordingRadarScanner: ResetRadarScanning, @unchecked Sendable {
    private let lock = NSLock()
    private var _scanCount = 0
    let snapshot: ResetRadarSnapshot

    init(snapshot: ResetRadarSnapshot = .empty) {
        self.snapshot = snapshot
    }

    var scanCount: Int { lock.withLock { _scanCount } }

    func scan(now: Date) async -> ResetRadarSnapshot {
        lock.withLock { _scanCount += 1 }
        return snapshot
    }
}

/// A dashboard that records how often it was opened.
final class RecordingDashboard: DashboardOpening, @unchecked Sendable {
    private let lock = NSLock()
    private var _openCount = 0

    var openCount: Int { lock.withLock { _openCount } }

    func openDashboard() async throws {
        lock.withLock { _openCount += 1 }
    }
}

/// A reader that hands over the prepared lines and then the end of the input.
actor ScriptedLineReader: LineReading {
    private var lines: [String]

    init(lines: [String]) {
        self.lines = lines
    }

    func readLine() async -> String? {
        guard !lines.isEmpty else { return nil }
        return lines.removeFirst()
    }
}

/// A writer that keeps the written lines.
actor RecordingLineWriter: LineWriting {
    private(set) var lines: [Data] = []

    func writeLine(_ data: Data) async {
        lines.append(data)
    }
}
