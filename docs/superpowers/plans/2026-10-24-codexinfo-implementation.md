# CodexInfo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu-bar app and Codex desktop plugin that show Codex quota, reset cards, reset signals, current-session tokens, output tok/s, and a local model-health verdict.

**Architecture:** SwiftPM monorepo. `CodexInfoCore` owns models, collectors, and analytics; `CodexInfoLive` assembles live services; `CodexInfoMCPKit` implements the MCP router; `CodexInfoApp` hosts an `NSStatusItem`/`NSPopover`/`WKWebView`; `CodexInfoMCP` exposes the plugin server. The panel is one React single-file HTML build shared by the menu bar and MCP App surfaces.

**Tech Stack:** Swift 6.4 toolchain (SwiftPM, language mode 5), AppKit/SwiftUI, WebKit, Foundation, React 19 + Vite 8 + TypeScript, MCP Apps SDK 2.0.3, Node 24 (build only), pnpm.

**Spec:** `docs/superpowers/specs/2026-10-24-codexinfo-design.md`

## Global Constraints

- macOS 14+; Swift tools 6.0; `swiftLanguageModes: [.v5]`; no new system dependencies.
- The machine has CommandLineTools only. XCTest and Swift Testing macros are unavailable. All Swift tests run through `swift run codexinfo-tests [--filter <name>]`; failures exit non-zero.
- Node and pnpm are build-time tools only. The shipped app and MCP server must not require Node at runtime.
- Never auto-use a reset card, auto-purchase, inject into Codex, read conversation content, or upload session data.
- `access_token` lives in memory only. It is sent only to `chatgpt.com`; never log, cache, snapshot, or render it.
- All network calls go through `HTTPClient`; every service that touches the network must be testable with a mock client.
- Tests use temporary directories and fake tokens. Never read or write the real `~/.codex` in automated tests.
- Panel layout is B: header, quota, reset cards, reset tracking, model health, current session (including tok/s), account stats, footer. Width 340, max height 780.
- The menu bar label defaults to `84% · 42 tok/s · 正常`; the bottom Codex chip is not injected.
- Commit after every task. Do not push without explicit approval.
- M0 is a hard gate: if a local plugin cannot render an MCP App, switch the plugin to text summary + `open_dashboard` and keep the menu bar panel. Do not inject client UI.

---

## File Structure

```text
CodexInfo/
├─ Package.swift
├─ Sources/
│  ├─ CodexInfoCore/
│  │  ├─ AppConstants.swift
│  │  ├─ Models/
│  │  │  ├─ RateLimitModels.swift
│  │  │  ├─ QuotaModels.swift
│  │  │  ├─ ResetCreditModels.swift
│  │  │  ├─ SessionModels.swift
│  │  │  ├─ AccountModels.swift
│  │  │  ├─ HealthModels.swift
│  │  │  ├─ ResetRadarModels.swift
│  │  │  └─ SnapshotModels.swift
│  │  ├─ Networking/
│  │  │  ├─ HTTPClient.swift
│  │  │  ├─ CredentialStore.swift
│  │  │  └─ OfficialUsageClient.swift
│  │  ├─ Sessions/
│  │  │  ├─ SessionLogParser.swift
│  │  │  ├─ TurnAggregator.swift
│  │  │  ├─ SessionIndexer.swift
│  │  │  └─ SessionRepository.swift
│  │  ├─ Analytics/
│  │  │  ├─ OutputRateCalculator.swift
│  │  │  ├─ BaselineBuilder.swift
│  │  │  └─ DegradationAnalyzer.swift
│  │  ├─ Services/
│  │  │  ├─ QuotaService.swift
│  │  │  ├─ ResetCreditService.swift
│  │  │  ├─ CodexAppServerClient.swift
│  │  │  ├─ AccountUsageService.swift
│  │  │  ├─ SnapshotBuilder.swift
│  │  │  └─ SnapshotStore.swift
│  │  ├─ ResetRadar/
│  │  │  ├─ ResetSource.swift
│  │  │  ├─ CodexRadarCurrentSource.swift
│  │  │  ├─ CodexRadarFeedSource.swift
│  │  │  ├─ CodexResetsSource.swift
│  │  │  ├─ OpenAIStatusSource.swift
│  │  │  └─ ResetRadarService.swift
│  │  └─ Generated/WebAssets.swift
│  ├─ CodexInfoLive/
│  │  ├─ LiveEnvironment.swift
│  │  └─ LiveMCPToolService.swift
│  ├─ CodexInfoMCPKit/
│  │  ├─ MCPRouter.swift
│  │  ├─ MCPToolService.swift
│  │  └─ MCPJSON.swift
│  ├─ CodexInfoApp/
│  │  ├─ main.swift
│  │  ├─ AppDelegate.swift
│  │  ├─ AppEnvironment.swift
│  │  ├─ MenuBarController.swift
│  │  ├─ PanelViewController.swift
│  │  ├─ PanelMessage.swift
│  │  ├─ StatusTitleFormatter.swift
│  │  ├─ SettingsStore.swift
│  │  ├─ SettingsView.swift
│  │  ├─ NotificationController.swift
│  │  └─ LaunchAtLogin.swift
│  ├─ CodexInfoMCP/
│  │  └─ main.swift
│  └─ CodexInfoTests/
│     ├─ main.swift
│     ├─ TestSupport.swift
│     ├─ CoreTests.swift
│     └─ MCPTests.swift
├─ Web/
│  ├─ package.json
│  ├─ pnpm-lock.yaml
│  ├─ vite.config.ts
│  ├─ tsconfig.json
│  ├─ index.html
│  ├─ public/mock-snapshot.json
│  ├─ src/main.tsx
│  ├─ src/App.tsx
│  ├─ src/styles.css
│  ├─ src/format.ts
│  ├─ src/data/types.ts
│  ├─ src/host/types.ts
│  ├─ src/host/detect.ts
│  ├─ src/host/mockHost.ts
│  ├─ src/host/nativeHost.ts
│  ├─ src/host/mcpHost.ts
│  ├─ src/host/useHost.ts
│  └─ tests/panel.spec.ts
├─ scripts/
│  ├─ build-web.sh
│  ├─ build-app.sh
│  ├─ install-plugin.sh
│  ├─ dev.sh
│  ├─ test.sh
│  └─ mcp_smoke.py
├─ .agents/plugins/marketplace.json
├─ plugins/codexinfo/
│  ├─ .codex-plugin/plugin.json
│  ├─ .mcp.json.template
│  ├─ skills/codex-usage/SKILL.md
│  └─ assets/icon.svg
├─ Tests/Fixtures/
├─ docs/superpowers/
└─ spikes/mcp-app/
```

---

### Task 1: M0 MCP App Feasibility Gate

**Files:**
- Create: `spikes/mcp-app/server.mjs`
- Create: `spikes/mcp-app/plugins/codexinfo-spike/.codex-plugin/plugin.json`
- Create: `spikes/mcp-app/plugins/codexinfo-spike/.mcp.json`
- Create: `spikes/mcp-app/.agents/plugins/marketplace.json`
- Create: `spikes/mcp-app/README.md`

**Interfaces:**
- Consumes: none.
- Produces: a recorded M0 result. The spike code is throwaway and must not be imported into `Sources/`.

- [ ] **Step 1: Write the minimal MCP App server**

```js
// spikes/mcp-app/server.mjs
import readline from "node:readline";

const HTML = `<!doctype html><html><body style="font:14px -apple-system;padding:24px">
<h2>CodexInfo MCP App OK</h2><p>If you can read this inside Codex, the host renders MCP Apps.</p>
</body></html>`;

function send(value) {
  process.stdout.write(JSON.stringify(value) + "\n");
}
function ok(id, result) { send({ jsonrpc: "2.0", id, result }); }
function fail(id, code, message) { send({ jsonrpc: "2.0", id, error: { code, message } }); }

const rl = readline.createInterface({ input: process.stdin });
rl.on("line", (line) => {
  let request;
  try { request = JSON.parse(line); } catch { return; }
  const { id, method, params } = request;
  if (method === "initialize") {
    return ok(id, {
      protocolVersion: "2025-06-18",
      capabilities: { tools: {}, resources: {} },
      serverInfo: { name: "codexinfo-spike", version: "0.0.1" },
    });
  }
  if (method === "notifications/initialized") return;
  if (method === "ping") return ok(id, {});
  if (method === "tools/list") {
    return ok(id, {
      tools: [{
        name: "show_spike_panel",
        description: "Render the CodexInfo MCP App spike panel.",
        inputSchema: { type: "object", properties: {}, additionalProperties: false },
        _meta: {
          ui: { resourceUri: "ui://codexinfo-spike/panel.html" },
          "ui/resourceUri": "ui://codexinfo-spike/panel.html",
          "openai/outputTemplate": "ui://codexinfo-spike/panel.html",
        },
      }],
    });
  }
  if (method === "tools/call") {
    if (params?.name !== "show_spike_panel") return fail(id, -32602, "unknown tool");
    return ok(id, { content: [{ type: "text", text: "CodexInfo spike panel" }], structuredContent: { ok: true } });
  }
  if (method === "resources/list") {
    return ok(id, {
      resources: [{
        uri: "ui://codexinfo-spike/panel.html",
        name: "CodexInfo spike panel",
        mimeType: "text/html;profile=mcp-app",
      }],
    });
  }
  if (method === "resources/read") {
    if (params?.uri !== "ui://codexinfo-spike/panel.html") return fail(id, -32602, "unknown resource");
    return ok(id, { contents: [{ uri: params.uri, mimeType: "text/html;profile=mcp-app", text: HTML }] });
  }
  return fail(id, -32601, `unknown method ${method}`);
});
```

- [ ] **Step 2: Write the spike plugin manifest**

`spikes/mcp-app/plugins/codexinfo-spike/.codex-plugin/plugin.json`:

```json
{
  "name": "codexinfo-spike",
  "version": "0.0.1",
  "description": "M0 feasibility spike for CodexInfo MCP Apps.",
  "author": { "name": "laoer" },
  "mcpServers": "./.mcp.json"
}
```

`spikes/mcp-app/plugins/codexinfo-spike/.mcp.json` (replace `/opt/homebrew/bin/node` only if `which node` differs):

```json
{
  "mcpServers": {
    "codexinfo_spike": {
      "command": "/opt/homebrew/bin/node",
      "args": ["/Users/laoer/Documents/CodexInfo/spikes/mcp-app/server.mjs"],
      "cwd": "/Users/laoer/Documents/CodexInfo/spikes/mcp-app",
      "enabled": true,
      "startup_timeout_sec": 10,
      "tool_timeout_sec": 30
    }
  }
}
```

`spikes/mcp-app/.agents/plugins/marketplace.json`:

```json
{
  "name": "codexinfo-spike",
  "interface": { "displayName": "CodexInfo Spike" },
  "plugins": [
    {
      "name": "codexinfo-spike",
      "source": { "source": "local", "path": "./plugins/codexinfo-spike" },
      "policy": { "installation": "AVAILABLE", "authentication": "ON_INSTALL" },
      "category": "Developer Tools"
    }
  ]
}
```

- [ ] **Step 3: Verify the server protocol without Codex**

Run:

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
  '{"jsonrpc":"2.0","id":3,"method":"resources/read","params":{"uri":"ui://codexinfo-spike/panel.html"}}' \
  | node spikes/mcp-app/server.mjs
```

Expected: three JSON lines; line 2 contains `show_spike_panel`; line 3 contains `text/html;profile=mcp-app` and `CodexInfo MCP App OK`.

- [ ] **Step 4: Install the spike as a local plugin and verify rendering in Codex**

Add a local marketplace entry with the repo root as the source. In Codex, open plugin settings, add local marketplace `/Users/laoer/Documents/CodexInfo/spikes/mcp-app`, install `codexinfo-spike`, then ask the model to call `show_spike_panel`.

If the UI step is not exposed in the current Codex build, use this temporary config block and restart Codex:

```toml
[marketplaces.codexinfo-spike]
source_type = "local"
source = "/Users/laoer/Documents/CodexInfo/spikes/mcp-app"

[plugins."codexinfo-spike@codexinfo-spike"]
enabled = true
```

Expected: the iframe renders `CodexInfo MCP App OK`.

- [ ] **Step 5: Record the gate result and commit**

Write `spikes/mcp-app/README.md` with one of:

```markdown
# M0 result

- Date: 2026-10-24
- Host: Codex desktop <version>
- Result: PASS — tool list resourceUri rendered in the MCP App iframe.
- Notes: <exact tool name and observation>
```

or:

```markdown
# M0 result

- Result: FAIL — tool ran but the host did not render `ui://`.
- Fallback: plugin returns text summary + `open_dashboard`; menu bar panel is primary.
```

Commit:

```bash
git add spikes/mcp-app
git commit -m "spike: verify Codex MCP App rendering"
```

Do not continue to Task 17's MCP App UI if this gate fails; continue with the menu-bar path and use the documented fallback.

---

### Task 2: Swift Package, Custom Test Runner, HTTP and Credentials

**Files:**
- Create: `Package.swift`
- Create: `Sources/CodexInfoCore/AppConstants.swift`
- Create: `Sources/CodexInfoCore/Networking/HTTPClient.swift`
- Create: `Sources/CodexInfoCore/Networking/CredentialStore.swift`
- Create: `Sources/CodexInfoTests/TestSupport.swift`
- Create: `Sources/CodexInfoTests/main.swift`
- Create: `Sources/CodexInfoTests/CoreTests.swift`

**Interfaces:**
- Consumes: none.
- Produces:
  - `HTTPClient.send(_:) async throws -> HTTPResponse`
  - `FileCredentialStore.load() throws -> CodexCredentials`
  - `swift run codexinfo-tests [--filter <substring>]`

- [ ] **Step 1: Write the failing credential tests**

`Sources/CodexInfoTests/TestSupport.swift`:

```swift
import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

final class TestContext {
    private(set) var failures: [String] = []

    func expectEqual<T: Equatable>(
        _ actual: T,
        _ expected: T,
        _ label: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if actual != expected {
            failures.append("\(label) at \(file):\(line): expected \(expected), got \(actual)")
        }
    }

    func expectTrue(_ condition: Bool, _ label: String = "", file: StaticString = #filePath, line: UInt = #line) {
        if !condition { failures.append("\(label) at \(file):\(line)") }
    }

    func expectThrows<T>(_ expression: @autoclosure () throws -> T, _ label: String = "", file: StaticString = #filePath, line: UInt = #line) {
        do {
            _ = try expression()
            failures.append("\(label) at \(file):\(line): expected an error")
        } catch { }
    }

    func fail(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        failures.append("\(message) at \(file):\(line)")
    }
}

struct TestCase {
    let name: String
    let body: (TestContext) async throws -> Void
}

final class TestRegistry {
    static let shared = TestRegistry()
    private var cases: [TestCase] = []
    private init() {}

    func add(_ name: String, _ body: @escaping (TestContext) async throws -> Void) {
        cases.append(TestCase(name: name, body: body))
    }

    func run(filter: String?) async -> Int {
        var failed = 0
        var ran = 0
        for testCase in cases {
            if let filter, !testCase.name.localizedCaseInsensitiveContains(filter) { continue }
            ran += 1
            let context = TestContext()
            do {
                try await testCase.body(context)
            } catch {
                context.fail("threw: \(error)")
            }
            if context.failures.isEmpty {
                print("PASS \(testCase.name)")
            } else {
                failed += 1
                print("FAIL \(testCase.name)")
                for failure in context.failures { print("  \(failure)") }
            }
        }
        print("SUMMARY ran=\(ran) failed=\(failed)")
        return failed
    }
}

func test(_ name: String, _ body: @escaping (TestContext) async throws -> Void) {
    TestRegistry.shared.add(name, body: body)
}
```

`Sources/CodexInfoTests/main.swift`:

```swift
import Foundation

registerCoreTests()

let arguments = CommandLine.arguments
let filter: String?
if let argument = arguments.first(where: { $0.hasPrefix("--filter=") }) {
    filter = String(argument.dropFirst("--filter=".count))
} else if let index = arguments.firstIndex(of: "--filter"), arguments.indices.contains(index + 1) {
    filter = arguments[index + 1]
} else {
    filter = nil
}
let failures = await TestRegistry.shared.run(filter: filter)
exit(failures == 0 ? 0 : 1)
```

`Sources/CodexInfoTests/CoreTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift run codexinfo-tests --filter CredentialStore`

Expected: compile failure because `CodexInfoCore`, `FileCredentialStore`, and the package products do not exist yet.

- [ ] **Step 3: Create the package and production types**

`Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexInfo",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexInfoCore", targets: ["CodexInfoCore"]),
        .executable(name: "codexinfo-tests", targets: ["CodexInfoTests"])
    ],
    targets: [
        .target(name: "CodexInfoCore", path: "Sources/CodexInfoCore"),
        .executableTarget(
            name: "CodexInfoTests",
            dependencies: ["CodexInfoCore"],
            path: "Sources/CodexInfoTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
```

`Sources/CodexInfoCore/AppConstants.swift`:

```swift
import Foundation

public enum AppConstants {
    public static let appName = "CodexInfo"
    public static let version = "0.1.0"
    public static let bundleIdentifier = "com.laoer.codexinfo"
    public static let supportDirectoryName = "CodexInfo"
    public static let codexHomeEnvironmentKey = "CODEX_HOME"
    public static let baseURL = URL(string: "https://chatgpt.com/backend-api")!
    public static let weeklyWindowMinutes: Double = 10_080
    public static let fiveHourWindowMinutes: Double = 300
    public static let refreshQuotaSeconds: TimeInterval = 60
    public static let refreshSessionSeconds: TimeInterval = 5
    public static let refreshAccountSeconds: TimeInterval = 300
    public static let refreshSourcesSeconds: TimeInterval = 60
    public static let staleSeconds: TimeInterval = 300
    public static let userAgent = "CodexInfo/0.1.0"
}
```

`Sources/CodexInfoCore/Networking/HTTPClient.swift`:

```swift
import Foundation

public struct HTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public let headers: [String: String]

    public init(data: Data, statusCode: Int, headers: [String: String] = [:]) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
    }
}

public enum HTTPError: Error, Equatable {
    case invalidResponse
    case status(Int)
    case emptyResponse
}

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HTTPError.invalidResponse }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers[String(describing: key)] = String(describing: value)
        }
        return HTTPResponse(data: data, statusCode: http.statusCode, headers: headers)
    }
}
```

`Sources/CodexInfoCore/Networking/CredentialStore.swift`:

```swift
import Foundation

public struct CodexCredentials: Equatable, Sendable {
    public let accessToken: String

    public init(accessToken: String) {
        self.accessToken = accessToken
    }
}

public enum CredentialError: Error, Equatable {
    case fileNotFound(String)
    case invalidJSON
    case tokenMissing
}

public protocol CredentialProviding: Sendable {
    func load() throws -> CodexCredentials
}

public struct FileCredentialStore: CredentialProviding {
    public let authURL: URL

    public init(authURL: URL = FileCredentialStore.defaultAuthURL()) {
        self.authURL = authURL
    }

    public func load() throws -> CodexCredentials {
        guard FileManager.default.fileExists(atPath: authURL.path) else {
            throw CredentialError.fileNotFound(authURL.path)
        }
        return try Self.parse(Data(contentsOf: authURL))
    }

    public static func parse(_ data: Data) throws -> CodexCredentials {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CredentialError.invalidJSON
        }
        let tokens = root["tokens"] as? [String: Any]
        let candidates: [Any?] = [
            root["access_token"],
            root["accessToken"],
            tokens?["access_token"],
            tokens?["accessToken"],
        ]
        guard let token = candidates.compactMap({ $0 as? String }).first(where: { !$0.isEmpty }) else {
            throw CredentialError.tokenMissing
        }
        return CodexCredentials(accessToken: token)
    }

    public static func defaultAuthURL() -> URL {
        let environment = ProcessInfo.processInfo.environment
        let codexHome = environment[AppConstants.codexHomeEnvironmentKey]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        return codexHome.appendingPathComponent("auth.json")
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift run codexinfo-tests --filter CredentialStore`

Expected: three `PASS` lines and `SUMMARY ran=3 failed=0`.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/CodexInfoCore Sources/CodexInfoTests
git commit -m "feat: add core package, test runner and credential parsing"
```

---

### Task 3: Rate Limit Models and Weekly Window Selection

**Files:**
- Create: `Sources/CodexInfoCore/Models/RateLimitModels.swift`
- Create: `Sources/CodexInfoCore/Models/QuotaModels.swift`
- Create: `Sources/CodexInfoCore/Services/RateLimitWindowSelector.swift`
- Modify: `Sources/CodexInfoTests/CoreTests.swift`

**Interfaces:**
- Consumes: none.
- Produces:
  - `RateLimitSnapshot`, `RateLimitWindow`
  - `RateLimitWindowSelector.weekly(from:)`, `.fiveHour(from:)`
  - `QuotaSnapshot`, `QuotaSource`

- [ ] **Step 1: Add failing selector tests**

Append to `registerCoreTests()` in `Sources/CodexInfoTests/CoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift run codexinfo-tests --filter RateLimit`

Expected: compile failure because the models and selector do not exist.

- [ ] **Step 3: Implement the models and selector**

`Sources/CodexInfoCore/Models/RateLimitModels.swift`:

```swift
import Foundation

public struct RateLimitWindow: Codable, Equatable, Sendable {
    public let usedPercent: Double
    public let windowDurationMins: Double?
    public let resetsAt: Int?

    public init(usedPercent: Double, windowDurationMins: Double?, resetsAt: Int?) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Int {
        Int((100 - usedPercent).rounded()).clamped(to: 0...100)
    }
}

public struct RateLimitSnapshot: Codable, Equatable, Sendable {
    public let limitId: String?
    public let primary: RateLimitWindow?
    public let secondary: RateLimitWindow?
    public let planType: String?

    public init(limitId: String?, primary: RateLimitWindow?, secondary: RateLimitWindow?, planType: String?) {
        self.limitId = limitId
        self.primary = primary
        self.secondary = secondary
        self.planType = planType
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
```

`Sources/CodexInfoCore/Services/RateLimitWindowSelector.swift`:

```swift
import Foundation

public enum RateLimitWindowSelector {
    public static func weekly(from snapshot: RateLimitSnapshot) -> RateLimitWindow? {
        window(in: snapshot, near: AppConstants.weeklyWindowMinutes)
    }

    public static func fiveHour(from snapshot: RateLimitSnapshot) -> RateLimitWindow? {
        window(in: snapshot, near: AppConstants.fiveHourWindowMinutes)
    }

    private static func window(in snapshot: RateLimitSnapshot, near target: Double) -> RateLimitWindow? {
        [snapshot.primary, snapshot.secondary]
            .compactMap { $0 }
            .first { window in
                guard let duration = window.windowDurationMins else { return false }
                return abs(duration - target) <= target * 0.05
            }
    }
}

public enum RateLimitBucketSelector {
    public static func select(_ buckets: [String: RateLimitSnapshot]) -> RateLimitSnapshot? {
        buckets["codex"] ?? buckets.values.first { $0.limitId == "codex" }
    }
}
```

`Sources/CodexInfoCore/Models/QuotaModels.swift`:

```swift
import Foundation

public enum QuotaSource: String, Codable, Equatable, Sendable {
    case official
    case appServer
    case session
}

public struct QuotaSnapshot: Codable, Equatable, Sendable {
    public let planType: String?
    public let weeklyRemainingPercent: Int?
    public let weeklyResetsAt: Date?
    public let source: QuotaSource
    public let fetchedAt: Date

    public init(planType: String?, weeklyRemainingPercent: Int?, weeklyResetsAt: Date?, source: QuotaSource, fetchedAt: Date) {
        self.planType = planType
        self.weeklyRemainingPercent = weeklyRemainingPercent
        self.weeklyResetsAt = weeklyResetsAt
        self.source = source
        self.fetchedAt = fetchedAt
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift run codexinfo-tests --filter RateLimit`

Expected: five `PASS` lines and `SUMMARY ran=5 failed=0`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexInfoCore/Models Sources/CodexInfoCore/Services/RateLimitWindowSelector.swift Sources/CodexInfoTests/CoreTests.swift
git commit -m "feat: map rate limit windows by duration"
```

---

### Task 4: Official Usage Client and Quota Service

**Files:**
- Create: `Sources/CodexInfoCore/Networking/OfficialUsageClient.swift`
- Create: `Sources/CodexInfoCore/Services/QuotaService.swift`
- Modify: `Sources/CodexInfoTests/CoreTests.swift`

**Interfaces:**
- Consumes: `HTTPClient`, `CredentialProviding`, `RateLimitSnapshot`, `QuotaSnapshot`.
- Produces:
  - `OfficialUsageClient.fetchUsage() async throws -> OfficialUsage`
  - `QuotaService.quotaSnapshot(now:) async -> QuotaSnapshot?`
  - `QuotaFallbackProviding.fallbackQuota(now:) async -> QuotaSnapshot?`

- [ ] **Step 1: Add failing official-client and fallback tests**

Append to `registerCoreTests()`:

```swift
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
```

Add test doubles at the bottom of `CoreTests.swift` (outside `registerCoreTests`):

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift run codexinfo-tests --filter Quota`

Expected: compile failure because the client, service, and protocols do not exist.

- [ ] **Step 3: Implement the official client and quota service**

`Sources/CodexInfoCore/Networking/OfficialUsageClient.swift`:

```swift
import Foundation

public struct OfficialUsage: Equatable, Sendable {
    public let planType: String?
    public let rateLimits: RateLimitSnapshot?
    public let rateLimitsByLimitID: [String: RateLimitSnapshot]
}

public enum OfficialUsageError: Error, Equatable {
    case unauthorized
    case httpStatus(Int)
    case invalidPayload
}

public struct OfficialUsageClient: Sendable {
    private let http: HTTPClient
    private let credentials: CredentialProviding
    private let baseURL: URL

    public init(http: HTTPClient, credentials: CredentialProviding, baseURL: URL = AppConstants.baseURL) {
        self.http = http
        self.credentials = credentials
        self.baseURL = baseURL
    }

    public func fetchUsage() async throws -> OfficialUsage {
        let request = try authorizedRequest(path: "/wham/usage")
        let response = try await http.send(request)
        guard response.statusCode != 401, response.statusCode != 403 else { throw OfficialUsageError.unauthorized }
        guard (200..<300).contains(response.statusCode) else { throw OfficialUsageError.httpStatus(response.statusCode) }
        guard let object = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            throw OfficialUsageError.invalidPayload
        }
        return try Self.decodeUsage(object)
    }

    private func authorizedRequest(path: String) throws -> URLRequest {
        let token = try credentials.load().accessToken
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    static func decodeUsage(_ object: [String: Any]) throws -> OfficialUsage {
        let planType = object["plan_type"] as? String ?? object["planType"] as? String
        let rateLimitsObject = object["rate_limits"] as? [String: Any]
            ?? object["rateLimits"] as? [String: Any]
        let rateLimits = rateLimitsObject.flatMap(Self.decodeSnapshot)
        let byIDObject = object["rate_limits_by_limit_id"] as? [String: Any]
            ?? object["rateLimitsByLimitId"] as? [String: Any]
        var byID: [String: RateLimitSnapshot] = [:]
        for (key, value) in byIDObject ?? [:] {
            if let dict = value as? [String: Any], let snapshot = Self.decodeSnapshot(dict) {
                byID[key] = snapshot
            }
        }
        return OfficialUsage(planType: planType, rateLimits: rateLimits, rateLimitsByLimitID: byID)
    }

    private static func decodeSnapshot(_ object: [String: Any]) -> RateLimitSnapshot? {
        guard object["limit_id"] != nil || object["limitId"] != nil || object["primary"] != nil else { return nil }
        return RateLimitSnapshot(
            limitId: object["limit_id"] as? String ?? object["limitId"] as? String,
            primary: decodeWindow(object["primary"] as? [String: Any]),
            secondary: decodeWindow(object["secondary"] as? [String: Any]),
            planType: object["plan_type"] as? String ?? object["planType"] as? String
        )
    }

    private static func decodeWindow(_ object: [String: Any]?) -> RateLimitWindow? {
        guard let object else { return nil }
        guard let used = object["used_percent"] as? Double ?? (object["used_percent"] as? NSNumber)?.doubleValue else { return nil }
        let duration = (object["window_minutes"] as? NSNumber)?.doubleValue
            ?? (object["windowDurationMins"] as? NSNumber)?.doubleValue
        let resets = (object["resets_at"] as? NSNumber)?.intValue
            ?? (object["resetsAt"] as? NSNumber)?.intValue
        return RateLimitWindow(usedPercent: used, windowDurationMins: duration, resetsAt: resets)
    }
}
```

`Sources/CodexInfoCore/Services/QuotaService.swift`:

```swift
import Foundation

public protocol QuotaSnapshotProviding: Sendable {
    func quotaSnapshot(now: Date) async -> QuotaSnapshot?
}

public protocol QuotaFallbackProviding: Sendable {
    func fallbackQuota(now: Date) async -> QuotaSnapshot?
}

public actor QuotaService: QuotaSnapshotProviding {
    private let official: OfficialUsageClient
    private let fallback: QuotaFallbackProviding?
    private var cache: QuotaSnapshot?
    private var cachedAt: Date?

    public init(official: OfficialUsageClient, fallback: QuotaFallbackProviding?) {
        self.official = official
        self.fallback = fallback
    }

    public func quotaSnapshot(now: Date = Date()) async -> QuotaSnapshot? {
        if let cache, let cachedAt, now.timeIntervalSince(cachedAt) < AppConstants.refreshQuotaSeconds {
            return cache
        }
        if let usage = try? await official.fetchUsage() {
            let snapshotBucket = RateLimitBucketSelector.select(usage.rateLimitsByLimitID) ?? usage.rateLimits
            let weekly = snapshotBucket.flatMap(RateLimitWindowSelector.weekly)
            let snapshot = QuotaSnapshot(
                planType: usage.planType ?? snapshotBucket?.planType,
                weeklyRemainingPercent: weekly?.remainingPercent,
                weeklyResetsAt: weekly?.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                source: .official,
                fetchedAt: now
            )
            cache = snapshot
            cachedAt = now
            return snapshot
        }
        if let fallbackSnapshot = await fallback?.fallbackQuota(now: now) {
            cache = fallbackSnapshot
            cachedAt = now
            return fallbackSnapshot
        }
        return cache
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift run codexinfo-tests --filter Quota`

Expected: three `PASS` lines and `SUMMARY ran=3 failed=0`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexInfoCore/Networking/OfficialUsageClient.swift Sources/CodexInfoCore/Services/QuotaService.swift Sources/CodexInfoTests/CoreTests.swift
git commit -m "feat: fetch official usage and cache weekly quota"
```

### Task 5: Reset Credit Client and Service

**Files:**
- Create: `Sources/CodexInfoCore/Support/DateParsing.swift`
- Create: `Sources/CodexInfoCore/Models/ResetCreditModels.swift`
- Create: `Sources/CodexInfoCore/Services/ResetCreditService.swift`
- Modify: `Sources/CodexInfoTests/CoreTests.swift`

**Interfaces:**
- Consumes: `HTTPClient`, `CredentialProviding`.
- Produces:
  - `ResetCredit`, `ResetCreditsSnapshot`
  - `OfficialResetCreditsClient.fetch(now:) async throws -> ResetCreditsSnapshot`
  - `ResetCreditService.creditsSnapshot(now:) async -> ResetCreditsSnapshot?`

- [ ] **Step 1: Add failing reset-credit tests**

Append to `registerCoreTests()`:

```swift
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
```

Add the stub outside `registerCoreTests`:

```swift
struct StubResetCreditFallback: ResetCreditFallbackProviding {
    let snapshot: ResetCreditsSnapshot?
    func fallbackCredits(now: Date) async -> ResetCreditsSnapshot? { snapshot }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift run codexinfo-tests --filter ResetCredit`

Expected: compile failure because the reset-credit types and client do not exist.

- [ ] **Step 3: Implement reset-credit models, client, and service**

`Sources/CodexInfoCore/Support/DateParsing.swift`:

```swift
import Foundation

public enum DateParsing {
    public static func iso8601(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    public static func epochSeconds(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber else { return nil }
        return Date(timeIntervalSince1970: number.doubleValue)
    }
}
```

`Sources/CodexInfoCore/Models/ResetCreditModels.swift`:

```swift
import Foundation

public struct ResetCredit: Codable, Equatable, Sendable, Identifiable {
    public let idSuffix: String
    public let status: String
    public let grantedAt: Date?
    public let expiresAt: Date?
    public let title: String?

    public init(id: String, status: String, grantedAt: Date?, expiresAt: Date?, title: String?) {
        self.idSuffix = String(id.suffix(6))
        self.status = status
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
        self.title = title
    }

    public var id: String { idSuffix }

    public var isAvailable: Bool {
        status.lowercased() == "available"
    }

    public func isExpired(now: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}

public struct ResetCreditsSnapshot: Codable, Equatable, Sendable {
    public let availableCount: Int
    public let reportedAvailableCount: Int?
    public let items: [ResetCredit]
    public let fetchedAt: Date

    public init(availableCount: Int, reportedAvailableCount: Int?, items: [ResetCredit], fetchedAt: Date) {
        self.availableCount = availableCount
        self.reportedAvailableCount = reportedAvailableCount
        self.items = items
        self.fetchedAt = fetchedAt
    }
}
```

`Sources/CodexInfoCore/Services/ResetCreditService.swift`:

```swift
import Foundation

public protocol ResetCreditsProviding: Sendable {
    func creditsSnapshot(now: Date) async -> ResetCreditsSnapshot?
}

public protocol ResetCreditFallbackProviding: Sendable {
    func fallbackCredits(now: Date) async -> ResetCreditsSnapshot?
}

public struct OfficialResetCreditsClient: Sendable {
    private let http: HTTPClient
    private let credentials: CredentialProviding
    private let baseURL: URL

    public init(http: HTTPClient, credentials: CredentialProviding, baseURL: URL = AppConstants.baseURL) {
        self.http = http
        self.credentials = credentials
        self.baseURL = baseURL
    }

    public func fetch(now: Date = Date()) async throws -> ResetCreditsSnapshot {
        let token = try credentials.load().accessToken
        var request = URLRequest(url: baseURL.appendingPathComponent("/wham/rate-limit-reset-credits"))
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")

        let response = try await http.send(request)
        guard response.statusCode != 401, response.statusCode != 403 else { throw OfficialUsageError.unauthorized }
        guard (200..<300).contains(response.statusCode) else { throw OfficialUsageError.httpStatus(response.statusCode) }
        guard let root = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            throw OfficialUsageError.invalidPayload
        }

        let credits = (root["credits"] as? [[String: Any]] ?? []).compactMap { item -> ResetCredit? in
            guard let id = item["id"] as? String, let status = item["status"] as? String else { return nil }
            return ResetCredit(
                id: id,
                status: status,
                grantedAt: DateParsing.iso8601(item["granted_at"] as? String) ?? DateParsing.epochSeconds(item["granted_at"]),
                expiresAt: DateParsing.iso8601(item["expires_at"] as? String) ?? DateParsing.epochSeconds(item["expires_at"]),
                title: item["title"] as? String
            )
        }
        let available = credits
            .filter { $0.isAvailable && !$0.isExpired(now: now) }
            .sorted { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }
        let reported = (root["available_count"] as? NSNumber)?.intValue
        return ResetCreditsSnapshot(
            availableCount: available.count,
            reportedAvailableCount: reported,
            items: available,
            fetchedAt: now
        )
    }
}

public actor ResetCreditService: ResetCreditsProviding {
    private let official: OfficialResetCreditsClient
    private let fallback: ResetCreditFallbackProviding?
    private var cache: ResetCreditsSnapshot?
    private var cachedAt: Date?

    public init(official: OfficialResetCreditsClient, fallback: ResetCreditFallbackProviding?) {
        self.official = official
        self.fallback = fallback
    }

    public func creditsSnapshot(now: Date = Date()) async -> ResetCreditsSnapshot? {
        if let cache, let cachedAt, now.timeIntervalSince(cachedAt) < AppConstants.refreshQuotaSeconds {
            return cache
        }
        if let snapshot = try? await official.fetch(now: now) {
            cache = snapshot
            cachedAt = now
            return snapshot
        }
        if let snapshot = await fallback?.fallbackCredits(now: now) {
            cache = snapshot
            cachedAt = now
            return snapshot
        }
        return cache
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift run codexinfo-tests --filter ResetCredit`

Expected: two `PASS` lines and `SUMMARY ran=2 failed=0`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexInfoCore/Support Sources/CodexInfoCore/Models/ResetCreditModels.swift Sources/CodexInfoCore/Services/ResetCreditService.swift Sources/CodexInfoTests/CoreTests.swift
git commit -m "feat: fetch and cache reset cards"
```

---

### Task 6: Session Log Parser and Models

**Files:**
- Create: `Sources/CodexInfoCore/Models/SessionModels.swift`
- Create: `Sources/CodexInfoCore/Sessions/SessionLogParser.swift`
- Modify: `Sources/CodexInfoTests/CoreTests.swift`

**Interfaces:**
- Consumes: `DateParsing`, `RateLimitWindow`, `RateLimitSnapshot`.
- Produces:
  - `SessionEvent` and its associated event structs
  - `SessionLogParser.parse(line:) -> SessionEvent?`
  - `TokenUsage`

- [ ] **Step 1: Add failing parser tests**

Append to `registerCoreTests()`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift run codexinfo-tests --filter SessionLogParser`

Expected: compile failure because the parser and models do not exist.

- [ ] **Step 3: Implement the models and parser**

`Sources/CodexInfoCore/Models/SessionModels.swift`:

```swift
import Foundation

public struct TokenUsage: Codable, Equatable, Sendable {
    public let inputTokens: Int
    public let cachedInputTokens: Int
    public let cacheWriteInputTokens: Int
    public let outputTokens: Int
    public let reasoningOutputTokens: Int
    public let totalTokens: Int

    public init(inputTokens: Int, cachedInputTokens: Int, cacheWriteInputTokens: Int, outputTokens: Int, reasoningOutputTokens: Int, totalTokens: Int) {
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheWriteInputTokens = cacheWriteInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
    }

    public static let zero = TokenUsage(inputTokens: 0, cachedInputTokens: 0, cacheWriteInputTokens: 0, outputTokens: 0, reasoningOutputTokens: 0, totalTokens: 0)
}

public struct TokenUsageRecordEvent: Equatable, Sendable {
    public let timestamp: Date?
    public let turnId: String
    public let responseId: String
    public let usage: TokenUsage
    public let turnTokenUsage: TokenUsage
    public let threadTokenUsage: TokenUsage
}

public struct TaskStartedEvent: Equatable, Sendable {
    public let turnId: String
    public let startedAt: Date?
}

public struct TaskCompleteEvent: Equatable, Sendable {
    public let turnId: String
    public let durationMs: Double?
    public let ttftMs: Double?
    public let completedAt: Date?
}

public struct TokenCountEvent: Equatable, Sendable {
    public let lastUsage: TokenUsage?
    public let totalUsage: TokenUsage?
    public let modelContextWindow: Int?
    public let rateLimits: RateLimitSnapshot?
}

public struct ItemCompletedEvent: Equatable, Sendable {
    public let turnId: String
    public let itemType: String
    public let startedAtMs: Double?
    public let completedAtMs: Double?
}

public struct TurnContextEvent: Equatable, Sendable {
    public let turnId: String
    public let model: String?
    public let reasoningEffort: String?
    public let compHash: String?
}

public struct ThreadSettingsEvent: Equatable, Sendable {
    public let model: String?
    public let reasoningEffort: String?
    public let serviceTier: String?
    public let provider: String?
}

public enum SessionEvent: Equatable, Sendable {
    case tokenUsageRecord(TokenUsageRecordEvent)
    case taskStarted(TaskStartedEvent)
    case taskComplete(TaskCompleteEvent)
    case tokenCount(TokenCountEvent)
    case itemCompleted(ItemCompletedEvent)
    case turnContext(TurnContextEvent)
    case threadSettings(ThreadSettingsEvent)
    case compacted
}
```

`Sources/CodexInfoCore/Sessions/SessionLogParser.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift run codexinfo-tests --filter SessionLogParser`

Expected: three `PASS` lines and `SUMMARY ran=3 failed=0`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexInfoCore/Models/SessionModels.swift Sources/CodexInfoCore/Sessions/SessionLogParser.swift Sources/CodexInfoTests/CoreTests.swift
git commit -m "feat: parse codex session events"
```

---

### Task 7: Turn Aggregation and Output Rate

**Files:**
- Create: `Sources/CodexInfoCore/Sessions/TurnAggregator.swift`
- Create: `Sources/CodexInfoCore/Analytics/OutputRateCalculator.swift`
- Modify: `Sources/CodexInfoTests/CoreTests.swift`

**Interfaces:**
- Consumes: `SessionEvent`, `TokenUsage`, `ThreadSettingsEvent`.
- Produces:
  - `TurnMetrics`, `SessionAggregate`
  - `TurnAggregator.aggregate(_:) -> SessionAggregate`
  - `TurnRate`, `OutputRateCalculator.rate(for:)`, `.medianRate(_:)`

- [ ] **Step 1: Add failing aggregator and rate tests**

Append to `registerCoreTests()`:

```swift
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
        context.expectEqual(OutputRateCalculator.medianRate([
            TurnMetrics(turnId: "a", model: nil, reasoningEffort: nil, serviceTier: nil, provider: nil, compHash: nil, startedAt: nil, completedAt: nil, durationMs: 1, ttftMs: 0, inputTokens: 0, cachedInputTokens: 0, outputTokens: 10, reasoningOutputTokens: 0, modelItemMs: 1_000, toolMs: 0, toolCallCount: 0, isCompleted: true),
            TurnMetrics(turnId: "b", model: nil, reasoningEffort: nil, serviceTier: nil, provider: nil, compHash: nil, startedAt: nil, completedAt: nil, durationMs: 1, ttftMs: 0, inputTokens: 0, cachedInputTokens: 0, outputTokens: 20, reasoningOutputTokens: 0, modelItemMs: 1_000, toolMs: 0, toolCallCount: 0, isCompleted: true),
            TurnMetrics(turnId: "c", model: nil, reasoningEffort: nil, serviceTier: nil, provider: nil, compHash: nil, startedAt: nil, completedAt: nil, durationMs: 1, ttftMs: 0, inputTokens: 0, cachedInputTokens: 0, outputTokens: 30, reasoningOutputTokens: 0, modelItemMs: 1_000, toolMs: 0, toolCallCount: 0, isCompleted: true)
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift run codexinfo-tests --filter OutputRate`

Expected: compile failure because `TurnMetrics`, `TurnAggregator`, and `OutputRateCalculator` do not exist. The aggregator test also fails to compile.

- [ ] **Step 3: Implement the aggregator and calculator**

`Sources/CodexInfoCore/Sessions/TurnAggregator.swift`:

```swift
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
```

`Sources/CodexInfoCore/Analytics/OutputRateCalculator.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift run codexinfo-tests --filter OutputRate`

Expected: two `PASS` lines and `SUMMARY ran=2 failed=0`. The aggregator test starts with "TurnAggregator" and will not match the filter; run it separately:

Run: `swift run codexinfo-tests --filter TurnAggregator`

Expected: one `PASS` line.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexInfoCore/Sessions/TurnAggregator.swift Sources/CodexInfoCore/Analytics/OutputRateCalculator.swift Sources/CodexInfoTests/CoreTests.swift
git commit -m "feat: aggregate turns and compute output tok/s"
```

### Task 8: App-Server Quota Fallback

**Files:**
- Create: `Sources/CodexInfoCore/Services/CodexAppServerClient.swift`
- Modify: `Sources/CodexInfoCore/Models/RateLimitModels.swift`
- Modify: `Sources/CodexInfoTests/CoreTests.swift`

**Interfaces:**
- Consumes: `RateLimitSnapshot`, `RateLimitWindowSelector`, `QuotaSnapshot`.
- Produces:
  - `AppServerTransport` protocol and `ProcessAppServerTransport`
  - `CodexAppServerClient.readRateLimits() async throws -> AppServerRateLimits`
  - `AppServerQuotaFallback.fallbackQuota(now:)`
  - `CompositeQuotaFallback`

- [ ] **Step 1: Add failing app-server fallback tests**

Append to `registerCoreTests()`:

```swift
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
```

Add the fake outside `registerCoreTests`:

```swift
final class FakeAppServerTransport: AppServerTransport, @unchecked Sendable {
    struct Request { let method: String; let params: [String: Any] }
    let result: [String: Any]
    private(set) var requests: [Request] = []

    init(result: [String: Any]) { self.result = result }

    func request(method: String, params: [String: Any]) async throws -> [String: Any] {
        requests.append(Request(method: method, params: params))
        if method == "initialize" { return [:] }
        return result
    }

    func notify(method: String, params: [String: Any]) async throws {}
    func close() {}
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift run codexinfo-tests --filter AppServer`

Expected: compile failure because the transport/client/fallback do not exist.

- [ ] **Step 3: Implement the app-server transport and fallback**

Add to `Sources/CodexInfoCore/Models/RateLimitModels.swift`:

```swift
public enum RateLimitPayloadDecoder {
    public static func snapshot(from object: [String: Any]) -> RateLimitSnapshot? {
        guard object["limit_id"] != nil || object["limitId"] != nil || object["primary"] != nil else { return nil }
        return RateLimitSnapshot(
            limitId: object["limit_id"] as? String ?? object["limitId"] as? String,
            primary: window(object["primary"] as? [String: Any]),
            secondary: window(object["secondary"] as? [String: Any]),
            planType: object["plan_type"] as? String ?? object["planType"] as? String
        )
    }

    public static func snapshotMap(from object: [String: Any]) -> [String: RateLimitSnapshot] {
        var result: [String: RateLimitSnapshot] = [:]
        for (key, value) in object {
            if let dictionary = value as? [String: Any], let snapshot = snapshot(from: dictionary) {
                result[key] = snapshot
            }
        }
        return result
    }

    private static func window(_ object: [String: Any]?) -> RateLimitWindow? {
        guard let object, let used = (object["used_percent"] as? NSNumber)?.doubleValue else { return nil }
        return RateLimitWindow(
            usedPercent: used,
            windowDurationMins: (object["window_minutes"] as? NSNumber)?.doubleValue,
            resetsAt: (object["resets_at"] as? NSNumber)?.intValue
        )
    }
}
```

`Sources/CodexInfoCore/Services/CodexAppServerClient.swift`:

```swift
import Foundation

public protocol AppServerTransport: Sendable {
    func request(method: String, params: [String: Any]) async throws -> [String: Any]
    func notify(method: String, params: [String: Any]) async throws
    func close()
}

public enum AppServerError: Error, Equatable {
    case binaryNotFound
    case notRunning
    case invalidResponse
    case rpc(code: Int, message: String)
    case timeout
}

public struct AppServerRateLimits: Equatable, Sendable {
    public let rateLimits: RateLimitSnapshot?
    public let rateLimitsByLimitID: [String: RateLimitSnapshot]
}

public actor CodexAppServerClient {
    private let transport: AppServerTransport
    private var initialized = false

    public init(transport: AppServerTransport) {
        self.transport = transport
    }

    public func readRateLimits() async throws -> AppServerRateLimits {
        try await ensureInitialized()
        let result = try await transport.request(method: "account/rateLimits/read", params: [:])
        let snapshot = (result["rateLimits"] as? [String: Any]).flatMap(RateLimitPayloadDecoder.snapshot)
        let byID = (result["rateLimitsByLimitId"] as? [String: Any]).map(RateLimitPayloadDecoder.snapshotMap) ?? [:]
        return AppServerRateLimits(rateLimits: snapshot, rateLimitsByLimitID: byID)
    }

    private func ensureInitialized() async throws {
        guard !initialized else { return }
        _ = try await transport.request(method: "initialize", params: [
            "clientInfo": ["name": "CodexInfo", "title": "CodexInfo", "version": AppConstants.version],
            "capabilities": [
                "experimentalApi": false,
                "requestAttestation": false,
                "optOutNotificationMethods": [],
            ],
        ])
        try? await transport.notify(method: "initialized", params: [:])
        initialized = true
    }
}

public struct AppServerQuotaFallback: QuotaFallbackProviding {
    private let client: CodexAppServerClient

    public init(client: CodexAppServerClient) {
        self.client = client
    }

    public func fallbackQuota(now: Date) async -> QuotaSnapshot? {
        guard let result = try? await client.readRateLimits() else { return nil }
        let bucket = RateLimitBucketSelector.select(result.rateLimitsByLimitID) ?? result.rateLimits
        guard let weekly = bucket.flatMap(RateLimitWindowSelector.weekly) else { return nil }
        return QuotaSnapshot(
            planType: bucket?.planType,
            weeklyRemainingPercent: weekly.remainingPercent,
            weeklyResetsAt: weekly.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            source: .appServer,
            fetchedAt: now
        )
    }
}

public struct CompositeQuotaFallback: QuotaFallbackProviding {
    private let providers: [QuotaFallbackProviding]

    public init(_ providers: [QuotaFallbackProviding]) {
        self.providers = providers
    }

    public func fallbackQuota(now: Date) async -> QuotaSnapshot? {
        for provider in providers {
            if let snapshot = await provider.fallbackQuota(now: now) { return snapshot }
        }
        return nil
    }
}

public enum CodexBinaryLocator {
    public static func find(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        if let override = environment["CODEX_CLI_PATH"], fileManager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        let home = fileManager.homeDirectoryForCurrentUser.path
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "\(home)/.codex/packages/standalone/current/bin/codex",
            "\(home)/.local/bin/codex",
        ]
        return candidates.first(where: fileManager.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }
}

public final class ProcessAppServerTransport: AppServerTransport, @unchecked Sendable {
    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private let queue = DispatchQueue(label: "com.laoer.codexinfo.appserver")
    private var buffer = Data()
    private var nextID = 1
    private var closed = false

    public init(binaryURL: URL) throws {
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = binaryURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        self.process = process
        self.input = stdin.fileHandleForWriting
        self.output = stdout.fileHandleForReading
    }

    public func request(method: String, params: [String: Any]) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let id = self.nextID
                    self.nextID += 1
                    let message: [String: Any] = [
                        "jsonrpc": "2.0",
                        "id": id,
                        "method": method,
                        "params": params,
                    ]
                    self.input.write(try JSONSerialization.data(withJSONObject: message) + Data("\n".utf8))
                    while let line = self.readLine() {
                        guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                        guard (object["id"] as? NSNumber)?.intValue == id else { continue }
                        if let error = object["error"] as? [String: Any] {
                            let code = (error["code"] as? NSNumber)?.intValue ?? -32603
                            let text = error["message"] as? String ?? "app-server error"
                            throw AppServerError.rpc(code: code, message: text)
                        }
                        guard let result = object["result"] as? [String: Any] else { throw AppServerError.invalidResponse }
                        continuation.resume(returning: result)
                        return
                    }
                    throw AppServerError.notRunning
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func notify(method: String, params: [String: Any]) async throws {
        let message: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        input.write(try JSONSerialization.data(withJSONObject: message) + Data("\n".utf8))
    }

    public func close() {
        guard !closed else { return }
        closed = true
        input.closeFile()
        output.closeFile()
        if process.isRunning { process.terminate() }
    }

    private func readLine() -> Data? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer = buffer[(newline + 1)...]
                if !line.isEmpty { return Data(line) }
                continue
            }
            let chunk = output.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift run codexinfo-tests --filter AppServer`

Expected: one `PASS` line and `SUMMARY ran=1 failed=0`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexInfoCore/Models/RateLimitModels.swift Sources/CodexInfoCore/Services/CodexAppServerClient.swift Sources/CodexInfoTests/CoreTests.swift
git commit -m "feat: add app-server quota fallback"
```

---

### Task 9: Session Indexer, Repository and Session Quota Fallback

**Files:**
- Create: `Sources/CodexInfoCore/Sessions/SessionIndexer.swift`
- Create: `Sources/CodexInfoCore/Sessions/SessionRepository.swift`
- Modify: `Sources/CodexInfoCore/Models/SessionModels.swift`
- Modify: `Sources/CodexInfoCore/Services/CodexAppServerClient.swift` (add session fallback)
- Modify: `Sources/CodexInfoTests/CoreTests.swift`

**Interfaces:**
- Consumes: `SessionLogParser`, `TurnAggregator`, `OutputRateCalculator`, `SessionEvent`.
- Produces:
  - `SessionIndex`, `SessionIndexer.scan()`
  - `SessionSnapshot`, `SessionRepository.currentSnapshot(now:)`, `.allTurns(now:)`, `.dailyTokens(calendar:)`
  - `SessionQuotaFallback`

- [ ] **Step 1: Add failing session-index tests**

Append to `registerCoreTests()`:

```swift
    test("SessionIndexer picks the newest session and reports context") { context in
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let older = directory.appendingPathComponent("older.jsonl")
        let newer = directory.appendingPathComponent("newer.jsonl")
        let threadSettings = #"{"timestamp":"2026-10-24T02:48:18.321Z","type":"event_msg","payload":{"type":"thread_settings_applied","thread_settings":{"model":"gpt-6.1-sol","model_provider_id":"openai","service_tier":"default","reasoning_effort":"xhigh"}}}"# + "\n"
        let contextLine = #"{"timestamp":"2026-10-24T02:48:23.310Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":80,"cache_write_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120},"total_token_usage":{"input_tokens":100,"cached_input_tokens":80,"cache_write_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120},"model_context_window":475000}}}"# + "\n"
        let newerContent = threadSettings
            + #"{"timestamp":"2026-10-24T02:48:19.000Z","type":"task_started","payload":{"turn_id":"turn-1","started_at":1792810096}}"# + "\n"
            + #"{"timestamp":"2026-10-24T02:48:20.000Z","type":"token_usage_record","payload":{"turn_id":"turn-1","response_id":"resp-1","usage":{"input_tokens":100,"cached_input_tokens":80,"cache_write_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120},"turn_token_usage":{"input_tokens":100,"cached_input_tokens":80,"cache_write_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120},"thread_token_usage":{"input_tokens":100,"cached_input_tokens":80,"cache_write_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120}}}"# + "\n"
            + contextLine
        try older.write(to: older, atomically: true, encoding: .utf8)
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
        context.expectEqual(snapshot.label, "当前会话")
        context.expectEqual(snapshot.contextTokens, 120)
        context.expectEqual(snapshot.totalTokens, 120)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift run codexinfo-tests --filter SessionIndexer`

Expected: compile failure because the indexer/repository do not exist.

- [ ] **Step 3: Implement the indexer and repository**

Add to `Sources/CodexInfoCore/Models/SessionModels.swift`:

```swift
public struct SessionIndex: Codable, Equatable, Sendable {
    public let path: String
    public let modifiedAt: Date
    public let turns: [TurnMetrics]
    public let isActive: Bool
    public let model: String?
    public let reasoningEffort: String?
    public let serviceTier: String?
    public let contextTokens: Int?
    public let contextWindow: Int?
    public let lastRateLimits: RateLimitSnapshot?
    public let selectedModel: String?
    public let selectedEffort: String?
    public let selectedServiceTier: String?
    public let routeMismatch: Bool
}

public struct SessionSnapshot: Codable, Equatable, Sendable {
    public let isActive: Bool
    public let label: String
    public let model: String?
    public let effort: String?
    public let serviceTier: String?
    public let contextTokens: Int?
    public let contextWindow: Int?
    public let totalTokens: Int?
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cachedInputTokens: Int?
    public let reasoningOutputTokens: Int?
    public let outputTokensPerSecond: Double?
    public let medianOutputTokensPerSecond: Double?
    public let ttftMs: Double?
    public let turnCount: Int
    public let routeMismatch: Bool
}

extension TokenCountEvent: Codable {}
```

`Sources/CodexInfoCore/Sessions/SessionIndexer.swift`:

```swift
import Foundation

public actor SessionIndexer {
    private struct FileState {
        var offset: UInt64
        var pending: Data
        var events: [SessionEvent]
        var modifiedAt: Date
        var size: UInt64
    }

    private struct CachedIndex: Codable {
        let size: UInt64
        let modifiedAt: Date
        let index: SessionIndex
    }

    private let rootURL: URL
    private let cacheURL: URL?
    private var states: [String: FileState] = [:]
    private var cachedIndexes: [String: CachedIndex] = [:]

    public init(rootURL: URL, cacheURL: URL? = nil) {
        self.rootURL = rootURL
        self.cacheURL = cacheURL
        if let cacheURL, let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode([String: CachedIndex].self, from: data) {
            self.cachedIndexes = decoded
        }
    }

    public func scan() async -> [SessionIndex] {
        let files = (try? FileManager.default.subpathsOfDirectory(atPath: rootURL.path))?
            .filter { $0.hasSuffix(".jsonl") } ?? []
        var results: [SessionIndex] = []
        for relative in files {
            let url = rootURL.appendingPathComponent(relative)
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize, let modifiedAt = values.contentModificationDate else { continue }
            let path = url.path
            if states[path] == nil,
               let cached = cachedIndexes[path],
               cached.size == UInt64(size),
               cached.modifiedAt == modifiedAt {
                results.append(cached.index)
                continue
            }
            var state = states[path] ?? FileState(offset: 0, pending: Data(), events: [], modifiedAt: .distantPast, size: 0)
            if UInt64(size) < state.offset {
                state = FileState(offset: 0, pending: Data(), events: [], modifiedAt: .distantPast, size: 0)
            }
            if UInt64(size) > state.offset || state.events.isEmpty {
                let data = read(from: url, offset: state.offset)
                var combined = state.pending + data
                let lines = combined.split(separator: 0x0A, omittingEmptySubsequences: false)
                var remaining = Data()
                if let last = lines.last, !last.isEmpty {
                    remaining = Data(last)
                    combined = Data(combined.dropLast(last.count))
                }
                for line in combined.split(separator: 0x0A) where !line.isEmpty {
                    if let event = SessionLogParser.parse(line: Data(line)) {
                        state.events.append(event)
                    }
                }
                state.pending = remaining
                state.offset = UInt64(size)
            }
            state.size = UInt64(size)
            state.modifiedAt = modifiedAt
            states[path] = state

            let aggregate = TurnAggregator.aggregate(state.events)
            var activeTurn: String?
            for event in state.events {
                switch event {
                case .taskStarted(let value): activeTurn = value.turnId
                case .taskComplete(let value): if activeTurn == value.turnId { activeTurn = nil }
                default: break
                }
            }
            let settings = state.events.compactMap { event -> ThreadSettingsEvent? in
                if case .threadSettings(let value) = event { return value }
                return nil
            }.last
            let latestTurn = aggregate.turns.last
            let lastContext = aggregate.lastTokenCount
            let modelMismatch = latestTurn?.model != nil && settings?.model != nil && latestTurn?.model != settings?.model
            let effortMismatch = latestTurn?.reasoningEffort != nil && settings?.reasoningEffort != nil && latestTurn?.reasoningEffort != settings?.reasoningEffort
            let routeMismatch = modelMismatch || effortMismatch
            let index = SessionIndex(
                path: path,
                modifiedAt: modifiedAt,
                turns: aggregate.turns,
                isActive: activeTurn != nil,
                model: latestTurn?.model ?? settings?.model,
                reasoningEffort: latestTurn?.reasoningEffort ?? settings?.reasoningEffort,
                serviceTier: settings?.serviceTier,
                contextTokens: lastContext?.lastUsage?.totalTokens,
                contextWindow: lastContext?.modelContextWindow,
                lastRateLimits: lastContext?.rateLimits,
                selectedModel: settings?.model,
                selectedEffort: settings?.reasoningEffort,
                selectedServiceTier: settings?.serviceTier,
                routeMismatch: routeMismatch
            )
            results.append(index)
            cachedIndexes[path] = CachedIndex(size: UInt64(size), modifiedAt: modifiedAt, index: index)
        }
        if let cacheURL, let data = try? JSONEncoder().encode(cachedIndexes) {
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheURL, options: .atomic)
        }
        return results.sorted { $0.modifiedAt < $1.modifiedAt }
    }

    private func read(from url: URL, offset: UInt64) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        return (try? handle.readToEnd()) ?? Data()
    }
}
```

`Sources/CodexInfoCore/Sessions/SessionRepository.swift`:

```swift
import Foundation

public protocol SessionSnapshotProviding: Sendable {
    func currentSnapshot(now: Date) async -> SessionSnapshot?
    func allTurns(now: Date) async -> [TurnMetrics]
}

public actor SessionRepository: SessionSnapshotProviding {
    private let indexer: SessionIndexer
    private var cache: [SessionIndex] = []

    public init(indexer: SessionIndexer) {
        self.indexer = indexer
    }

    public func currentSnapshot(now: Date = Date()) async -> SessionSnapshot? {
        cache = await indexer.scan()
        guard let latest = cache.max(by: { $0.modifiedAt < $1.modifiedAt }) else { return nil }
        let lastTurn = latest.turns.last
        let rate = lastTurn.flatMap(OutputRateCalculator.rate)
        let sameModel = latest.turns.filter {
            $0.model == latest.model && $0.reasoningEffort == latest.reasoningEffort
        }
        let median = OutputRateCalculator.medianRate(sameModel)
        let totalInput = latest.turns.reduce(0) { $0 + $1.inputTokens }
        let totalOutput = latest.turns.reduce(0) { $0 + $1.outputTokens }
        let totalCached = latest.turns.reduce(0) { $0 + $1.cachedInputTokens }
        let totalReasoning = latest.turns.reduce(0) { $0 + $1.reasoningOutputTokens }
        return SessionSnapshot(
            isActive: latest.isActive,
            label: latest.isActive ? "当前会话" : "最近会话",
            model: latest.model,
            effort: latest.reasoningEffort,
            serviceTier: latest.serviceTier,
            contextTokens: latest.contextTokens,
            contextWindow: latest.contextWindow,
            totalTokens: totalInput + totalOutput,
            inputTokens: totalInput,
            outputTokens: totalOutput,
            cachedInputTokens: totalCached,
            reasoningOutputTokens: totalReasoning,
            outputTokensPerSecond: rate?.tokensPerSecond,
            medianOutputTokensPerSecond: median,
            ttftMs: lastTurn?.ttftMs,
            turnCount: latest.turns.count,
            routeMismatch: latest.routeMismatch
        )
    }

    public func allTurns(now: Date = Date()) async -> [TurnMetrics] {
        cache = await indexer.scan()
        return cache.flatMap(\.turns)
    }

    public func dailyTokens(calendar: Calendar = .current) async -> [Date: Int] {
        let turns = await allTurns()
        var result: [Date: Int] = [:]
        for turn in turns {
            guard let date = turn.completedAt else { continue }
            let day = calendar.startOfDay(for: date)
            result[day, default: 0] += turn.inputTokens + turn.outputTokens
        }
        return result
    }
}
```

Add `latestRateLimits()` to `SessionRepository`:

```swift
    public func latestRateLimits() async -> RateLimitSnapshot? {
        cache = await indexer.scan()
        return cache.max(by: { $0.modifiedAt < $1.modifiedAt })?.lastRateLimits
    }
```

Add `SessionQuotaFallback` to `CodexAppServerClient.swift`:

```swift
public struct SessionQuotaFallback: QuotaFallbackProviding {
    private let repository: SessionRepository

    public init(repository: SessionRepository) {
        self.repository = repository
    }

    public func fallbackQuota(now: Date) async -> QuotaSnapshot? {
        guard let limits = await repository.latestRateLimits(),
              let weekly = RateLimitWindowSelector.weekly(from: limits) else { return nil }
        return QuotaSnapshot(
            planType: limits.planType,
            weeklyRemainingPercent: weekly.remainingPercent,
            weeklyResetsAt: weekly.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            source: .session,
            fetchedAt: now
        )
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift run codexinfo-tests --filter SessionIndexer`

Expected: one `PASS` line and `SUMMARY ran=1 failed=0`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexInfoCore/Models/SessionModels.swift Sources/CodexInfoCore/Sessions Sources/CodexInfoCore/Services/CodexAppServerClient.swift Sources/CodexInfoTests/CoreTests.swift
git commit -m "feat: index sessions and expose current-session metrics"
```

---

### Task 10: Account Usage Service

**Files:**
- Create: `Sources/CodexInfoCore/Models/AccountModels.swift`
- Create: `Sources/CodexInfoCore/Services/AccountUsageService.swift`
- Modify: `Sources/CodexInfoCore/Networking/OfficialUsageClient.swift`
- Modify: `Sources/CodexInfoTests/CoreTests.swift`

**Interfaces:**
- Consumes: `SessionRepository.dailyTokens(calendar:)`, `OfficialUsageClient`.
- Produces:
  - `AccountSnapshot`, `AccountUsageService.accountSnapshot(now:)`
  - `OfficialUsageClient.fetchDailyTokenUsage(start:end:calendar:)`

- [ ] **Step 1: Add failing account tests**

Append to `registerCoreTests()`:

```swift
    test("AccountUsageService uses official today total and local cumulative") { context in
        let today = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        let http = MockHTTPClient(response: HTTPResponse(
            data: #"{"days":[{"date":"2026-10-24","total_tokens":1234}]}"#.data(using: .utf8)!,
            statusCode: 200
        ))
        let official = OfficialUsageClient(http: http, credentials: StubCredentials(token: "tok_test"), baseURL: URL(string: "https://chatgpt.com/backend-api")!)
        let local = StubLocalAccount(today: 100, total: 999)
        let service = AccountUsageService(official: official, sessions: local)
        let snapshot = await service.accountSnapshot(now: today)
        context.expectEqual(snapshot?.todayTokens, 1234)
        context.expectEqual(snapshot?.totalTokens, 999)
    }

    test("AccountUsageService falls back to local totals") { context in
        let today = DateParsing.iso8601("2026-10-24T12:00:00Z")!
        let http = MockHTTPClient(error: HTTPError.status(500))
        let official = OfficialUsageClient(http: http, credentials: StubCredentials(token: "tok_test"), baseURL: URL(string: "https://chatgpt.com/backend-api")!)
        let local = StubLocalAccount(today: 100, total: 999)
        let service = AccountUsageService(official: official, sessions: local)
        let snapshot = await service.accountSnapshot(now: today)
        context.expectEqual(snapshot?.todayTokens, 100)
        context.expectEqual(snapshot?.totalTokens, 999)
        context.expectEqual(snapshot?.source, "local")
    }
```

Add the stub outside:

```swift
struct StubLocalAccount: AccountTotalsProviding {
    let today: Int
    let total: Int
    func accountTotals(now: Date, calendar: Calendar) async -> (today: Int, total: Int) {
        (today, total)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift run codexinfo-tests --filter AccountUsage`

Expected: compile failure because the service and protocol do not exist.

- [ ] **Step 3: Implement account models and service**

`Sources/CodexInfoCore/Models/AccountModels.swift`:

```swift
import Foundation

public struct AccountSnapshot: Codable, Equatable, Sendable {
    public let todayTokens: Int?
    public let totalTokens: Int?
    public let source: String
    public let updatedAt: Date

    public init(todayTokens: Int?, totalTokens: Int?, source: String, updatedAt: Date) {
        self.todayTokens = todayTokens
        self.totalTokens = totalTokens
        self.source = source
        self.updatedAt = updatedAt
    }
}
```

`Sources/CodexInfoCore/Services/AccountUsageService.swift`:

```swift
import Foundation

public protocol AccountTotalsProviding: Sendable {
    func accountTotals(now: Date, calendar: Calendar) async -> (today: Int, total: Int)
}

public actor AccountUsageService {
    private let official: OfficialUsageClient
    private let sessions: AccountTotalsProviding
    private let calendar: Calendar
    private var cache: AccountSnapshot?
    private var cachedAt: Date?

    public init(official: OfficialUsageClient, sessions: AccountTotalsProviding, calendar: Calendar = .current) {
        self.official = official
        self.sessions = sessions
        self.calendar = calendar
    }

    public func accountSnapshot(now: Date = Date()) async -> AccountSnapshot? {
        if let cache, let cachedAt, now.timeIntervalSince(cachedAt) < AppConstants.refreshAccountSeconds {
            return cache
        }
        let local = await sessions.accountTotals(now: now, calendar: calendar)
        let start = calendar.startOfDay(for: now)
        let officialToday = try? await official.fetchDailyTokenUsage(start: start, end: now, calendar: calendar)
        let snapshot: AccountSnapshot
        if let officialToday {
            snapshot = AccountSnapshot(todayTokens: officialToday, totalTokens: local.total, source: "official+local", updatedAt: now)
        } else {
            snapshot = AccountSnapshot(todayTokens: local.today, totalTokens: local.total, source: "local", updatedAt: now)
        }
        cache = snapshot
        cachedAt = now
        return snapshot
    }
}

extension SessionRepository: AccountTotalsProviding {
    public func accountTotals(now: Date, calendar: Calendar) async -> (today: Int, total: Int) {
        let daily = await dailyTokens(calendar: calendar)
        let today = daily[calendar.startOfDay(for: now)] ?? 0
        let total = daily.values.reduce(0, +)
        return (today, total)
    }
}
```

Add the official daily method to `OfficialUsageClient`:

```swift
    public func fetchDailyTokenUsage(start: Date, end: Date, calendar: Calendar = .current) async throws -> Int {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        var components = URLComponents(url: baseURL.appendingPathComponent("/wham/usage/daily-token-usage-breakdown"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "start_date", value: formatter.string(from: start)),
            URLQueryItem(name: "end_date", value: formatter.string(from: end)),
            URLQueryItem(name: "group_by", value: "day"),
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(try credentials.load().accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1", forHTTPHeaderField: "x-openai-codex-usage-categories")
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
        let response = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else { throw OfficialUsageError.httpStatus(response.statusCode) }
        guard let root = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            throw OfficialUsageError.invalidPayload
        }
        let rows = (root["days"] as? [[String: Any]])
            ?? (root["data"] as? [[String: Any]])
            ?? (root["breakdown"] as? [[String: Any]])
            ?? []
        let values = rows.compactMap { row -> Int? in
            (row["total_tokens"] as? NSNumber)?.intValue
                ?? (row["tokens"] as? NSNumber)?.intValue
                ?? (row["total"] as? NSNumber)?.intValue
        }
        if !values.isEmpty { return values.reduce(0, +) }
        return (root["total_tokens"] as? NSNumber)?.intValue ?? 0
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift run codexinfo-tests --filter AccountUsage`

Expected: two `PASS` lines and `SUMMARY ran=2 failed=0`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexInfoCore/Models/AccountModels.swift Sources/CodexInfoCore/Services/AccountUsageService.swift Sources/CodexInfoCore/Networking/OfficialUsageClient.swift Sources/CodexInfoTests/CoreTests.swift
git commit -m "feat: aggregate account token usage"
```

### Task 11: Local Baseline and Degradation Verdict

**Files:**
- Create: `Sources/CodexInfoCore/Models/HealthModels.swift`
- Create: `Sources/CodexInfoCore/Analytics/BaselineBuilder.swift`
- Create: `Sources/CodexInfoCore/Analytics/DegradationAnalyzer.swift`
- Modify: `Sources/CodexInfoTests/CoreTests.swift`

**Interfaces:**
- Consumes: `TurnMetrics`, `OutputRateCalculator`.
- Produces:
  - `HealthStatus`, `HealthSignal`, `HealthSnapshot`
  - `HealthThresholds.standard/.conservative`
  - `BaselineBuilder.build(...)`
  - `DegradationAnalyzer.analyze(baselineTurns:currentTurns:routeMismatch:now:windowDays:thresholds:)`

- [ ] **Step 1: Add failing verdict tests**

Append to `registerCoreTests()`:

```swift
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
```

Add the helper outside `registerCoreTests`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift run codexinfo-tests --filter Degradation`

Expected: compile failure because the analyzer and models do not exist.

- [ ] **Step 3: Implement the health models, baseline and analyzer**

`Sources/CodexInfoCore/Models/HealthModels.swift`:

```swift
import Foundation

public enum HealthStatus: String, Codable, Equatable, Sendable {
    case normal
    case suspected
    case degraded
    case insufficient
}

public enum HealthSignalID: String, Codable, Equatable, Sendable {
    case outputRate
    case ttft
    case reasoningShare
    case toolDensity
    case route
}

public struct HealthSignal: Codable, Equatable, Sendable {
    public let id: HealthSignalID
    public let label: String
    public let current: Double
    public let baseline: Double
    public let flagged: Bool
    public let detail: String
}

public struct HealthSnapshot: Codable, Equatable, Sendable {
    public let status: HealthStatus
    public let baselineWindowDays: Int
    public let sampleTurns: Int
    public let model: String?
    public let effort: String?
    public let signals: [HealthSignal]
    public let disclaimer: String

    public static let empty = HealthSnapshot(
        status: .insufficient,
        baselineWindowDays: 7,
        sampleTurns: 0,
        model: nil,
        effort: nil,
        signals: [],
        disclaimer: "基于本机基线，不代表官方结论"
    )
}

public struct HealthThresholds: Equatable, Sendable {
    public let rateRatio: Double
    public let ttftRatio: Double
    public let ttftDeltaMs: Double
    public let reasoningRatio: Double
    public let toolDensityRatio: Double

    public static let standard = HealthThresholds(
        rateRatio: 0.7, ttftRatio: 2.0, ttftDeltaMs: 2_000,
        reasoningRatio: 0.5, toolDensityRatio: 0.6
    )
    public static let conservative = HealthThresholds(
        rateRatio: 0.6, ttftRatio: 3.0, ttftDeltaMs: 3_000,
        reasoningRatio: 0.5, toolDensityRatio: 0.6
    )
}
```

`Sources/CodexInfoCore/Analytics/BaselineBuilder.swift`:

```swift
import Foundation

public struct BaselineStats: Equatable, Sendable {
    public let turns: [TurnMetrics]
    public let medians: [HealthSignalID: Double]
    public let mads: [HealthSignalID: Double]
    public let iqrs: [HealthSignalID: Double]
    public let model: String?
    public let effort: String?
    public let serviceTier: String?
}

public enum BaselineBuilder {
    public static func build(
        from turns: [TurnMetrics],
        now: Date,
        windowDays: Int = 7,
        maxTurns: Int = 30,
        minTurns: Int = 8,
        model: String? = nil,
        effort: String? = nil,
        serviceTier: String? = nil
    ) -> BaselineStats? {
        let start = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let eligible = turns
            .filter { $0.isCompleted }
            .filter { ($0.completedAt ?? .distantPast) >= start }
            .filter { model == nil || $0.model == model }
            .filter { effort == nil || $0.reasoningEffort == effort }
            .filter { serviceTier == nil || $0.serviceTier == serviceTier }
            .suffix(maxTurns)
        guard eligible.count >= minTurns else { return nil }

        var medians: [HealthSignalID: Double] = [:]
        var mads: [HealthSignalID: Double] = [:]
        var iqrs: [HealthSignalID: Double] = [:]
        for metric in [HealthSignalID.outputRate, .ttft, .reasoningShare, .toolDensity] {
            let values = eligible.compactMap { value(for: metric, turn: $0) }.sorted()
            guard !values.isEmpty else { continue }
            let median = median(values)
            let deviations = values.map { abs($0 - median) }.sorted()
            medians[metric] = median
            mads[metric] = median(deviations)
            let q1 = quartile(values, fraction: 0.25)
            let q3 = quartile(values, fraction: 0.75)
            iqrs[metric] = q3 - q1
        }
        return BaselineStats(
            turns: Array(eligible),
            medians: medians,
            mads: mads,
            iqrs: iqrs,
            model: eligible.last?.model,
            effort: eligible.last?.reasoningEffort,
            serviceTier: eligible.last?.serviceTier
        )
    }

    public static func value(for metric: HealthSignalID, turn: TurnMetrics) -> Double? {
        switch metric {
        case .outputRate:
            return OutputRateCalculator.rate(for: turn)?.tokensPerSecond
        case .ttft:
            return turn.ttftMs
        case .reasoningShare:
            return OutputRateCalculator.rate(for: turn)?.reasoningShare
        case .toolDensity:
            return OutputRateCalculator.rate(for: turn)?.toolDensity
        case .route:
            return nil
        }
    }

    public static func quartile(_ values: [Double], fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = (Double(sorted.count) - 1) * fraction
        let lower = Int(floor(position))
        let upper = Int(ceil(position))
        if lower == upper { return sorted[lower] }
        let weight = position - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    public static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
```

`Sources/CodexInfoCore/Analytics/DegradationAnalyzer.swift`:

```swift
import Foundation

public enum DegradationAnalyzer {
    public static func analyze(
        baselineTurns: [TurnMetrics],
        currentTurns: [TurnMetrics],
        routeMismatch: Bool,
        now: Date,
        windowDays: Int = 7,
        minimumTurns: Int = 8,
        thresholds: HealthThresholds = .standard
    ) -> HealthSnapshot {
        let latest = currentTurns.filter(\.isCompleted).last
        guard let latest,
              let baseline = BaselineBuilder.build(
                from: baselineTurns,
                now: now,
                windowDays: windowDays,
                minTurns: minimumTurns,
                model: latest.model,
                effort: latest.reasoningEffort,
                serviceTier: latest.serviceTier
              )
        else {
            return HealthSnapshot(
                status: .insufficient,
                baselineWindowDays: windowDays,
                sampleTurns: baselineTurns.filter(\.isCompleted).count,
                model: latest?.model,
                effort: latest?.reasoningEffort,
                signals: [],
                disclaimer: "基于本机近 \(windowDays) 天基线，不代表官方结论"
            )
        }

        let recent = Array(currentTurns.filter(\.isCompleted).suffix(3))
        guard !recent.isEmpty else {
            return HealthSnapshot(
                status: .insufficient, baselineWindowDays: windowDays,
                sampleTurns: baseline.turns.count, model: baseline.model, effort: baseline.effort,
                signals: [], disclaimer: "24 小时内没有已完成轮次"
            )
        }

        var signals: [HealthSignal] = []
        var performanceFlags = 0

        func addSignal(_ id: HealthSignalID, label: String, current: Double?, baselineValue: Double?, flagged: Bool, detail: String) {
            guard let current, let baselineValue else { return }
            signals.append(HealthSignal(id: id, label: label, current: current, baseline: baselineValue, flagged: flagged, detail: detail))
            if flagged { performanceFlags += 1 }
        }

        let currentValues = Dictionary(uniqueKeysWithValues: [HealthSignalID.outputRate, .ttft, .reasoningShare, .toolDensity].compactMap { metric in
            let values = recent.compactMap { BaselineBuilder.value(for: metric, turn: $0) }
            guard !values.isEmpty else { return nil }
            return (metric, BaselineBuilder.median(values))
        })
        let baselineMedian = baseline.medians
        let baselineMAD = baseline.mads

        func robustZ(_ value: Double, _ median: Double, _ mad: Double, _ iqr: Double) -> Double {
            let scale = mad > 0 ? mad : (iqr > 0 ? iqr / 1.349 : 0)
            guard scale > 0 else { return 0 }
            return 0.6745 * (value - median) / scale
        }

        if let current = currentValues[.outputRate], let base = baselineMedian[.outputRate] {
            let flagged = current <= base * thresholds.rateRatio
                && robustZ(current, base, baselineMAD[.outputRate] ?? 0, baseline.iqrs[.outputRate] ?? 0) <= -2
            addSignal(.outputRate, label: "输出速率", current: current, baselineValue: base, flagged: flagged, detail: "当前 \(String(format: "%.1f", current)) / 基线 \(String(format: "%.1f", base)) tok/s")
        }
        if let current = currentValues[.ttft], let base = baselineMedian[.ttft] {
            let flagged = (current >= base * thresholds.ttftRatio || current >= base + thresholds.ttftDeltaMs)
                && robustZ(current, base, baselineMAD[.ttft] ?? 0, baseline.iqrs[.ttft] ?? 0) >= 2
            addSignal(.ttft, label: "首 token", current: current, baselineValue: base, flagged: flagged, detail: "当前 \(String(format: "%.0f", current))ms / 基线 \(String(format: "%.0f", base))ms")
        }
        if let current = currentValues[.reasoningShare], let base = baselineMedian[.reasoningShare], base >= 0.05 {
            let flagged = current <= base * thresholds.reasoningRatio
            addSignal(.reasoningShare, label: "推理占比", current: current, baselineValue: base, flagged: flagged, detail: "当前 \(Int(current * 100))% / 基线 \(Int(base * 100))%")
        }
        if let current = currentValues[.toolDensity], let base = baselineMedian[.toolDensity], base >= 0.5 {
            let flagged = current <= base * thresholds.toolDensityRatio
            addSignal(.toolDensity, label: "工具调用密度", current: current, baselineValue: base, flagged: flagged, detail: "当前 \(String(format: "%.2f", current)) / 基线 \(String(format: "%.2f", base))")
        }
        if routeMismatch {
            signals.append(HealthSignal(id: .route, label: "路由不一致", current: 1, baseline: 0, flagged: true, detail: "实际模型/档位与选择不一致"))
        }

        let rawStatus: HealthStatus
        if performanceFlags >= 3 || (routeMismatch && performanceFlags >= 2) {
            rawStatus = .degraded
        } else if performanceFlags >= 2 || (routeMismatch && performanceFlags >= 1) {
            rawStatus = .suspected
        } else {
            rawStatus = .normal
        }
        let status: HealthStatus = (rawStatus == .degraded && recent.count < 3) ? .suspected : rawStatus
        return HealthSnapshot(
            status: status,
            baselineWindowDays: windowDays,
            sampleTurns: baseline.turns.count,
            model: baseline.model,
            effort: baseline.effort,
            signals: signals,
            disclaimer: "基于本机近 \(windowDays) 天基线，不代表官方结论"
        )
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift run codexinfo-tests --filter Degradation`

Expected: four `PASS` lines and `SUMMARY ran=4 failed=0`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexInfoCore/Models/HealthModels.swift Sources/CodexInfoCore/Analytics/BaselineBuilder.swift Sources/CodexInfoCore/Analytics/DegradationAnalyzer.swift Sources/CodexInfoTests/CoreTests.swift
git commit -m "feat: add local model-health baseline and verdict"
```

---

### Task 12: Reset Source Models, CodexRadar Records and OpenAI Status

**Files:**
- Create: `Sources/CodexInfoCore/ResetRadar/ResetSource.swift`
- Create: `Sources/CodexInfoCore/ResetRadar/CodexRadarCurrentSource.swift`
- Create: `Sources/CodexInfoCore/ResetRadar/OpenAIStatusSource.swift`
- Modify: `Sources/CodexInfoTests/CoreTests.swift`

**Interfaces:**
- Consumes: `HTTPClient`, `DateParsing`.
- Produces:
  - `ResetSignal`, `ResetSignalKind`, `ResetSource`
  - `CodexRadarCurrentSource`, `OpenAIStatusSource`

- [ ] **Step 1: Add failing source tests**

Append to `registerCoreTests()`:

```swift
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

    test("OpenAIStatusSource reports service status without claiming a reset") { context in
        let json = #"{"status":{"indicator":"none","description":"All Systems Operational"}}"#
        let http = MockHTTPClient(response: HTTPResponse(data: json.data(using: .utf8)!, statusCode: 200))
        let source = OpenAIStatusSource()
        let signals = try await source.fetch(using: http, now: Date(timeIntervalSince1970: 1_790_000_000))
        context.expectEqual(signals.count, 1)
        context.expectEqual(signals.first?.kind, .status)
        context.expectEqual(signals.first?.verified, false)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift run codexinfo-tests --filter CodexRadarCurrentSource`

Expected: compile failure because the models/sources do not exist.

- [ ] **Step 3: Implement the models and two sources**

`Sources/CodexInfoCore/ResetRadar/ResetSource.swift`:

```swift
import Foundation

public enum ResetSignalKind: String, Codable, Equatable, Sendable {
    case reset
    case banked
    case limits
    case verifying
    case status
    case note
}

public struct ResetSignal: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let sourceId: String
    public let sourceName: String
    public let kind: ResetSignalKind
    public let severity: String?
    public let title: String
    public let summary: String
    public let publishedAt: Date?
    public let url: URL?
    public let verified: Bool
    public let scope: String?
    public let confirmingSources: [String]
}

public protocol ResetSource: Sendable {
    var id: String { get }
    var displayName: String { get }
    func fetch(using http: HTTPClient, now: Date) async throws -> [ResetSignal]
}
```

`Sources/CodexInfoCore/ResetRadar/CodexRadarCurrentSource.swift`:

```swift
import Foundation

public struct CodexRadarCurrentSource: ResetSource {
    public let id = "ai-sentinel-records"
    public let displayName = "AI 哨兵记录"
    public init() {}

    public func fetch(using http: HTTPClient, now: Date) async throws -> [ResetSignal] {
        var request = URLRequest(url: URL(string: "https://codexradar.com/current.json")!)
        request.timeoutInterval = 10
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
        let response = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else { throw HTTPError.status(response.statusCode) }
        guard let root = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else { return [] }
        guard let observation = root["completion_observation"] as? [String: Any] else { return [] }
        let confirmation = observation["confirmation_level"] as? String ?? ""
        let status = observation["status"] as? String ?? ""
        guard status == "completed" || confirmation.contains("confirmed") else { return [] }
        let window = root["window"] as? [String: Any]
        let urlString = observation["announcement_url"] as? String
            ?? window?["source_url"] as? String
        let publishedAt = DateParsing.iso8601(observation["occurred_at"] as? String)
            ?? DateParsing.iso8601(observation["occurred_on"] as? String)
            ?? DateParsing.iso8601(root["monitored_at"] as? String)
        let title = observation["title_zh"] as? String ?? "Codex 重置完成"
        return [ResetSignal(
            id: "\(id):\(title):\(observation["occurred_on"] as? String ?? "")",
            sourceId: id,
            sourceName: displayName,
            kind: .reset,
            severity: confirmation.contains("stationmaster") ? "strong" : nil,
            title: title,
            summary: observation["evidence_zh"] as? String ?? "",
            publishedAt: publishedAt,
            url: urlString.flatMap(URL.init(string:)),
            verified: true,
            scope: window?["scope"] as? String ?? "Codex 用户",
            confirmingSources: [displayName]
        )]
    }
}
```

`Sources/CodexInfoCore/ResetRadar/OpenAIStatusSource.swift`:

```swift
import Foundation

public struct OpenAIStatusSource: ResetSource {
    public let id = "openai-status"
    public let displayName = "官方状态"
    public init() {}

    public func fetch(using http: HTTPClient, now: Date) async throws -> [ResetSignal] {
        var request = URLRequest(url: URL(string: "https://status.openai.com/api/v2/summary.json")!)
        request.timeoutInterval = 10
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
        let response = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else { throw HTTPError.status(response.statusCode) }
        guard let root = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let status = root["status"] as? [String: Any] else { return [] }
        let indicator = status["indicator"] as? String ?? "unknown"
        let description = status["description"] as? String ?? "Unknown"
        return [ResetSignal(
            id: "\(id):\(indicator):\(now.timeIntervalSince1970)",
            sourceId: id,
            sourceName: displayName,
            kind: .status,
            severity: indicator == "none" ? nil : "strong",
            title: "OpenAI 服务状态：\(description)",
            summary: "服务状态指示灯：\(indicator)",
            publishedAt: now,
            url: URL(string: "https://status.openai.com/"),
            verified: false,
            scope: "所有用户",
            confirmingSources: [displayName]
        )]
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift run codexinfo-tests --filter CodexRadarCurrentSource`

Expected: one `PASS` line.

Run: `swift run codexinfo-tests --filter OpenAIStatusSource`

Expected: one `PASS` line.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexInfoCore/ResetRadar/ResetSource.swift Sources/CodexInfoCore/ResetRadar/CodexRadarCurrentSource.swift Sources/CodexInfoCore/ResetRadar/OpenAIStatusSource.swift Sources/CodexInfoTests/CoreTests.swift
git commit -m "feat: normalize reset records and official status"
```

### Task 13: CodexRadar Feed and Codex Resets Adapters

**Files:**
- Create: `Sources/CodexInfoCore/ResetRadar/CodexRadarFeedSource.swift`
- Create: `Sources/CodexInfoCore/ResetRadar/CodexResetsSource.swift`
- Modify: `Sources/CodexInfoTests/CoreTests.swift`

**Interfaces:**
- Consumes: `ResetSource`, `ResetSignal`, `HTTPClient`, `DateParsing`.
- Produces: `CodexRadarFeedSource`, `CodexResetsSource`.

- [ ] **Step 1: Add failing adapter tests**

Append to `registerCoreTests()`:

```swift
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
```

`MockHTTPClient` currently has one response. Extend it in this task:

```swift
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
```

Replace the earlier `MockHTTPClient` definition with this one.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift run codexinfo-tests --filter Codex`

Expected: compile failure because the feed adapters do not exist.

- [ ] **Step 3: Implement the two adapters**

`Sources/CodexInfoCore/ResetRadar/CodexRadarFeedSource.swift`:

```swift
import Foundation

public struct CodexRadarFeedSource: ResetSource {
    public let id = "ai-sentinel-signals"
    public let displayName = "AI 哨兵信号"
    public init() {}

    public func fetch(using http: HTTPClient, now: Date) async throws -> [ResetSignal] {
        var request = URLRequest(url: URL(string: "https://codexradar.com/feed.xml")!)
        request.timeoutInterval = 10
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
        let response = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else { throw HTTPError.status(response.statusCode) }

        let delegate = RSSDelegate()
        let parser = XMLParser(data: response.data)
        parser.delegate = delegate
        guard parser.parse() else { return [] }

        return delegate.items.compactMap { item in
            guard let title = item["title"], !title.isEmpty else { return nil }
            let description = item["description"] ?? ""
            let verified = title.contains("官方权益确认") || description.contains("权益事件已确认")
            let kind: ResetSignalKind = title.contains("预告") || title.contains("窗口") ? .verifying : .reset
            let scope = description
                .split(separator: "\n")
                .first { $0.contains("适用范围") }?
                .split(separator: "：").last
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            let url = item["link"].flatMap(URL.init(string:))
                ?? description
                    .split(separator: "\n")
                    .first { $0.contains("http") }
                    .flatMap { URL(string: String($0).trimmingCharacters(in: .whitespaces)) }
            return ResetSignal(
                id: "\(id):\(item["guid"] ?? title)",
                sourceId: id,
                sourceName: displayName,
                kind: kind,
                severity: nil,
                title: title,
                summary: description.trimmingCharacters(in: .whitespacesAndNewlines),
                publishedAt: DateParsing.rfc822(item["pubDate"]),
                url: url,
                verified: verified,
                scope: scope,
                confirmingSources: [displayName]
            )
        }
    }
}

private final class RSSDelegate: NSObject, XMLParserDelegate {
    var items: [[String: String]] = []
    private var current: [String: String] = [:]
    private var element = ""
    private var buffer = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        element = elementName
        buffer = ""
        if elementName == "item" { current = [:] }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            items.append(current)
        } else if !buffer.isEmpty {
            current[elementName] = buffer
        }
    }
}
```

Add `rfc822` to `DateParsing.swift`:

```swift
    public static func rfc822(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.date(from: string)
    }
```

`Sources/CodexInfoCore/ResetRadar/CodexResetsSource.swift`:

```swift
import Foundation

public struct CodexResetsSource: ResetSource {
    public let id = "codex-resets"
    public let displayName = "Codex Resets"
    public init() {}

    public func fetch(using http: HTTPClient, now: Date) async throws -> [ResetSignal] {
        var feedRequest = URLRequest(url: URL(string: "https://codex-reset.com/api/feed")!)
        feedRequest.timeoutInterval = 10
        feedRequest.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
        let feedResponse = try await http.send(feedRequest)
        guard (200..<300).contains(feedResponse.statusCode) else { throw HTTPError.status(feedResponse.statusCode) }
        guard let root = try JSONSerialization.jsonObject(with: feedResponse.data) as? [String: Any] else { return [] }

        var signals: [ResetSignal] = []
        if let signal = root["signal"] as? [String: Any],
           let summary = signal["summary"] as? String {
            signals.append(ResetSignal(
                id: "\(id):signal:\(signal["tweet_id"] as? String ?? summary)",
                sourceId: id, sourceName: displayName, kind: .verifying, severity: "strong",
                title: summary, summary: summary,
                publishedAt: DateParsing.iso8601(signal["at"] as? String),
                url: (signal["url"] as? String).flatMap(URL.init(string:)),
                verified: false, scope: "Codex 用户", confirmingSources: [displayName]
            ))
        }
        for tweet in root["tweets"] as? [[String: Any]] ?? [] {
            guard (tweet["explicit_reset_claim"] as? Bool) == true,
                  let text = tweet["text"] as? String else { continue }
            let verified = (tweet["reset_verification_status"] as? String) == "confirmed"
            signals.append(ResetSignal(
                id: "\(id):tweet:\(tweet["id"] as? String ?? text)",
                sourceId: id, sourceName: displayName, kind: .reset, severity: verified ? "strong" : nil,
                title: text.components(separatedBy: "\n").first ?? text,
                summary: text,
                publishedAt: DateParsing.iso8601(tweet["at"] as? String),
                url: (tweet["url"] as? String).flatMap(URL.init(string:)),
                verified: verified, scope: "Codex 用户", confirmingSources: [displayName]
            ))
        }

        var statusRequest = URLRequest(url: URL(string: "https://codex-reset.com/api/status")!)
        statusRequest.timeoutInterval = 10
        if let statusResponse = try? await http.send(statusRequest),
           (200..<300).contains(statusResponse.statusCode),
           let status = try? JSONSerialization.jsonObject(with: statusResponse.data) as? [String: Any] {
            let description = status["description"] as? String ?? "Unknown"
            signals.append(ResetSignal(
                id: "\(id):status:\(status["checked_at"] as? String ?? "")",
                sourceId: id, sourceName: displayName, kind: .status,
                severity: status["degraded"] as? Bool == true ? "strong" : nil,
                title: "Codex Resets 服务状态：\(description)",
                summary: description, publishedAt: now,
                url: URL(string: "https://codex-reset.com/"),
                verified: false, scope: "所有用户", confirmingSources: [displayName]
            ))
        }
        return signals
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift run codexinfo-tests --filter CodexRadarFeedSource`

Expected: one `PASS` line.

Run: `swift run codexinfo-tests --filter CodexResetsSource`

Expected: one `PASS` line.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexInfoCore/ResetRadar/CodexRadarFeedSource.swift Sources/CodexInfoCore/ResetRadar/CodexResetsSource.swift Sources/CodexInfoCore/Support/DateParsing.swift Sources/CodexInfoTests/CoreTests.swift
git commit -m "feat: add reset feed adapters"
```

---

### Task 14: Reset Radar Aggregation, Confirmation and Health

**Files:**
- Create: `Sources/CodexInfoCore/Models/ResetRadarModels.swift`
- Create: `Sources/CodexInfoCore/ResetRadar/ResetRadarService.swift`
- Modify: `Sources/CodexInfoTests/CoreTests.swift`

**Interfaces:**
- Consumes: `[ResetSource]`, `HTTPClient`, `ResetSignal`.
- Produces:
  - `SourceState`, `SourceHealth`, `ResetRadarSnapshot`
  - `ResetRadarService.radarSnapshot(now:)`, `.scan(now:)`

- [ ] **Step 1: Add failing aggregation tests**

Append to `registerCoreTests()`:

```swift
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
```

Add fakes outside:

```swift
struct FakeResetSource: ResetSource {
    let id: String
    let displayName: String
    let signals: [ResetSignal]
    func fetch(using http: HTTPClient, now: Date) async throws -> [ResetSignal] { signals }
}

struct FailingResetSource: ResetSource {
    let id: String
    let displayName: String
    func fetch(using http: HTTPClient, now: Date) async throws -> [ResetSignal] { throw HTTPError.status(500) }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift run codexinfo-tests --filter ResetRadarService`

Expected: compile failure because the service and models do not exist.

- [ ] **Step 3: Implement the radar models and service**

`Sources/CodexInfoCore/Models/ResetRadarModels.swift`:

```swift
import Foundation

public enum SourceState: String, Codable, Equatable, Sendable {
    case ok
    case degraded
    case down
}

public struct SourceHealth: Codable, Equatable, Sendable {
    public let sourceId: String
    public let sourceName: String
    public let state: SourceState
    public let lastSuccessAt: Date?
    public let lastError: String?
    public let nextScanAt: Date?
}

public struct ResetRadarSnapshot: Codable, Equatable, Sendable {
    public let sources: [SourceHealth]
    public let latestConfirmed: ResetSignal?
    public let recent: [ResetSignal]
    public let lastScanAt: Date?
    public let nextScanAt: Date?

    public var sourcesAvailable: Int {
        sources.filter { $0.state != .down }.count
    }

    public static let empty = ResetRadarSnapshot(
        sources: [], latestConfirmed: nil, recent: [], lastScanAt: nil, nextScanAt: nil
    )
}
```

`Sources/CodexInfoCore/ResetRadar/ResetRadarService.swift`:

```swift
import Foundation

public actor ResetRadarService {
    private let sources: [ResetSource]
    private let http: HTTPClient
    private let interval: TimeInterval
    private var health: [String: SourceHealth] = [:]
    private var failures: [String: Int] = [:]
    private var blockedUntil: [String: Date] = [:]
    private var signals: [ResetSignal] = []
    private var lastScanAt: Date?
    private var nextScanAt: Date?

    public init(sources: [ResetSource], http: HTTPClient, interval: TimeInterval = AppConstants.refreshSourcesSeconds) {
        self.sources = sources
        self.http = http
        self.interval = interval
    }

    public func radarSnapshot(now: Date = Date()) async -> ResetRadarSnapshot {
        if nextScanAt == nil || now >= (nextScanAt ?? .distantPast) {
            return await scan(now: now)
        }
        return makeSnapshot()
    }

    public func scan(now: Date = Date()) async -> ResetRadarSnapshot {
        var collected: [ResetSignal] = []
        for source in sources {
            if let blocked = blockedUntil[source.id], now < blocked {
                health[source.id] = SourceHealth(
                    sourceId: source.id, sourceName: source.displayName, state: .down,
                    lastSuccessAt: health[source.id]?.lastSuccessAt,
                    lastError: "retry backoff", nextScanAt: blocked
                )
                continue
            }
            do {
                let sourceSignals = try await withTimeout(10) {
                    try await source.fetch(using: self.http, now: now)
                }
                collected.append(contentsOf: sourceSignals)
                failures[source.id] = 0
                blockedUntil[source.id] = nil
                health[source.id] = SourceHealth(
                    sourceId: source.id, sourceName: source.displayName, state: .ok,
                    lastSuccessAt: now, lastError: nil, nextScanAt: now.addingTimeInterval(interval)
                )
            } catch {
                let count = (failures[source.id] ?? 0) + 1
                failures[source.id] = count
                let backoff = [60.0, 120.0, 300.0, 900.0][min(count - 1, 3)]
                let blocked = now.addingTimeInterval(backoff)
                blockedUntil[source.id] = blocked
                health[source.id] = SourceHealth(
                    sourceId: source.id, sourceName: source.displayName, state: .down,
                    lastSuccessAt: health[source.id]?.lastSuccessAt,
                    lastError: String(describing: error), nextScanAt: blocked
                )
            }
        }
        signals = collected
        lastScanAt = now
        nextScanAt = now.addingTimeInterval(interval)
        return makeSnapshot()
    }

    private func makeSnapshot() -> ResetRadarSnapshot {
        let resetSourceNames: Set<String> = ["AI 哨兵记录", "AI 哨兵信号", "Codex Resets"]
        var groups: [ResetSignal] = []
        for signal in signals.sorted(by: { ($0.publishedAt ?? .distantPast) > ($1.publishedAt ?? .distantPast) }) {
            let normalized = signal.title.lowercased().filter { $0.isLetter || $0.isNumber }
            if let index = groups.firstIndex(where: { existing in
                let existingNormalized = existing.title.lowercased().filter { $0.isLetter || $0.isNumber }
                let timeDelta = abs((existing.publishedAt ?? .distantPast).timeIntervalSince(signal.publishedAt ?? .distantPast))
                return existingNormalized == normalized && timeDelta <= 6 * 3600
            }) {
                let existing = groups[index]
                let confirmed = Array(Set(existing.confirmingSources + signal.confirmingSources))
                groups[index] = ResetSignal(
                    id: existing.id, sourceId: existing.sourceId, sourceName: existing.sourceName,
                    kind: existing.kind, severity: existing.severity, title: existing.title,
                    summary: existing.summary, publishedAt: existing.publishedAt, url: existing.url,
                    verified: existing.verified || signal.verified, scope: existing.scope,
                    confirmingSources: confirmed
                )
            } else {
                groups.append(signal)
            }
        }
        let recent = Array(groups.prefix(20))
        let latestConfirmed = recent.first { signal in
            signal.verified && signal.confirmingSources.filter { resetSourceNames.contains($0) }.count >= 2
        }
        return ResetRadarSnapshot(
            sources: health.values.sorted { $0.sourceId < $1.sourceId },
            latestConfirmed: latestConfirmed,
            recent: recent,
            lastScanAt: lastScanAt,
            nextScanAt: nextScanAt
        )
    }

    private func withTimeout<T>(_ seconds: TimeInterval, _ operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw HTTPError.invalidResponse
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift run codexinfo-tests --filter ResetRadarService`

Expected: two `PASS` lines and `SUMMARY ran=2 failed=0`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexInfoCore/Models/ResetRadarModels.swift Sources/CodexInfoCore/ResetRadar/ResetRadarService.swift Sources/CodexInfoTests/CoreTests.swift
git commit -m "feat: aggregate reset signals with source health"
```

---

### Task 15: Snapshot Builder and Store

**Files:**
- Create: `Sources/CodexInfoCore/Models/SnapshotModels.swift`
- Create: `Sources/CodexInfoCore/Services/SnapshotBuilder.swift`
- Create: `Sources/CodexInfoCore/Services/SnapshotStore.swift`
- Modify: `Sources/CodexInfoCore/Services/AccountUsageService.swift`
- Modify: `Sources/CodexInfoCore/ResetRadar/ResetRadarService.swift`
- Modify: `Sources/CodexInfoTests/CoreTests.swift`

**Interfaces:**
- Consumes: all service protocols.
- Produces:
  - `UsageSnapshot`, `Freshness`, `DataState`
  - `SnapshotBuilder.build(now:)`
  - `SnapshotStore.save(_:)`, `.load(maxAge:)`

- [ ] **Step 1: Add failing snapshot tests**

Append to `registerCoreTests()`:

```swift
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
        let stale = try store.load(maxAge: 10, now: Date(timeIntervalSince1970: 1_790_000_100))
        context.expectEqual(stale, nil)
    }
```

Add stubs:

```swift
struct StubQuotaProvider: QuotaSnapshotProviding {
    let snapshot: QuotaSnapshot
    func quotaSnapshot(now: Date) async -> QuotaSnapshot? { snapshot }
}
struct StubCreditsProvider: ResetCreditsProviding {
    let snapshot: ResetCreditsSnapshot
    func creditsSnapshot(now: Date) async -> ResetCreditsSnapshot? { snapshot }
}
struct StubSessionProvider: SessionSnapshotProviding {
    let snapshot: SessionSnapshot
    let turns: [TurnMetrics]
    func currentSnapshot(now: Date) async -> SessionSnapshot? { snapshot }
    func allTurns(now: Date) async -> [TurnMetrics] { turns }
}
struct StubAccountProvider: AccountSnapshotProviding {
    let snapshot: AccountSnapshot
    func accountSnapshot(now: Date) async -> AccountSnapshot? { snapshot }
}
struct StubRadarProvider: ResetRadarProviding {
    let snapshot: ResetRadarSnapshot
    func radarSnapshot(now: Date) async -> ResetRadarSnapshot { snapshot }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift run codexinfo-tests --filter Snapshot`

Expected: compile failure because the snapshot types and builder do not exist.

- [ ] **Step 3: Implement the snapshot models, builder and store**

`Sources/CodexInfoCore/Models/SnapshotModels.swift`:

```swift
import Foundation

public enum DataState: String, Codable, Equatable, Sendable {
    case fresh
    case stale
    case loading
    case error
}

public struct Freshness: Codable, Equatable, Sendable {
    public let quota: DataState
    public let session: DataState
    public let account: DataState
    public let sources: DataState
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let generatedAt: Date
    public let freshness: Freshness
    public let quota: QuotaSnapshot
    public let resetCredits: ResetCreditsSnapshot
    public let session: SessionSnapshot
    public let account: AccountSnapshot
    public let health: HealthSnapshot
    public let resetRadar: ResetRadarSnapshot
}
```

`Sources/CodexInfoCore/Services/SnapshotBuilder.swift`:

```swift
import Foundation

public protocol AccountSnapshotProviding: Sendable {
    func accountSnapshot(now: Date) async -> AccountSnapshot?
}

public protocol ResetRadarProviding: Sendable {
    func radarSnapshot(now: Date) async -> ResetRadarSnapshot
}

extension AccountUsageService: AccountSnapshotProviding {}
extension ResetRadarService: ResetRadarProviding {}

public actor SnapshotBuilder {
    private let quota: QuotaSnapshotProviding
    private let credits: ResetCreditsProviding
    private let sessions: SessionSnapshotProviding
    private let account: AccountSnapshotProviding
    private let radar: ResetRadarProviding

    public init(
        quota: QuotaSnapshotProviding,
        credits: ResetCreditsProviding,
        sessions: SessionSnapshotProviding,
        account: AccountSnapshotProviding,
        radar: ResetRadarProviding
    ) {
        self.quota = quota
        self.credits = credits
        self.sessions = sessions
        self.account = account
        self.radar = radar
    }

    public func build(now: Date = Date(), windowDays: Int = 7, minimumTurns: Int = 8) async -> UsageSnapshot {
        let quotaSnapshot = await quota.quotaSnapshot(now: now) ?? QuotaSnapshot(
            planType: nil, weeklyRemainingPercent: nil, weeklyResetsAt: nil, source: .official, fetchedAt: now
        )
        let creditsSnapshot = await credits.creditsSnapshot(now: now) ?? ResetCreditsSnapshot(
            availableCount: 0, reportedAvailableCount: nil, items: [], fetchedAt: now
        )
        let sessionSnapshot = await sessions.currentSnapshot(now: now)
        let turns = await sessions.allTurns(now: now)
        let accountSnapshot = await account.accountSnapshot(now: now)
        let radarSnapshot = await radar.radarSnapshot(now: now)
        let completed = turns.filter(\.isCompleted)
        let currentCount = min(3, completed.count)
        let currentTurns = Array(completed.suffix(currentCount))
        let baselineTurns = Array(completed.dropLast(currentCount))
        let health = DegradationAnalyzer.analyze(
            baselineTurns: baselineTurns,
            currentTurns: currentTurns,
            routeMismatch: sessionSnapshot?.routeMismatch ?? false,
            now: now,
            windowDays: windowDays,
            minimumTurns: minimumTurns
        )
        func state(_ date: Date?) -> DataState {
            guard let date else { return .error }
            return now.timeIntervalSince(date) > AppConstants.staleSeconds ? .stale : .fresh
        }
        return UsageSnapshot(
            generatedAt: now,
            freshness: Freshness(
                quota: state(quotaSnapshot.fetchedAt),
                session: sessionSnapshot == nil ? .error : .fresh,
                account: state(accountSnapshot?.updatedAt),
                sources: state(radarSnapshot.lastScanAt)
            ),
            quota: quotaSnapshot,
            resetCredits: creditsSnapshot,
            session: sessionSnapshot ?? .empty,
            account: accountSnapshot ?? AccountSnapshot(todayTokens: nil, totalTokens: nil, source: "local", updatedAt: now),
            health: health,
            resetRadar: radarSnapshot
        )
    }
}
```

Add `SessionSnapshot.empty` in `SessionModels.swift`:

```swift
extension SessionSnapshot {
    public static let empty = SessionSnapshot(
        isActive: false, label: "最近会话", model: nil, effort: nil, serviceTier: nil,
        contextTokens: nil, contextWindow: nil, totalTokens: nil, inputTokens: nil,
        outputTokens: nil, cachedInputTokens: nil, reasoningOutputTokens: nil,
        outputTokensPerSecond: nil, medianOutputTokensPerSecond: nil,
        ttftMs: nil, turnCount: 0, routeMismatch: false
    )
}
```

`Sources/CodexInfoCore/Services/SnapshotStore.swift`:

```swift
import Foundation

public struct SnapshotStore: Sendable {
    private let directory: URL
    private let fileURL: URL

    public init(directory: URL) {
        self.directory = directory
        self.fileURL = directory.appendingPathComponent("snapshot.json")
    }

    public func save(_ snapshot: UsageSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    public func load(maxAge: TimeInterval, now: Date = Date()) throws -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(UsageSnapshot.self, from: data)
        guard now.timeIntervalSince(snapshot.generatedAt) <= maxAge else { return nil }
        return snapshot
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift run codexinfo-tests --filter Snapshot`

Expected: two `PASS` lines and `SUMMARY ran=2 failed=0`.

- [ ] **Step 5: Commit**

```bash
git add Sources/CodexInfoCore/Models/SnapshotModels.swift Sources/CodexInfoCore/Services/SnapshotBuilder.swift Sources/CodexInfoCore/Services/SnapshotStore.swift Sources/CodexInfoCore/Services/AccountUsageService.swift Sources/CodexInfoCore/ResetRadar/ResetRadarService.swift Sources/CodexInfoTests/CoreTests.swift
git commit -m "feat: build and persist usage snapshots"
```

### Task 16: Web Panel with Mock Data

**Files:**
- Create: `Web/package.json`
- Create: `Web/pnpm-lock.yaml` (generated by `pnpm install`)
- Create: `Web/vite.config.ts`
- Create: `Web/tsconfig.json`
- Create: `Web/index.html`
- Create: `Web/playwright.config.ts`
- Create: `Web/src/main.tsx`
- Create: `Web/src/App.tsx`
- Create: `Web/src/styles.css`
- Create: `Web/src/format.ts`
- Create: `Web/src/data/types.ts`
- Create: `Web/src/host/types.ts`
- Create: `Web/src/host/detect.ts`
- Create: `Web/src/host/mockHost.ts`
- Create: `Web/src/host/useHost.ts`
- Create: `Web/src/data/mockSnapshot.ts`
- Create: `Web/tests/panel.spec.ts`

**Interfaces:**
- Consumes: mock snapshot JSON.
- Produces:
  - The B-layout panel HTML.
  - `Host` interface and `useHost()` for later native/MCP adapters.

- [ ] **Step 1: Write the failing UI test and scaffold**

`Web/package.json`:

```json
{
  "name": "codexinfo-web",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview --port 4173",
    "test": "playwright test"
  },
  "dependencies": {
    "@modelcontextprotocol/client": "^2.4.0",
    "@modelcontextprotocol/core": "^2.4.0",
    "@modelcontextprotocol/ext-apps": "2.0.3",
    "react": "^19.3.1",
    "react-dom": "^19.3.1",
    "zod": "^4.2.0"
  },
  "devDependencies": {
    "@playwright/test": "^1.64.1",
    "@types/react": "^19.2.2",
    "@types/react-dom": "^19.2.2",
    "@vitejs/plugin-react": "^6.1.2",
    "typescript": "^7.0.2",
    "vite": "^8.3.5",
    "vite-plugin-singlefile": "^2.3.4"
  }
}
```

`Web/playwright.config.ts`:

```ts
import { defineConfig } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  use: { baseURL: "http://127.0.0.1:4173", headless: true },
  webServer: {
    command: "pnpm exec vite --host 127.0.0.1 --port 4173",
    port: 4173,
    reuseExistingServer: true,
  },
});
```

`Web/tests/panel.spec.ts`:

```ts
import { expect, test } from "@playwright/test";

test("panel follows the B layout", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByTestId("panel")).toBeVisible();
  await expect(page.getByTestId("weekly-quota")).toContainText("84%");
  await expect(page.getByTestId("reset-credit")).toContainText("1 张");
  await expect(page.getByTestId("reset-radar")).toContainText("3/4");
  await expect(page.getByTestId("model-health")).toContainText("正常");
  await expect(page.getByTestId("model-health")).toContainText("42.3 tok/s");
  await expect(page.getByTestId("current-session")).toContainText("输出速率");
  await expect(page.getByTestId("account-stats")).toContainText("3.3B");
  const order = await page.locator("[data-section]").evaluateAll((nodes) =>
    nodes.map((node) => node.getAttribute("data-section"))
  );
  expect(order).toEqual([
    "quota", "reset-credit", "reset-radar", "model-health",
    "current-session", "account-stats",
  ]);
});
```

Run: `pnpm --dir Web install && pnpm --dir Web exec playwright install chromium && pnpm --dir Web exec playwright test tests/panel.spec.ts`

Expected: fail because `Web` has no app yet.

- [ ] **Step 2: Create the mock snapshot and data types**

`Web/src/data/mockSnapshot.ts` (import this module; do not fetch it, so the CSP stays `connect-src 'none'`):

```ts
import type { UsageSnapshot } from "./types";

export const mockSnapshot: UsageSnapshot = {
  "generatedAt": "2026-10-24T14:20:39+08:00",
  "freshness": { "quota": "fresh", "session": "fresh", "account": "fresh", "sources": "fresh" },
  "quota": { "planType": "pro", "weeklyRemainingPercent": 84, "weeklyResetsAt": "2026-10-26T11:03:00+08:00", "source": "official", "fetchedAt": "2026-10-24T14:20:39+08:00" },
  "resetCredits": { "availableCount": 1, "reportedAvailableCount": 1, "items": [{ "idSuffix": "123456", "status": "available", "grantedAt": null, "expiresAt": "2026-11-07T07:55:00+08:00", "title": "Full reset" }], "fetchedAt": "2026-10-24T14:20:39+08:00" },
  "session": { "isActive": true, "label": "当前会话", "model": "gpt-6.1-sol", "effort": "xhigh", "serviceTier": "default", "contextTokens": 147000, "contextWindow": 475000, "totalTokens": 1240000, "inputTokens": 1180000, "outputTokens": 58300, "cachedInputTokens": 1020000, "reasoningOutputTokens": 7000, "outputTokensPerSecond": 42.3, "medianOutputTokensPerSecond": 45.1, "ttftMs": 3900, "turnCount": 12, "routeMismatch": false },
  "account": { "todayTokens": 1800000, "totalTokens": 3300000000, "source": "official+local", "updatedAt": "2026-10-24T14:20:39+08:00" },
  "health": { "status": "normal", "baselineWindowDays": 7, "sampleTurns": 12, "model": "gpt-6.1-sol", "effort": "xhigh", "signals": [{ "id": "outputRate", "label": "输出速率", "current": 42.3, "baseline": 45.1, "flagged": false, "detail": "当前 42.3 / 基线 45.1 tok/s" }], "disclaimer": "基于本机近 7 天基线，不代表官方结论" },
  "resetRadar": { "sources": [{ "sourceId": "ai-sentinel-records", "sourceName": "AI 哨兵记录", "state": "ok", "lastSuccessAt": "2026-10-24T14:20:51+08:00", "lastError": null, "nextScanAt": "2026-10-24T14:21:51+08:00" }, { "sourceId": "ai-sentinel-signals", "sourceName": "AI 哨兵信号", "state": "ok", "lastSuccessAt": "2026-10-24T14:20:51+08:00", "lastError": null, "nextScanAt": "2026-10-24T14:21:51+08:00" }, { "sourceId": "codex-resets", "sourceName": "Codex Resets", "state": "ok", "lastSuccessAt": "2026-10-24T14:20:51+08:00", "lastError": null, "nextScanAt": "2026-10-24T14:21:51+08:00" }, { "sourceId": "openai-status", "sourceName": "官方状态", "state": "down", "lastSuccessAt": null, "lastError": "timeout", "nextScanAt": "2026-10-24T14:21:51+08:00" }], "latestConfirmed": { "id": "reset:1", "sourceId": "ai-sentinel-records", "sourceName": "AI 哨兵记录", "kind": "reset", "severity": "strong", "title": "第 13 天额度重置完成", "summary": "覆盖所有付费用户", "publishedAt": "2026-10-18T05:12:00+08:00", "url": "https://codex-reset.com/zh/radar", "verified": true, "scope": "所有付费用户", "confirmingSources": ["AI 哨兵记录", "AI 哨兵信号", "Codex Resets"] }, "recent": [], "lastScanAt": "2026-10-24T14:20:51+08:00", "nextScanAt": "2026-10-24T14:21:51+08:00" }
};
```

`Web/src/data/types.ts`:

```ts
export type DataState = "fresh" | "stale" | "loading" | "error";
export type HealthStatus = "normal" | "suspected" | "degraded" | "insufficient";
export type SourceState = "ok" | "degraded" | "down";

export interface HealthSignal {
  id: string;
  label: string;
  current: number;
  baseline: number;
  flagged: boolean;
  detail: string;
}

export interface ResetSignal {
  id: string;
  sourceId: string;
  sourceName: string;
  kind: string;
  severity?: string | null;
  title: string;
  summary: string;
  publishedAt?: string | null;
  url?: string | null;
  verified: boolean;
  scope?: string | null;
  confirmingSources: string[];
}

export interface UsageSnapshot {
  generatedAt: string;
  freshness: Record<"quota" | "session" | "account" | "sources", DataState>;
  quota: {
    planType?: string | null;
    weeklyRemainingPercent?: number | null;
    weeklyResetsAt?: string | null;
    source: string;
    fetchedAt: string;
  };
  resetCredits: {
    availableCount: number;
    reportedAvailableCount?: number | null;
    items: Array<{ idSuffix: string; status: string; grantedAt?: string | null; expiresAt?: string | null; title?: string | null }>;
    fetchedAt: string;
  };
  session: {
    isActive: boolean;
    label: string;
    model?: string | null;
    effort?: string | null;
    serviceTier?: string | null;
    contextTokens?: number | null;
    contextWindow?: number | null;
    totalTokens?: number | null;
    inputTokens?: number | null;
    outputTokens?: number | null;
    cachedInputTokens?: number | null;
    reasoningOutputTokens?: number | null;
    outputTokensPerSecond?: number | null;
    medianOutputTokensPerSecond?: number | null;
    ttftMs?: number | null;
    turnCount: number;
    routeMismatch: boolean;
  };
  account: {
    todayTokens?: number | null;
    totalTokens?: number | null;
    source: string;
    updatedAt: string;
  };
  health: {
    status: HealthStatus;
    baselineWindowDays: number;
    sampleTurns: number;
    model?: string | null;
    effort?: string | null;
    signals: HealthSignal[];
    disclaimer: string;
  };
  resetRadar: {
    sources: Array<{ sourceId: string; sourceName: string; state: SourceState; lastSuccessAt?: string | null; lastError?: string | null; nextScanAt?: string | null }>;
    latestConfirmed?: ResetSignal | null;
    recent: ResetSignal[];
    lastScanAt?: string | null;
    nextScanAt?: string | null;
  };
}
```

- [ ] **Step 3: Implement the host abstraction, panel and styles**

`Web/src/host/types.ts`:

```ts
import type { UsageSnapshot } from "../data/types";

export interface HostHandlers {
  onSnapshot: (snapshot: UsageSnapshot) => void;
  onError: (message: string) => void;
}

export interface Host {
  mode: "native" | "mcp" | "mock";
  start(handlers: HostHandlers): Promise<void>;
  stop(): void;
  refresh(): void;
  scan(): void;
  openURL(url: string): void;
  openSettings(): void;
  close(): void;
}
```

`Web/src/host/mockHost.ts`:

```ts
import { mockSnapshot } from "../data/mockSnapshot";
import type { Host, HostHandlers } from "./types";

export class MockHost implements Host {
  mode = "mock" as const;
  private handlers?: HostHandlers;

  async start(handlers: HostHandlers) {
    this.handlers = handlers;
    handlers.onSnapshot(mockSnapshot);
  }

  stop() {}
  refresh() {}
  scan() {}
  openURL(url: string) { window.open(url, "_blank", "noopener,noreferrer"); }
  openSettings() {}
  close() {}
}
```

`Web/src/host/detect.ts`:

```ts
import type { Host } from "./types";
import { MockHost } from "./mockHost";

export function detectHost(): Host {
  return new MockHost();
}
```

`Web/src/host/useHost.ts`:

```ts
import { useEffect, useRef, useState } from "react";
import type { UsageSnapshot } from "../data/types";
import { detectHost } from "./detect";
import type { Host } from "./types";

export function useHost() {
  const [snapshot, setSnapshot] = useState<UsageSnapshot | null>(null);
  const [error, setError] = useState<string | null>(null);
  const hostRef = useRef<Host | null>(null);

  useEffect(() => {
    const host = detectHost();
    hostRef.current = host;
    host.start({
      onSnapshot: setSnapshot,
      onError: setError,
    }).catch((reason) => setError(String(reason)));
    return () => host.stop();
  }, []);

  return { snapshot, error, host: hostRef };
}
```

`Web/src/format.ts`:

```ts
export function formatTokens(value?: number | null): string {
  if (value == null) return "—";
  if (value >= 1_000_000_000) return `${(value / 1_000_000_000).toFixed(1)}B`;
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(2)}M`;
  if (value >= 1_000) return `${(value / 1_000).toFixed(1)}k`;
  return String(value);
}

export function formatRate(value?: number | null): string {
  return value == null ? "—" : `${value.toFixed(1)} tok/s`;
}

export function formatDateTime(value?: string | null): string {
  if (!value) return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return date.toLocaleString("zh-CN", { year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit" });
}

export function formatRemaining(value?: string | null, now = Date.now()): string {
  if (!value) return "—";
  const target = new Date(value).getTime();
  if (Number.isNaN(target)) return "—";
  const minutes = Math.max(0, Math.round((target - now) / 60_000));
  if (minutes < 60) return `${minutes} 分钟`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} 小时`;
  return `${Math.floor(hours / 24)} 天 ${hours % 24} 小时`;
}
```

`Web/src/App.tsx`:

```tsx
import { useEffect, useState, type ReactNode } from "react";
import { formatDateTime, formatRate, formatRemaining, formatTokens } from "./format";
import { useHost } from "./host/useHost";
import type { HealthStatus, UsageSnapshot } from "./data/types";

const HEALTH_LABEL: Record<HealthStatus, string> = {
  normal: "正常",
  suspected: "疑似降智",
  degraded: "已降智（本地判定）",
  insufficient: "数据不足",
};

function Section({ id, children }: { id: string; children: ReactNode }) {
  return <section data-section={id} data-testid={id}>{children}</section>;
}

export default function App() {
  const { snapshot, error, host } = useHost();
  const [now, setNow] = useState(Date.now());

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 60_000);
    return () => window.clearInterval(timer);
  }, []);

  if (error) return <main data-testid="panel" className="panel error">加载失败：{error}</main>;
  if (!snapshot) return <main data-testid="panel" className="panel loading">加载中…</main>;
  return <Panel snapshot={snapshot} now={now} host={host} />;
}

function Panel({ snapshot, now, host }: { snapshot: UsageSnapshot; now: number; host: { current: import("./host/types").Host | null } }) {
  const quota = snapshot.quota;
  const credits = snapshot.resetCredits;
  const session = snapshot.session;
  const account = snapshot.account;
  const health = snapshot.health;
  const radar = snapshot.resetRadar;
  const latest = radar.latestConfirmed;
  const [healthOpen, setHealthOpen] = useState(health.status !== "normal");
  const [sourcesOpen, setSourcesOpen] = useState(false);
  useEffect(() => {
    if (health.status !== "normal") setHealthOpen(true);
  }, [health.status]);
  const contextPercent = session.contextWindow && session.contextTokens
    ? Math.round((session.contextTokens / session.contextWindow) * 100)
    : null;

  return (
    <main data-testid="panel" className="panel">
      <header className="header">
        <strong className="title">用量</strong>
        <span className="badge">{quota.planType ?? "pro"}</span>
        <button className="ghost" onClick={() => host.current?.refresh()}>刷新</button>
        <button className="close" onClick={() => host.current?.close()} aria-label="关闭">×</button>
      </header>
      <div className="body">
        <Section id="quota">
          <div className="row"><span>周额度</span><strong data-testid="weekly-quota">剩余 {quota.weeklyRemainingPercent ?? "—"}%</strong></div>
          <div className="bar"><i style={{ width: `${quota.weeklyRemainingPercent ?? 0}%` }} /></div>
          <div className="row tiny muted"><span /><span>{formatDateTime(quota.weeklyResetsAt)} 重置 · {formatRemaining(quota.weeklyResetsAt, now)}</span></div>
        </Section>

        <Section id="reset-credit">
          <div className="row"><strong>重置卡</strong><strong>{credits.availableCount} 张</strong></div>
          {credits.items.length === 0 ? <div className="tiny muted">暂无可用重置卡</div> : credits.items.map((item) => (
            <div className="row tiny" key={item.idSuffix}>
              <span className="muted">第 1 张 · 可用</span>
              <span className="right">{formatDateTime(item.expiresAt)} 到期<br />余 {formatRemaining(item.expiresAt, now)}</span>
            </div>
          ))}
        </Section>

        <Section id="reset-radar">
          <div className="row"><strong>重置追踪</strong><button className="ghost" onClick={() => host.current?.scan()}>立即扫描</button></div>
          <div className="row tiny"><span className="muted">每 1 分钟扫描</span><span>{radar.sources.filter((source) => source.state !== "down").length}/{radar.sources.length} 来源可用</span></div>
          {latest ? (
            <div className="quote">
              <div>{latest.title}：{latest.summary}</div>
              <div className="tiny muted">发布于 {formatDateTime(latest.publishedAt)} · {latest.confirmingSources.join("、")}</div>
              <div className="row tiny"><span className="muted">适用范围</span><span>{latest.scope ?? "—"}</span></div>
              <button className="link" onClick={() => latest.url && host.current?.openURL(latest.url)}>查看原始出处 ↗</button>
            </div>
          ) : <div className="tiny muted">暂未确认的重置记录</div>}
          <div className="row tiny muted"><span>上次扫描 {formatDateTime(radar.lastScanAt)}</span><span>下次 {formatDateTime(radar.nextScanAt)}</span></div>
          <button className="link" onClick={() => setSourcesOpen((value) => !value)}>{sourcesOpen ? "收起" : "来源健康与近期记录"}</button>
          {sourcesOpen && (
            <div className="sources">
              {radar.sources.map((source) => (
                <div className="row tiny" key={source.sourceId}>
                  <span>{source.sourceName}</span>
                  <span className={source.state === "ok" ? "green" : "orange"}>{source.state}{source.lastError ? ` · ${source.lastError}` : ""}</span>
                </div>
              ))}
              {radar.recent.slice(1, 6).map((signal) => (
                <div className="row tiny" key={signal.id}>
                  <span className="muted">{formatDateTime(signal.publishedAt)}</span><span>{signal.title}</span>
                </div>
              ))}
            </div>
          )}
          <div className="tiny muted">系统通知未开启时，新动态仍在此处高亮。</div>
          <div className="tiny muted">站点消息不等于个人额度恢复；无明确时间不推算倒计时。</div>
        </Section>

        <Section id="model-health">
          <div className="row">
            <strong>模型状态</strong>
            <button className={`pill ${health.status}`} onClick={() => setHealthOpen((value) => !value)}>{HEALTH_LABEL[health.status]}</button>
          </div>
          <div className="tiny muted">{formatRate(session.outputTokensPerSecond)} · 首 token {session.ttftMs ? `${(session.ttftMs / 1000).toFixed(1)}s` : "—"} · {health.sampleTurns} 轮基线</div>
          {healthOpen && (
            <div className="evidence">
              {health.signals.map((signal) => (
                <div className="row tiny" key={signal.id}><span className={signal.flagged ? "orange" : "muted"}>{signal.label}</span><span>{signal.detail}</span></div>
              ))}
              <div className="tiny muted">{health.disclaimer}</div>
            </div>
          )}
        </Section>

        <Section id="current-session">
          <div className="row"><strong>{session.label}</strong><span className="tiny muted">{session.isActive ? "生成中" : "空闲"}</span></div>
          <div className="row tiny"><span className="muted">上下文</span><span>{contextPercent == null ? "—" : `${contextPercent}% · ${formatTokens(session.contextTokens)} / ${formatTokens(session.contextWindow)}`}</span></div>
          <div className="row tiny"><span className="muted">Token 总数</span><span>{formatTokens(session.totalTokens)}</span></div>
          <div className="row tiny"><span className="muted">输入 / 输出</span><span>{formatTokens(session.inputTokens)} / {formatTokens(session.outputTokens)}</span></div>
          <div className="row tiny"><span className="muted">缓存读取</span><span>{formatTokens(session.cachedInputTokens)}</span></div>
          <div className="row tiny new"><span className="muted">输出速率</span><span><strong data-testid="output-rate">{formatRate(session.outputTokensPerSecond)}</strong> <span className="muted">/ 中位 {formatRate(session.medianOutputTokensPerSecond)}</span></span></div>
        </Section>

        <Section id="account-stats">
          <div className="subhead">账号统计</div>
          <div className="row tiny"><span className="muted">账号今日 Token</span><span>{formatTokens(account.todayTokens)}</span></div>
          <div className="row tiny"><span className="muted">账号累计 Token</span><span>{formatTokens(account.totalTokens)}</span></div>
          <div className="tiny muted">更新于 {formatDateTime(account.updatedAt)} · {account.source}</div>
        </Section>
      </div>
      <footer className="footer">{session.model ?? "—"} {session.effort ?? ""} · 额度 {quota.weeklyRemainingPercent ?? "—"}% · 更新 {formatDateTime(snapshot.generatedAt)}</footer>
    </main>
  );
}
```

`Web/src/main.tsx`:

```tsx
import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import "./styles.css";

ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode><App /></React.StrictMode>
);
```

`Web/index.html`:

```html
<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; img-src data:; connect-src 'none'" />
    <title>CodexInfo</title>
  </head>
  <body><div id="root"></div><script type="module" src="/src/main.tsx"></script></body>
</html>
```

`Web/vite.config.ts`:

```ts
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import { viteSingleFile } from "vite-plugin-singlefile";

export default defineConfig({
  plugins: [react(), viteSingleFile()],
  build: { target: "es2022", cssCodeSplit: false, assetsInlineLimit: 100_000_000 },
});
```

`Web/tsconfig.json`:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "jsx": "react-jsx",
    "strict": true,
    "skipLibCheck": true,
    "noEmit": true,
    "types": ["vite/client"]
  },
  "include": ["src", "tests", "playwright.config.ts", "vite.config.ts"]
}
```

`Web/src/styles.css` (append the full stylesheet; this is the panel's visual baseline):

```css
:root {
  color-scheme: light dark;
  --bg: #ffffff;
  --fg: #1b1b1b;
  --muted: #8b8b87;
  --line: #ededeb;
  --card: #fafaf8;
  --accent: #2e9d6b;
  --warn: #b26a12;
  --danger: #c2413b;
  --new: #4b86f7;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}
@media (prefers-color-scheme: dark) {
  :root { --bg: #1c1c1e; --fg: #f2f2f7; --muted: #8e8e93; --line: #333336; --card: #242426; }
}
* { box-sizing: border-box; }
html, body, #root { margin: 0; min-height: 100%; background: transparent; color: var(--fg); }
.panel { width: 340px; max-height: 780px; display: flex; flex-direction: column; background: var(--bg); border: 1px solid var(--line); border-radius: 14px; box-shadow: 0 18px 48px rgba(0,0,0,.18); overflow: hidden; font-size: 12px; line-height: 1.5; }
.panel.loading, .panel.error { padding: 24px; }
.header { display: flex; align-items: center; gap: 6px; padding: 12px 14px 8px; }
.title { font-size: 16px; }
.badge { border: 1px solid var(--line); border-radius: 4px; padding: 0 5px; color: var(--muted); font-size: 9px; line-height: 15px; }
.ghost { border: 1px solid var(--line); border-radius: 5px; background: transparent; color: var(--fg); height: 22px; padding: 0 7px; font-size: 10px; cursor: pointer; }
.close { margin-left: auto; border: 0; background: transparent; color: var(--muted); font-size: 16px; cursor: pointer; }
.body { overflow: auto; padding: 0 14px; }
.body section { border-top: 1px solid var(--line); padding: 9px 0 8px; }
.body section:first-child { border-top: 0; }
.row { display: flex; justify-content: space-between; align-items: baseline; gap: 8px; margin: 2px 0; }
.row.tiny { font-size: 10px; }
.muted { color: var(--muted); }
.tiny { font-size: 10px; }
.subhead { color: var(--muted); font-size: 10px; margin-bottom: 3px; }
.right { text-align: right; }
.green { color: var(--accent); }
.orange { color: var(--warn); }
.bar { height: 3px; border-radius: 2px; background: color-mix(in srgb, var(--accent) 15%, transparent); overflow: hidden; margin: 7px 0 4px; }
.bar > i { display: block; height: 100%; background: var(--accent); }
.quote { border-radius: 6px; background: var(--card); padding: 7px; margin: 6px 0; font-size: 10px; }
.link { border: 0; background: transparent; color: var(--new); padding: 3px 0; cursor: pointer; font-size: 10px; }
.pill { border: 0; border-radius: 999px; padding: 2px 8px; font-size: 10px; font-weight: 600; cursor: pointer; }
.pill.normal { background: color-mix(in srgb, var(--accent) 14%, transparent); color: var(--accent); }
.pill.suspected { background: color-mix(in srgb, var(--warn) 16%, transparent); color: var(--warn); }
.pill.degraded { background: color-mix(in srgb, var(--danger) 14%, transparent); color: var(--danger); }
.pill.insufficient { background: var(--card); color: var(--muted); }
.evidence { border: 1px dashed var(--new); border-radius: 6px; padding: 6px 7px; margin-top: 6px; background: color-mix(in srgb, var(--new) 5%, transparent); }
.sources { margin: 5px 0; }
.new { border-left: 2px solid var(--new); padding-left: 6px; }
.footer { border-top: 1px solid var(--line); padding: 7px 14px 9px; font-size: 10px; color: var(--muted); }
```

- [ ] **Step 4: Run the UI test and build**

Run: `pnpm --dir Web install && pnpm --dir Web exec playwright test tests/panel.spec.ts`

Expected: one `PASS` line.

Run: `pnpm --dir Web run build`

Expected: `Web/dist/index.html` exists.

- [ ] **Step 5: Commit**

```bash
git add Web
git commit -m "feat: add B-layout panel UI"
```

---

### Task 17: Native/MCP Hosts and WebAssets Generation

**Files:**
- Create: `Web/src/host/nativeHost.ts`
- Create: `Web/src/host/mcpHost.ts`
- Modify: `Web/src/host/detect.ts`
- Modify: `Web/src/host/types.ts`
- Create: `Web/src/vite-env.d.ts`
- Create: `scripts/build-web.sh`
- Create: `Sources/CodexInfoCore/Generated/WebAssets.swift`

**Interfaces:**
- Consumes: `Host`, `UsageSnapshot`, `WebAssets`.
- Produces:
  - Native WKWebView bridge
  - MCP Apps host bridge
  - `WebAssets.panelHTML`

- [ ] **Step 1: Add the native host**

`Web/src/vite-env.d.ts`:

```ts
/// <reference types="vite/client" />

interface Window {
  webkit?: { messageHandlers?: { codexInfo?: { postMessage: (message: unknown) => void } } };
  CodexInfoHost?: {
    render: (snapshot: import("./data/types").UsageSnapshot) => void;
    error: (message: string) => void;
  };
}
```

`Web/src/host/nativeHost.ts`:

```ts
import type { UsageSnapshot } from "../data/types";
import type { Host, HostHandlers } from "./types";

function post(type: string, payload: Record<string, unknown> = {}) {
  window.webkit?.messageHandlers?.codexInfo?.postMessage({ type, ...payload });
}

export class NativeHost implements Host {
  mode = "native" as const;
  private timer?: number;

  async start(handlers: HostHandlers) {
    window.CodexInfoHost = {
      render: (snapshot: UsageSnapshot) => handlers.onSnapshot(snapshot),
      error: (message: string) => handlers.onError(message),
    };
    post("ready");
    this.timer = window.setInterval(() => post("refresh"), 30_000);
  }

  stop() { if (this.timer) window.clearInterval(this.timer); }
  refresh() { post("refresh"); }
  scan() { post("scan"); }
  openURL(url: string) { post("openURL", { url }); }
  openSettings() { post("openSettings"); }
  close() { post("close"); }
}
```

`Web/src/host/mcpHost.ts`:

```ts
import { App, PostMessageTransport } from "@modelcontextprotocol/ext-apps";
import type { UsageSnapshot } from "../data/types";
import type { Host, HostHandlers } from "./types";

function parseSnapshot(result: { structuredContent?: unknown; content?: Array<{ type: string; text?: string }> }): UsageSnapshot | null {
  if (result.structuredContent && typeof result.structuredContent === "object") {
    return result.structuredContent as UsageSnapshot;
  }
  const text = result.content?.find((item) => item.type === "text")?.text;
  if (!text) return null;
  try { return JSON.parse(text) as UsageSnapshot; } catch { return null; }
}

export class McpHost implements Host {
  mode = "mcp" as const;
  private app = new App({ name: "CodexInfo", version: "0.1.0" }, {});
  private handlers?: HostHandlers;
  private timer?: number;

  async start(handlers: HostHandlers) {
    this.handlers = handlers;
    await this.app.connect(new PostMessageTransport(window.parent, window.parent));
    await this.refresh();
    this.timer = window.setInterval(() => this.refresh(), 30_000);
  }

  async refresh() {
    try {
      const result = await this.app.callServerTool({ name: "get_usage_snapshot", arguments: { refresh: false } });
      const snapshot = parseSnapshot(result as unknown as { structuredContent?: unknown; content?: Array<{ type: string; text?: string }> });
      if (snapshot) this.handlers?.onSnapshot(snapshot);
      else this.handlers?.onError("快照格式无效");
    } catch (reason) {
      this.handlers?.onError(String(reason));
    }
  }

  async scan() {
    await this.app.callServerTool({ name: "scan_reset_sources", arguments: {} }).catch(() => undefined);
    await this.refresh();
  }

  stop() { if (this.timer) window.clearInterval(this.timer); }
  openURL(url: string) { void this.app.openLink({ url }); }
  openSettings() {}
  close() {}
}
```

`Web/src/host/detect.ts`:

```ts
import type { Host } from "./types";
import { McpHost } from "./mcpHost";
import { MockHost } from "./mockHost";
import { NativeHost } from "./nativeHost";

export function detectHost(): Host {
  if (window.webkit?.messageHandlers?.codexInfo) return new NativeHost();
  if (window.parent !== window) return new McpHost();
  return new MockHost();
}
```

- [ ] **Step 2: Generate the single-file Swift asset**

`scripts/build-web.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
pnpm --dir "$ROOT/Web" install --frozen-lockfile
pnpm --dir "$ROOT/Web" run build
python3 - "$ROOT/Web/dist/index.html" "$ROOT/Sources/CodexInfoCore/Generated/WebAssets.swift" <<'PY'
import base64, pathlib, sys
html = pathlib.Path(sys.argv[1]).read_bytes()
out = pathlib.Path(sys.argv[2])
out.parent.mkdir(parents=True, exist_ok=True)
payload = base64.b64encode(html).decode()
out.write_text(
    "// Generated by scripts/build-web.sh. Do not edit.\n"
    "import Foundation\n\n"
    "public enum WebAssets {\n"
    "    public static let panelHTML: String = {\n"
    f"        guard let data = Data(base64Encoded: \"{payload}\"), let html = String(data: data, encoding: .utf8) else {{ return \"\" }}\n"
    "        return html\n"
    "    }()\n"
    "}\n",
    encoding="utf-8",
)
PY
```

Run `chmod +x scripts/build-web.sh && bash scripts/build-web.sh`.

- [ ] **Step 3: Verify the build and WebAssets**

Run: `bash scripts/build-web.sh`

Expected: exit 0; `Sources/CodexInfoCore/Generated/WebAssets.swift` exists.

Run:

```bash
python3 - <<'PY'
from pathlib import Path
p = Path("Sources/CodexInfoCore/Generated/WebAssets.swift")
assert "panelHTML" in p.read_text()
assert "base64Encoded" in p.read_text()
print("WebAssets OK")
PY
```

- [ ] **Step 4: Run the existing UI test**

Run: `pnpm --dir Web exec playwright test tests/panel.spec.ts`

Expected: one `PASS` line.

- [ ] **Step 5: Commit**

```bash
git add Web scripts/build-web.sh Sources/CodexInfoCore/Generated/WebAssets.swift
git commit -m "feat: add native/MCP hosts and generate panel asset"
```

### Task 18: MCP Router and Tool Protocol

**Files:**
- Create: `Sources/CodexInfoMCPKit/MCPToolService.swift`
- Create: `Sources/CodexInfoMCPKit/MCPJSON.swift`
- Create: `Sources/CodexInfoMCPKit/MCPRouter.swift`
- Create: `Sources/CodexInfoTests/MCPTests.swift`
- Modify: `Package.swift`
- Modify: `Sources/CodexInfoTests/main.swift`

**Interfaces:**
- Consumes: `UsageSnapshot`, `HealthSnapshot`, `ResetRadarSnapshot`.
- Produces:
  - `MCPToolService` protocol
  - `MCPRouter.handle(line:) async -> [Data]`
  - UI resource `ui://codexinfo/panel.html`

- [ ] **Step 1: Add failing MCP protocol tests**

`Sources/CodexInfoTests/MCPTests.swift`:

```swift
import Foundation
import CodexInfoCore
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
}

struct FakeMCPToolService: MCPToolService {
    func usageSnapshot(refresh: Bool, now: Date) async throws -> UsageSnapshot { MCPTestFixtures.snapshot }
    func modelHealth(windowDays: Int, now: Date) async throws -> HealthSnapshot { .empty }
    func scanResetSources(now: Date) async throws -> ResetRadarSnapshot { .empty }
    func openDashboard() async throws {}
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
```

Modify `Sources/CodexInfoTests/main.swift`:

```swift
registerCoreTests()
registerMCPTests()
```

Modify `Package.swift` targets:

```swift
let package = Package(
    name: "CodexInfo",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexInfoCore", targets: ["CodexInfoCore"]),
        .library(name: "CodexInfoMCPKit", targets: ["CodexInfoMCPKit"]),
        .executable(name: "codexinfo-tests", targets: ["CodexInfoTests"])
    ],
    targets: [
        .target(name: "CodexInfoCore", path: "Sources/CodexInfoCore"),
        .target(name: "CodexInfoMCPKit", dependencies: ["CodexInfoCore"], path: "Sources/CodexInfoMCPKit"),
        .executableTarget(name: "CodexInfoTests", dependencies: ["CodexInfoCore", "CodexInfoMCPKit"], path: "Sources/CodexInfoTests")
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift run codexinfo-tests --filter MCP`

Expected: compile failure because `CodexInfoMCPKit` does not exist.

- [ ] **Step 3: Implement the router**

`Sources/CodexInfoMCPKit/MCPToolService.swift`:

```swift
import Foundation
import CodexInfoCore

public protocol MCPToolService: Sendable {
    func usageSnapshot(refresh: Bool, now: Date) async throws -> UsageSnapshot
    func modelHealth(windowDays: Int, now: Date) async throws -> HealthSnapshot
    func scanResetSources(now: Date) async throws -> ResetRadarSnapshot
    func openDashboard() async throws
}
```

`Sources/CodexInfoMCPKit/MCPJSON.swift`:

```swift
import Foundation

public enum MCPJSON {
    public static func encode<T: Encodable>(_ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    public static func response(id: Any?, result: [String: Any]) -> Data {
        let object: [String: Any] = ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    public static func error(id: Any?, code: Int, message: String) -> Data {
        let object: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": ["code": code, "message": message],
        ]
        return (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    public static func toolError(id: Any?, message: String) -> Data {
        response(id: id, result: [
            "content": [["type": "text", "text": message]],
            "isError": true,
        ])
    }
}
```

`Sources/CodexInfoMCPKit/MCPRouter.swift`:

```swift
import Foundation
import CodexInfoCore

public struct MCPRouter: Sendable {
    private let toolService: MCPToolService
    private let panelHTML: String

    public init(toolService: MCPToolService, panelHTML: String) {
        self.toolService = toolService
        self.panelHTML = panelHTML
    }

    public func handle(line: Data) async -> [Data] {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let method = object["method"] as? String else {
            return [MCPJSON.error(id: nil, code: -32700, message: "parse error")]
        }
        let id = object["id"]
        if method.hasPrefix("notifications/") { return [] }

        switch method {
        case "initialize":
            return [MCPJSON.response(id: id, result: [
                "protocolVersion": "2025-06-18",
                "capabilities": ["tools": [:], "resources": [:]],
                "serverInfo": ["name": "codexinfo", "version": "0.1.0"],
            ])]
        case "ping":
            return [MCPJSON.response(id: id, result: [:])]
        case "tools/list":
            return [MCPJSON.response(id: id, result: ["tools": toolDescriptors])]
        case "resources/list":
            return [MCPJSON.response(id: id, result: ["resources": [[
                "uri": "ui://codexinfo/panel.html",
                "name": "CodexInfo panel",
                "mimeType": "text/html;profile=mcp-app",
            ]]])]
        case "resources/read":
            let params = object["params"] as? [String: Any]
            guard params?["uri"] as? String == "ui://codexinfo/panel.html" else {
                return [MCPJSON.error(id: id, code: -32602, message: "unknown resource")]
            }
            return [MCPJSON.response(id: id, result: ["contents": [[
                "uri": "ui://codexinfo/panel.html",
                "mimeType": "text/html;profile=mcp-app",
                "text": panelHTML,
            ]]])]
        case "tools/call":
            let response = await callTool(id: id, object: object)
            return [response]
        default:
            return [MCPJSON.error(id: id, code: -32601, message: "method not found: \(method)")]
        }
    }

    private func callTool(id: Any?, object: [String: Any]) async -> Data {
        let params = object["params"] as? [String: Any]
        let name = params?["name"] as? String ?? ""
        let arguments = params?["arguments"] as? [String: Any] ?? [:]
        do {
            switch name {
            case "get_usage_snapshot":
                let snapshot = try await toolService.usageSnapshot(refresh: arguments["refresh"] as? Bool ?? false, now: Date())
                return MCPJSON.response(id: id, result: [
                    "content": [["type": "text", "text": summary(snapshot)]],
                    "structuredContent": try MCPJSON.encode(snapshot),
                ])
            case "get_model_health":
                let health = try await toolService.modelHealth(windowDays: arguments["windowDays"] as? Int ?? 7, now: Date())
                return MCPJSON.response(id: id, result: [
                    "content": [["type": "text", "text": "模型状态：\(health.status.rawValue)"]],
                    "structuredContent": try MCPJSON.encode(health),
                ])
            case "scan_reset_sources":
                let radar = try await toolService.scanResetSources(now: Date())
                return MCPJSON.response(id: id, result: [
                    "content": [["type": "text", "text": "\(radar.sourcesAvailable)/\(radar.sources.count) 来源可用"]],
                    "structuredContent": try MCPJSON.encode(radar),
                ])
            case "show_usage_panel":
                let snapshot = try await toolService.usageSnapshot(refresh: false, now: Date())
                return MCPJSON.response(id: id, result: [
                    "content": [["type": "text", "text": summary(snapshot)]],
                    "structuredContent": try MCPJSON.encode(snapshot),
                ])
            case "open_dashboard":
                try await toolService.openDashboard()
                return MCPJSON.response(id: id, result: [
                    "content": [["type": "text", "text": "已打开 CodexInfo 面板"]],
                ])
            default:
                return MCPJSON.error(id: id, code: -32602, message: "unknown tool: \(name)")
            }
        } catch {
            return MCPJSON.toolError(id: id, message: String(describing: error))
        }
    }

    private var toolDescriptors: [[String: Any]] {
        let show: [String: Any] = [
            "name": "show_usage_panel",
            "description": "Render the CodexInfo dashboard as an MCP App.",
            "inputSchema": ["type": "object", "properties": [:], "additionalProperties": false],
            "_meta": [
                "ui": ["resourceUri": "ui://codexinfo/panel.html"],
                "ui/resourceUri": "ui://codexinfo/panel.html",
                "openai/outputTemplate": "ui://codexinfo/panel.html",
            ],
        ]
        return [
            tool("get_usage_snapshot", "Return quota, reset cards, current session, account and health snapshot.", ["refresh": ["type": "boolean"]]),
            tool("get_model_health", "Return the local model-health verdict and evidence.", ["windowDays": ["type": "integer"]]),
            tool("scan_reset_sources", "Scan the four reset sources and return source health.", [:]),
            show,
            tool("open_dashboard", "Open the CodexInfo menu-bar dashboard.", [:]),
        ]
    }

    private func tool(_ name: String, _ description: String, _ properties: [String: Any]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": ["type": "object", "properties": properties, "additionalProperties": false],
        ]
    }

    private func summary(_ snapshot: UsageSnapshot) -> String {
        let quota = snapshot.quota.weeklyRemainingPercent.map { "\($0)%" } ?? "—"
        let rate = snapshot.session.outputTokensPerSecond.map { String(format: "%.1f tok/s", $0) } ?? "—"
        return "周额度剩余 \(quota) · 输出速率 \(rate) · 模型状态 \(snapshot.health.status.rawValue)"
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift run codexinfo-tests --filter MCP`

Expected: four `PASS` lines and `SUMMARY ran=4 failed=0`.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/CodexInfoMCPKit Sources/CodexInfoTests/MCPTests.swift Sources/CodexInfoTests/main.swift
git commit -m "feat: add MCP router and tool protocol"
```

---

### Task 19: Live Environment, MCP Executable and Plugin Package

**Files:**
- Create: `Sources/CodexInfoLive/LiveEnvironment.swift`
- Create: `Sources/CodexInfoLive/LiveMCPToolService.swift`
- Create: `Sources/CodexInfoMCP/main.swift`
- Create: `plugins/codexinfo/.codex-plugin/plugin.json`
- Create: `plugins/codexinfo/.mcp.json.template`
- Create: `plugins/codexinfo/skills/codex-usage/SKILL.md`
- Create: `plugins/codexinfo/assets/icon.svg`
- Create: `.agents/plugins/marketplace.json`
- Create: `scripts/mcp_smoke.py`
- Create: `scripts/install-plugin.sh`
- Modify: `Package.swift`

**Interfaces:**
- Consumes: `CodexInfoCore`, `CodexInfoMCPKit`, `WebAssets`, `NSWorkspace`.
- Produces:
  - `LiveEnvironment.live()`, `.buildSnapshot(now:)`
  - `codexinfo-mcp` executable
  - installable local plugin.

- [ ] **Step 1: Add the live environment and MCP tool service**

`Sources/CodexInfoLive/LiveEnvironment.swift`:

```swift
import Foundation
import CodexInfoCore

public final class LiveEnvironment: @unchecked Sendable {
    public let store: SnapshotStore
    public let builder: SnapshotBuilder
    public let radar: ResetRadarService
    public let repository: SessionRepository

    public init(
        store: SnapshotStore,
        builder: SnapshotBuilder,
        radar: ResetRadarService,
        repository: SessionRepository
    ) {
        self.store = store
        self.builder = builder
        self.radar = radar
        self.repository = repository
    }

    public static func live() -> LiveEnvironment {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexInfo", isDirectory: true)
        let store = SnapshotStore(directory: support)
        let http = URLSessionHTTPClient()
        let credentials = FileCredentialStore()
        let official = OfficialUsageClient(http: http, credentials: credentials)
        let credits = ResetCreditService(
            official: OfficialResetCreditsClient(http: http, credentials: credentials),
            fallback: nil
        )
        let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        let indexer = SessionIndexer(
            rootURL: codexHome.appendingPathComponent("sessions", isDirectory: true),
            cacheURL: support.appendingPathComponent("session-index.json")
        )
        let repository = SessionRepository(indexer: indexer)
        var quotaFallbacks: [QuotaFallbackProviding] = [SessionQuotaFallback(repository: repository)]
        if let binary = CodexBinaryLocator.find() {
            quotaFallbacks.insert(LazyAppServerQuotaFallback(binaryURL: binary), at: 0)
        }
        let quota = QuotaService(official: official, fallback: CompositeQuotaFallback(quotaFallbacks))
        let account = AccountUsageService(official: official, sessions: repository)
        let radar = ResetRadarService(
            sources: [CodexRadarCurrentSource(), CodexRadarFeedSource(), CodexResetsSource(), OpenAIStatusSource()],
            http: http
        )
        let builder = SnapshotBuilder(
            quota: quota, credits: credits, sessions: repository, account: account, radar: radar
        )
        return LiveEnvironment(store: store, builder: builder, radar: radar, repository: repository)
    }

    public func buildSnapshot(now: Date = Date()) async -> UsageSnapshot {
        let snapshot = await builder.build(now: now)
        try? store.save(snapshot)
        return snapshot
    }
}

private struct LazyAppServerQuotaFallback: QuotaFallbackProviding {
    let binaryURL: URL

    func fallbackQuota(now: Date) async -> QuotaSnapshot? {
        guard let transport = try? ProcessAppServerTransport(binaryURL: binaryURL) else { return nil }
        defer { transport.close() }
        let client = CodexAppServerClient(transport: transport)
        return await AppServerQuotaFallback(client: client).fallbackQuota(now: now)
    }
}
```

`Sources/CodexInfoLive/LiveMCPToolService.swift`:

```swift
import AppKit
import Foundation
import CodexInfoCore
import CodexInfoMCPKit

public struct LiveMCPToolService: MCPToolService {
    private let environment: LiveEnvironment

    public init(environment: LiveEnvironment) {
        self.environment = environment
    }

    public func usageSnapshot(refresh: Bool, now: Date) async throws -> UsageSnapshot {
        await environment.buildSnapshot(now: now)
    }

    public func modelHealth(windowDays: Int, now: Date) async throws -> HealthSnapshot {
        let snapshot = await environment.buildSnapshot(now: now)
        return snapshot.health
    }

    public func scanResetSources(now: Date) async throws -> ResetRadarSnapshot {
        await environment.radar.scan(now: now)
    }

    public func openDashboard() async throws {
        let url = URL(string: "codexinfo://show")!
        await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }
}
```

- [ ] **Step 2: Add the MCP executable**

`Sources/CodexInfoMCP/main.swift`:

```swift
import Foundation
import CodexInfoCore
import CodexInfoLive
import CodexInfoMCPKit

let environment = LiveEnvironment.live()
let router = MCPRouter(
    toolService: LiveMCPToolService(environment: environment),
    panelHTML: WebAssets.panelHTML
)

while let line = readLine(strippingNewline: true) {
    guard let data = line.data(using: .utf8) else { continue }
    let responses = await router.handle(line: data)
    for response in responses {
        FileHandle.standardOutput.write(response)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
```

Modify `Package.swift`:

```swift
let package = Package(
    name: "CodexInfo",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CodexInfoCore", targets: ["CodexInfoCore"]),
        .library(name: "CodexInfoMCPKit", targets: ["CodexInfoMCPKit"]),
        .executable(name: "codexinfo-mcp", targets: ["CodexInfoMCP"]),
        .executable(name: "codexinfo-tests", targets: ["CodexInfoTests"])
    ],
    targets: [
        .target(name: "CodexInfoCore", path: "Sources/CodexInfoCore"),
        .target(name: "CodexInfoMCPKit", dependencies: ["CodexInfoCore"], path: "Sources/CodexInfoMCPKit"),
        .target(name: "CodexInfoLive", dependencies: ["CodexInfoCore", "CodexInfoMCPKit"], path: "Sources/CodexInfoLive"),
        .executableTarget(name: "CodexInfoMCP", dependencies: ["CodexInfoCore", "CodexInfoLive", "CodexInfoMCPKit"], path: "Sources/CodexInfoMCP"),
        .executableTarget(name: "CodexInfoTests", dependencies: ["CodexInfoCore", "CodexInfoMCPKit"], path: "Sources/CodexInfoTests")
    ],
    swiftLanguageModes: [.v5]
)
```

- [ ] **Step 3: Add the plugin package and smoke test**

`plugins/codexinfo/.codex-plugin/plugin.json`:

```json
{
  "name": "codexinfo",
  "version": "0.1.0",
  "description": "Codex usage, reset cards, reset radar, output speed and local model health.",
  "author": { "name": "laoer" },
  "mcpServers": "./.mcp.json",
  "skills": "./skills/",
  "interface": {
    "displayName": "CodexInfo",
    "shortDescription": "Quota, reset cards, tok/s and local model health",
    "category": "Developer Tools",
    "composerIcon": "./assets/icon.svg",
    "logo": "./assets/icon.svg"
  }
}
```

`plugins/codexinfo/.mcp.json.template`:

```json
{
  "mcpServers": {
    "codexinfo": {
      "command": "__CODEXINFO_MCP_BINARY__",
      "cwd": "__CODEXINFO_PLUGIN_DIR__",
      "args": [],
      "enabled": true,
      "startup_timeout_sec": 15,
      "tool_timeout_sec": 60
    }
  }
}
```

`plugins/codexinfo/skills/codex-usage/SKILL.md`:

```markdown
---
name: codex-usage
description: Use when the user asks about Codex quota, weekly usage, reset cards, reset radar, output tokens per second, or whether the model seems degraded. Calls CodexInfo MCP tools and summarizes.
---

# CodexInfo

- For quota, reset cards, reset radar, tok/s or model health, call `get_usage_snapshot`.
- Answer in at most three lines: weekly remaining, output rate, model status.
- For detailed evidence, call `get_model_health` and show the `signals` rows.
- For a full panel, call `show_usage_panel`; to open the menu-bar panel, call `open_dashboard`.
- Never claim a global reset recovered the user's personal quota; only `quota.weeklyResetsAt` drives the countdown.
```

`plugins/codexinfo/assets/icon.svg`:

```svg
<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">
  <rect width="64" height="64" rx="14" fill="#1b1b1b"/>
  <path d="M18 32h28M32 18v28" stroke="#2e9d6b" stroke-width="5" stroke-linecap="round"/>
</svg>
```

`.agents/plugins/marketplace.json`:

```json
{
  "name": "codexinfo",
  "interface": { "displayName": "CodexInfo" },
  "plugins": [
    {
      "name": "codexinfo",
      "source": { "source": "local", "path": "./plugins/codexinfo" },
      "policy": { "installation": "AVAILABLE", "authentication": "ON_INSTALL" },
      "category": "Developer Tools"
    }
  ]
}
```

`scripts/install-plugin.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift build -c release --product codexinfo-mcp
BIN="$ROOT/.build/release/codexinfo-mcp"
PLUGIN="$ROOT/plugins/codexinfo"
mkdir -p "$PLUGIN/bin"
cp "$BIN" "$PLUGIN/bin/codexinfo-mcp"
chmod +x "$PLUGIN/bin/codexinfo-mcp"
python3 - "$PLUGIN" <<'PY'
import json, pathlib, sys
plugin = pathlib.Path(sys.argv[1])
template = (plugin / ".mcp.json.template").read_text()
data = json.loads(template)
server = data["mcpServers"]["codexinfo"]
server["command"] = str(plugin / "bin" / "codexinfo-mcp")
server["cwd"] = str(plugin)
(plugin / ".mcp.json").write_text(json.dumps(data, indent=2) + "\n")
PY
echo "Plugin ready: $PLUGIN"
echo "Add these lines to ~/.codex/config.toml (back up first):"
echo "[marketplaces.codexinfo]"
echo "source_type = \"local\""
echo "source = \"$ROOT\""
echo "[plugins.\"codexinfo@codexinfo\"]"
echo "enabled = true"
```

`scripts/mcp_smoke.py`:

```python
import json
import subprocess
import sys

binary = sys.argv[1]
proc = subprocess.Popen([binary], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

def send(message):
    proc.stdin.write(json.dumps(message) + "\n")
    proc.stdin.flush()

def receive():
    return json.loads(proc.stdout.readline())

send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
init = receive()
assert init["result"]["serverInfo"]["name"] == "codexinfo", init
send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
tools = receive()
assert any(tool["name"] == "show_usage_panel" for tool in tools["result"]["tools"]), tools
send({"jsonrpc": "2.0", "id": 3, "method": "resources/read", "params": {"uri": "ui://codexinfo/panel.html"}})
resource = receive()
assert resource["result"]["contents"][0]["mimeType"] == "text/html;profile=mcp-app", resource
print("MCP smoke OK")
proc.terminate()
```

Run `chmod +x scripts/install-plugin.sh scripts/mcp_smoke.py` and:

```bash
swift build -c release --product codexinfo-mcp
python3 scripts/mcp_smoke.py "$(swift build -c release --show-bin-path)/codexinfo-mcp"
```

- [ ] **Step 4: Build and smoke-test**

Run: `swift build -c release --product codexinfo-mcp`

Expected: build succeeds.

Run: `bash scripts/install-plugin.sh`

Expected: plugin `.mcp.json` generated; config lines printed.

Run:

```bash
BIN="$(swift build -c release --show-bin-path)/codexinfo-mcp"
python3 scripts/mcp_smoke.py "$BIN"
```

Expected: `MCP smoke OK`.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/CodexInfoLive Sources/CodexInfoMCP plugins .agents scripts/install-plugin.sh scripts/mcp_smoke.py
git commit -m "feat: add live MCP server and local plugin package"
```

### Task 20: Menu Bar App, Panel Bridge, Settings and Notifications

**Files:**
- Create: `Sources/CodexInfoApp/main.swift`
- Create: `Sources/CodexInfoApp/AppDelegate.swift`
- Create: `Sources/CodexInfoApp/AppEnvironment.swift`
- Create: `Sources/CodexInfoApp/MenuBarController.swift`
- Create: `Sources/CodexInfoApp/PanelViewController.swift`
- Create: `Sources/CodexInfoApp/PanelMessage.swift`
- Create: `Sources/CodexInfoApp/SettingsStore.swift`
- Create: `Sources/CodexInfoApp/SettingsView.swift`
- Create: `Sources/CodexInfoApp/NotificationController.swift`
- Create: `Sources/CodexInfoApp/LaunchAtLogin.swift`
- Create: `Sources/CodexInfoCore/Support/StatusTitleFormatter.swift`
- Modify: `Package.swift`
- Modify: `Sources/CodexInfoCore/Services/SnapshotBuilder.swift`
- Modify: `Sources/CodexInfoTests/CoreTests.swift`

**Interfaces:**
- Consumes: `LiveEnvironment`, `WebAssets`, `PanelMessage`.
- Produces:
  - `NSStatusItem` label and `NSPopover` panel
  - settings and notifications
  - `codexinfo://show` handling

- [ ] **Step 1: Add failing status-title tests**

Append to `registerCoreTests()`:

```swift
    test("StatusTitleFormatter renders quota, rate and health") { context in
        let snapshot = MCPTestFixtures.snapshot
        let title = StatusTitleFormatter.format(snapshot, segments: [.quota, .rate, .health])
        context.expectEqual(title.text, "84% · — · 数据不足")
    }

    test("StatusTitleFormatter marks low quota") { context in
        var snapshot = MCPTestFixtures.snapshot
        snapshot = UsageSnapshot(
            generatedAt: snapshot.generatedAt,
            freshness: snapshot.freshness,
            quota: QuotaSnapshot(planType: "pro", weeklyRemainingPercent: 7, weeklyResetsAt: nil, source: .official, fetchedAt: snapshot.quota.fetchedAt),
            resetCredits: snapshot.resetCredits,
            session: snapshot.session,
            account: snapshot.account,
            health: snapshot.health,
            resetRadar: snapshot.resetRadar
        )
        let title = StatusTitleFormatter.format(snapshot, segments: [.quota])
        context.expectEqual(title.parts.first?.color, .danger)
    }
```

`MCPTestFixtures` lives in `MCPTests.swift`; `CoreTests.swift` can see it because both are in the same test target. Add `StatusTitleFormatter` tests after Task 20 implementation; the test will fail until then.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift run codexinfo-tests --filter StatusTitle`

Expected: compile failure because `StatusTitleFormatter` does not exist.

- [ ] **Step 3: Implement the status formatter and app**

`Sources/CodexInfoCore/Support/StatusTitleFormatter.swift`:

```swift
import Foundation

public enum StatusSegment: String, Codable, CaseIterable, Hashable, Sendable {
    case quota
    case rate
    case health
    case credits
    case updated
}

public enum StatusColor: String, Equatable, Sendable {
    case normal
    case good
    case warn
    case danger
    case muted
}

public struct StatusTitlePart: Equatable, Sendable {
    public let text: String
    public let color: StatusColor
}

public struct StatusTitle: Equatable, Sendable {
    public let parts: [StatusTitlePart]
    public var text: String { parts.map(\.text).joined(separator: " · ") }
}

public enum StatusTitleFormatter {
    public static func format(_ snapshot: UsageSnapshot, segments: [StatusSegment] = [.quota, .rate, .health]) -> StatusTitle {
        var parts: [StatusTitlePart] = []
        for segment in segments {
            switch segment {
            case .quota:
                let value = snapshot.quota.weeklyRemainingPercent
                let color: StatusColor = value == nil ? .muted : (value! < 10 ? .danger : (value! < 30 ? .warn : .good))
                parts.append(StatusTitlePart(text: value.map { "\($0)%" } ?? "—", color: color))
            case .rate:
                let value = snapshot.session.outputTokensPerSecond
                parts.append(StatusTitlePart(text: value.map { String(format: "%.0f tok/s", $0) } ?? "—", color: value == nil ? .muted : .normal))
            case .health:
                let text: String
                let color: StatusColor
                switch snapshot.health.status {
                case .normal: text = "正常"; color = .good
                case .suspected: text = "疑似"; color = .warn
                case .degraded: text = "异常"; color = .danger
                case .insufficient: text = "数据不足"; color = .muted
                }
                parts.append(StatusTitlePart(text: text, color: color))
            case .credits:
                parts.append(StatusTitlePart(text: "\(snapshot.resetCredits.availableCount) 卡", color: snapshot.resetCredits.availableCount > 0 ? .good : .muted))
            case .updated:
                parts.append(StatusTitlePart(text: snapshot.generatedAt.formatted(date: .omitted, time: .shortened), color: .muted))
            }
        }
        return StatusTitle(parts: parts)
    }
}
```

`Sources/CodexInfoApp/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

`Sources/CodexInfoApp/PanelMessage.swift`:

```swift
import Foundation

enum PanelMessage: Equatable {
    case ready
    case refresh
    case scan
    case openURL(String)
    case openSettings
    case close

    static func parse(_ body: Any) -> PanelMessage? {
        guard let dictionary = body as? [String: Any], let type = dictionary["type"] as? String else { return nil }
        switch type {
        case "ready": return .ready
        case "refresh": return .refresh
        case "scan": return .scan
        case "openURL":
            guard let value = dictionary["url"] as? String, let url = URL(string: value),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            return .openURL(value)
        case "openSettings": return .openSettings
        case "close": return .close
        default: return nil
        }
    }
}
```

`Sources/CodexInfoApp/PanelViewController.swift`:

```swift
import AppKit
import WebKit
import CodexInfoCore

final class PanelViewController: NSViewController, WKScriptMessageHandler, WKNavigationDelegate {
    private let webView: WKWebView
    private var pendingSnapshot: UsageSnapshot?
    var onMessage: ((PanelMessage) -> Void)?

    init() {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        configuration.userContentController = contentController
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        contentController.add(self, name: "codexInfo")
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        if let dev = ProcessInfo.processInfo.environment["CODEXINFO_DEV_URL"], let url = URL(string: dev) {
            webView.load(URLRequest(url: url))
        } else {
            webView.loadHTMLString(WebAssets.panelHTML, baseURL: nil)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        view = NSView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func render(_ snapshot: UsageSnapshot) {
        pendingSnapshot = snapshot
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot), let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.CodexInfoHost && window.CodexInfoHost.render(\(json));")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let parsed = PanelMessage.parse(message.body) { onMessage?(parsed) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url,
           ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
           navigationAction.navigationType == .linkActivated {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}
```

`Sources/CodexInfoApp/MenuBarController.swift`:

```swift
import AppKit
import SwiftUI
import CodexInfoCore

@MainActor
final class MenuBarController: NSObject {
    private let environment: AppEnvironment
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let panel = PanelViewController()
    private var settingsWindow: NSWindow?
    private var contextMenu: NSMenu?

    init(environment: AppEnvironment) {
        self.environment = environment
        super.init()
        panel.onMessage = { [weak self] message in self?.handle(message) }
        popover.contentViewController = panel
        popover.contentSize = NSSize(width: 340, height: 780)
        popover.behavior = .transient
        popover.animates = true
        contextMenu = makeMenu()
        configureStatusItem()
        environment.onSnapshot = { [weak self] snapshot in
            self?.update(snapshot)
        }
    }

    func install() {
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    func update(_ snapshot: UsageSnapshot) {
        let title = StatusTitleFormatter.format(snapshot, segments: environment.settings.settings.segments)
        let attributed = NSMutableAttributedString()
        for (index, part) in title.parts.enumerated() {
            if index > 0 {
                attributed.append(NSAttributedString(string: " · ", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
            }
            attributed.append(NSAttributedString(string: part.text, attributes: [.font: font, .foregroundColor: color(for: part.color)]))
        }
        statusItem.button?.attributedTitle = attributed
        panel.render(snapshot)
    }

    @objc func showPanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            if let menu = contextMenu, let button = statusItem.button {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
            }
        } else {
            showPanel()
        }
    }

    private var font: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    }

    private func color(for color: StatusColor) -> NSColor {
        switch color {
        case .normal: return .labelColor
        case .good: return .systemGreen
        case .warn: return .systemOrange
        case .danger: return .systemRed
        case .muted: return .secondaryLabelColor
        }
    }

    private func configureStatusItem() {
        statusItem.button?.imagePosition = .noImage
        statusItem.button?.title = "CodexInfo"
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开面板", action: #selector(showPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "立即刷新", action: #selector(refresh), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "扫描重置源", action: #selector(scan), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "退出 CodexInfo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for item in menu.items { item.target = item.action == #selector(NSApplication.terminate(_:)) ? NSApp : self }
        return menu
    }

    @objc private func refresh() { Task { await environment.refresh() } }
    @objc private func scan() { Task { await environment.scan() } }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(store: environment.settings)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "CodexInfo 设置"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 420, height: 360))
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func handle(_ message: PanelMessage) {
        switch message {
        case .ready:
            if let snapshot = environment.snapshot { panel.render(snapshot) }
        case .refresh: Task { await environment.refresh() }
        case .scan: Task { await environment.scan() }
        case .openURL(let value):
            if let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            }
        case .openSettings: showSettings()
        case .close: popover.performClose(nil)
        }
    }
}
```

`Sources/CodexInfoApp/AppEnvironment.swift`:

```swift
import Foundation
import Combine
import CodexInfoCore
import CodexInfoLive

@MainActor
final class AppEnvironment: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var error: String?
    let settings = SettingsStore()
    let notifications = NotificationController()
    let live = LiveEnvironment.live()
    var onSnapshot: ((UsageSnapshot) -> Void)?
    private var refreshTask: Task<Void, Never>?

    func start() {
        notifications.onOpen = { [weak self] in
            Task { @MainActor in self?.openRequested?() }
        }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                await self.refresh()
                try? await Task.sleep(nanoseconds: UInt64(AppConstants.refreshSessionSeconds * 1_000_000_000))
            }
        }
    }

    var openRequested: (() -> Void)?

    func refresh() async {
        let value = await live.builder.build(
            now: Date(),
            windowDays: settings.settings.baselineWindowDays,
            minimumTurns: settings.settings.minimumTurns
        )
        snapshot = value
        error = nil
        try? live.store.save(value)
        onSnapshot?(value)
        await notifications.evaluate(snapshot: value, settings: settings.settings)
    }

    func scan() async {
        _ = await live.radar.scan(now: Date())
        await refresh()
    }
}
```

`Sources/CodexInfoApp/AppDelegate.swift`:

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var environment: AppEnvironment!
    private var menuBar: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        environment = AppEnvironment()
        menuBar = MenuBarController(environment: environment)
        environment.openRequested = { [weak self] in self?.menuBar.showPanel() }
        menuBar.install()
        environment.start()
        Task { await environment.refresh() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.scheme == "codexinfo" }) {
            menuBar.showPanel()
        }
    }
}
```

`Sources/CodexInfoApp/SettingsStore.swift`:

```swift
import Foundation
import Combine
import CodexInfoCore

struct Settings: Codable, Equatable {
    var baselineWindowDays = 7
    var minimumTurns = 8
    var notificationsEnabled = false
    var launchAtLogin = false
    var segments: [StatusSegment] = [.quota, .rate, .health]
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var settings: Settings {
        didSet { save() }
    }
    private let url: URL

    init() {
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexInfo", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        url = support.appendingPathComponent("settings.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(Settings.self, from: data) {
            settings = decoded
        } else {
            settings = Settings()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
```

`Sources/CodexInfoApp/SettingsView.swift`:

```swift
import SwiftUI
import CodexInfoCore

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Section("常驻条片段") {
                ForEach(StatusSegment.allCases, id: \.self) { segment in
                    Toggle(label(for: segment), isOn: Binding(
                        get: { store.settings.segments.contains(segment) },
                        set: { enabled in
                            if enabled {
                                if !store.settings.segments.contains(segment) { store.settings.segments.append(segment) }
                            } else {
                                store.settings.segments.removeAll { $0 == segment }
                            }
                        }
                    ))
                }
            }
            Section("模型基线") {
                Picker("基线窗口", selection: Binding(
                    get: { store.settings.baselineWindowDays },
                    set: { store.settings.baselineWindowDays = $0 }
                )) {
                    Text("7 天").tag(7)
                    Text("14 天").tag(14)
                    Text("30 天").tag(30)
                }
                Stepper("最少轮数：\(store.settings.minimumTurns)", value: Binding(
                    get: { store.settings.minimumTurns },
                    set: { store.settings.minimumTurns = min(max($0, 3), 30) }
                ), in: 3...30)
            }
            Section("通知") {
                Toggle("启用系统通知", isOn: Binding(
                    get: { store.settings.notificationsEnabled },
                    set: { value in
                        store.settings.notificationsEnabled = value
                        if value { Task { _ = await NotificationController().requestAuthorization() } }
                    }
                ))
            }
            Section("启动") {
                Toggle("登录时启动", isOn: Binding(
                    get: { store.settings.launchAtLogin },
                    set: { value in
                        do { try LaunchAtLogin.set(value); store.settings.launchAtLogin = value }
                        catch { store.settings.launchAtLogin = LaunchAtLogin.isEnabled }
                    }
                ))
            }
            Section("隐私") {
                Text("凭证只驻留内存；不读取对话正文。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private func label(for segment: StatusSegment) -> String {
        switch segment {
        case .quota: return "周额度"
        case .rate: return "输出速率"
        case .health: return "模型状态"
        case .credits: return "重置卡"
        case .updated: return "更新时间"
        }
    }
}
```

`Sources/CodexInfoApp/NotificationController.swift`:

```swift
import Foundation
import UserNotifications
import CodexInfoCore

final class NotificationController: NSObject, UNUserNotificationCenterDelegate {
    var onOpen: (() -> Void)?
    private let center = UNUserNotificationCenter.current()
    private let sentKey = "codexinfo.sentNotifications"

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func evaluate(snapshot: UsageSnapshot, settings: Settings) async {
        guard settings.notificationsEnabled else { return }
        var sent = UserDefaults.standard.stringArray(forKey: sentKey) ?? []
        func sendOnce(_ key: String, _ title: String, _ body: String) {
            guard !sent.contains(key) else { return }
            sent.append(key)
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
        }
        if let reset = snapshot.resetRadar.latestConfirmed {
            sendOnce("reset:\(reset.id)", "检测到已确认重置", reset.title)
        }
        for card in snapshot.resetCredits.items {
            if let expires = card.expiresAt, expires.timeIntervalSinceNow < 24 * 3600 {
                sendOnce("card:\(card.idSuffix)", "重置卡即将过期", "\(card.idSuffix) 将在 24 小时内到期")
            }
        }
        if let remaining = snapshot.quota.weeklyRemainingPercent, remaining < 10 {
            sendOnce("quota:\(snapshot.quota.weeklyResetsAt?.timeIntervalSince1970 ?? 0)", "周额度低于 10%", "剩余 \(remaining)%")
        }
        UserDefaults.standard.set(sent, forKey: sentKey)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        onOpen?()
        completionHandler()
    }
}
```

`Sources/CodexInfoApp/LaunchAtLogin.swift`:

```swift
import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
```

Modify `SnapshotBuilder.build` to accept `windowDays`:

```swift
    public func build(now: Date = Date(), windowDays: Int = 7) async -> UsageSnapshot {
        ...
        let health = DegradationAnalyzer.analyze(
            baselineTurns: baselineTurns,
            currentTurns: currentTurns,
            routeMismatch: sessionSnapshot?.routeMismatch ?? false,
            now: now,
            windowDays: windowDays
        )
```

Modify `Package.swift` products/targets:

```swift
        .executable(name: "CodexInfoApp", targets: ["CodexInfoApp"])
...
        .executableTarget(
            name: "CodexInfoApp",
            dependencies: ["CodexInfoCore", "CodexInfoLive"],
            path: "Sources/CodexInfoApp"
        ),
```

- [ ] **Step 4: Run tests and build**

Run: `swift run codexinfo-tests --filter StatusTitle`

Expected: two `PASS` lines and `SUMMARY ran=2 failed=0`.

Run: `swift build --product CodexInfoApp`

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add Package.swift Sources/CodexInfoCore/Services/SnapshotBuilder.swift Sources/CodexInfoCore/Support/StatusTitleFormatter.swift Sources/CodexInfoApp Sources/CodexInfoTests/CoreTests.swift
git commit -m "feat: add menu bar app, settings and notifications"
```

### Task 21: Build, Install, End-to-End Acceptance

**Files:**
- Create: `scripts/build-app.sh`
- Create: `scripts/test.sh`
- Create: `scripts/dev.sh`
- Create: `.github/workflows/ci.yml`
- Create: `Info.plist` content inside `scripts/build-app.sh`

**Interfaces:**
- Consumes: all prior tasks.
- Produces:
  - `dist/CodexInfo.app`
  - `codexinfo-mcp` in the app bundle and plugin
  - one-command test entry point.

- [ ] **Step 1: Write the build and test scripts**

`scripts/build-app.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
bash "$ROOT/scripts/build-web.sh"
swift build -c release --product CodexInfoApp
swift build -c release --product codexinfo-mcp
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$ROOT/dist/CodexInfo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CodexInfoApp" "$APP/Contents/MacOS/CodexInfoApp"
cp "$BIN_DIR/codexinfo-mcp" "$APP/Contents/MacOS/codexinfo-mcp"
chmod +x "$APP/Contents/MacOS/"*
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>CodexInfoApp</string>
  <key>CFBundleIdentifier</key><string>com.laoer.codexinfo</string>
  <key>CFBundleName</key><string>CodexInfo</string>
  <key>CFBundleDisplayName</key><string>CodexInfo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key><string>com.laoer.codexinfo</string>
      <key>CFBundleURLSchemes</key><array><string>codexinfo</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built $APP"
```

`scripts/test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift run codexinfo-tests
bash "$ROOT/scripts/build-web.sh"
swift build -c release --product codexinfo-mcp
BIN="$(swift build -c release --show-bin-path)/codexinfo-mcp"
python3 "$ROOT/scripts/mcp_smoke.py" "$BIN"
pnpm --dir "$ROOT/Web" exec playwright test
```

`scripts/dev.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
pnpm --dir "$ROOT/Web" dev &
WEB_PID=$!
trap 'kill $WEB_PID 2>/dev/null || true' EXIT
CODEXINFO_DEV_URL="http://127.0.0.1:5173" swift run CodexInfoApp
```

`.github/workflows/ci.yml`:

```yaml
name: ci
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
        with: { version: 9 }
      - uses: actions/setup-node@v4
        with: { node-version: 24, cache: pnpm, cache-dependency-path: Web/pnpm-lock.yaml }
      - run: swift run codexinfo-tests
      - run: bash scripts/build-web.sh
      - run: swift build -c release --product codexinfo-mcp
      - run: python3 scripts/mcp_smoke.py "$(swift build -c release --show-bin-path)/codexinfo-mcp"
      - run: pnpm --dir Web exec playwright install chromium
      - run: pnpm --dir Web exec playwright test
```

Run:

```bash
chmod +x scripts/build-app.sh scripts/test.sh scripts/dev.sh
bash scripts/build-app.sh
```

Expected: `dist/CodexInfo.app` exists, ad-hoc signed.

- [ ] **Step 2: Run the automated gate**

Run: `bash scripts/test.sh`

Expected:

- `codexinfo-tests` prints `SUMMARY ... failed=0`.
- Web build exits 0.
- `MCP smoke OK`.
- Playwright prints one passing test.

- [ ] **Step 3: Install and run the menu bar app**

Run: `open dist/CodexInfo.app`

Expected:

- A menu bar item appears with quota, rate and model status.
- Clicking it opens the 340px panel.
- Header, quota, reset cards, reset tracking, model health, current session with tok/s, account stats and footer are visible.
- The panel matches the B order.

- [ ] **Step 4: Install the Codex plugin and run the MCP App check**

Run:

```bash
bash scripts/install-plugin.sh
```

Add the printed `[marketplaces.codexinfo]` and `[plugins."codexinfo@codexinfo"]` blocks to `~/.codex/config.toml` after backing it up, then restart Codex.

In Codex:

1. Confirm `CodexInfo` appears in plugin settings.
2. Ask `查看我的 Codex 用量`.
3. Confirm the model calls `get_usage_snapshot` and returns at most three lines.
4. Ask `打开用量面板`.
5. If M0 passed, confirm `show_usage_panel` renders the panel; otherwise confirm the text summary and `open_dashboard` work.

- [ ] **Step 5: Manual acceptance and final commit**

Run the seven checks from the spec:

1. Menu bar label and panel open/close.
2. Quota/reset cards match the official Codex usage page within one refresh.
3. A completed turn's tok/s matches `output_tokens / net generation time`.
4. Synthetic weak baseline shows “数据不足” or “疑似降智” with evidence.
5. Four sources show `x/4`; a source failure does not block others.
6. Removing auth.json shows a re-login hint without a crash; quota falls back.
7. Search logs/caches/UI for a token; confirm the allowlist and no token.

Measure:

```bash
/usr/bin/time -lp open dist/CodexInfo.app
```

Expected: app opens; no crash; panel first paint ≤2s once snapshot exists.

Commit:

```bash
git add scripts/build-app.sh scripts/test.sh scripts/dev.sh
git commit -m "chore: add build, test and install scripts"
```

If any manual check fails, do not mark the task complete; add a focused fix task and rerun the gate.

---

## Self-Review Checklist

Before execution, verify:

- **Spec coverage:** UI B layout → Task 16; menu bar → Task 20; quota → Tasks 3–4; reset cards → Task 5; session/tok/s → Tasks 6–9; account → Task 10; degradation → Task 11; reset radar → Tasks 12–14; snapshot → Task 15; plugin/MCP → Tasks 18–19; packaging → Task 21.
- **M0 gate:** Task 1 result determines whether MCP App rendering is available; the fallback is documented in Task 19.
- **No secrets:** fixtures use `tok_test` only; no auth token is committed.
- **Type consistency:** `QuotaSnapshot`, `ResetCreditsSnapshot`, `SessionSnapshot`, `AccountSnapshot`, `HealthSnapshot`, `ResetRadarSnapshot`, `UsageSnapshot` are defined before use in `SnapshotBuilder`; `OutputRateCalculator` is used by `SessionRepository` and `BaselineBuilder`; `MCPTestFixtures` is shared by Core and MCP tests.
- **Test runner:** all Swift tests use `swift run codexinfo-tests`, not XCTest.
- **No automatic card use:** no `consume` call exists in the plan.

## Deferred Polish (post-MVP)

- Source URL/enable/timeout editors and scan-interval UI. The four confirmed sources use their default URLs in this plan; the adapter boundaries already isolate each URL. A settings-aware live factory is a follow-up.
- Notification permission status block inside the panel (the settings toggle requests authorization; the panel shows the notification-off hint).
- Developer ID signing, notarization and auto-update. This plan stops at an ad-hoc local app bundle.
- Quota history chart and CSV export; explicitly outside v1.
