import Foundation
import CodexInfoCore

/// The JSON-RPC router of the MCP server.
///
/// The router is a pure library: it takes one line of JSON-RPC and returns the
/// bytes of the answers. It never writes to the standard streams and it never
/// reads a file; the panel HTML is injected by the caller, so the server only
/// hands out what it was given.
public struct MCPRouter: Sendable {
    /// The URI of the MCP App panel.
    public static let panelResourceURI = "ui://codexinfo/panel.html"
    /// The MIME type of the panel resource.
    public static let panelMIMEType = "text/html;profile=mcp-app"
    /// The name the server answers with.
    public static let serverName = "codexinfo"
    /// The version the server answers with.
    public static let serverVersion = AppConstants.version
    /// The protocol versions the server answers with.
    ///
    /// A client that asks for one of them gets the version it asked for; every
    /// other version falls back to `defaultProtocolVersion`.
    public static let supportedProtocolVersions = ["2025-06-18", "2025-11-21", "2024-11-05"]
    /// The protocol version used when the client asks for an unknown one.
    public static let defaultProtocolVersion = "2025-06-18"

    private let toolService: MCPToolService
    private let panelHTML: String

    /// Creates a router.
    ///
    /// - Parameters:
    ///   - toolService: the source of the numbers the tools answer with.
    ///   - panelHTML: the panel the UI resource hands out; the router never
    ///     reads it from the file system.
    public init(toolService: MCPToolService, panelHTML: String) {
        self.toolService = toolService
        self.panelHTML = panelHTML
    }

    /// The answers of one line of JSON-RPC.
    ///
    /// An empty result means the line was a notification: notifications are
    /// never answered.
    public func handle(line: Data) async -> [Data] {
        guard let json = try? JSONSerialization.jsonObject(with: line),
              let object = json as? [String: Any],
              let method = object["method"] as? String else {
            return [MCPJSON.error(id: nil, code: -32700, message: "parse error")]
        }
        let id = object["id"]
        if method.hasPrefix("notifications/") { return [] }

        switch method {
        case "initialize":
            return [initialize(id: id, object: object)]
        case "ping":
            return [MCPJSON.response(id: id, result: [:])]
        case "tools/list":
            return [MCPJSON.response(id: id, result: ["tools": toolDescriptors])]
        case "resources/list":
            return [MCPJSON.response(id: id, result: ["resources": [panelResource]])]
        case "resources/read":
            return readResource(id: id, object: object)
        case "tools/call":
            return [await callTool(id: id, object: object)]
        default:
            return [MCPJSON.error(id: id, code: -32601, message: "method not found: \(method)")]
        }
    }

    // MARK: - Methods

    /// The handshake.
    ///
    /// The server answers with the protocol version the client asked for, as
    /// long as it is one the server knows; an unknown version falls back to the
    /// default one.
    private func initialize(id: Any?, object: [String: Any]) -> Data {
        let params = object["params"] as? [String: Any]
        let requested = params?["protocolVersion"] as? String
        let version = requested.flatMap { Self.supportedProtocolVersions.contains($0) ? $0 : nil }
            ?? Self.defaultProtocolVersion
        return MCPJSON.response(id: id, result: [
            "protocolVersion": version,
            "capabilities": ["tools": [:], "resources": [:]],
            "serverInfo": ["name": Self.serverName, "version": Self.serverVersion],
        ])
    }

    /// The panel the host reads to render the MCP App.
    private func readResource(id: Any?, object: [String: Any]) -> [Data] {
        let params = object["params"] as? [String: Any]
        guard params?["uri"] as? String == Self.panelResourceURI else {
            return [MCPJSON.error(id: id, code: -32602, message: "unknown resource")]
        }
        return [MCPJSON.response(id: id, result: ["contents": [[
            "uri": Self.panelResourceURI,
            "name": "CodexInfo panel",
            "mimeType": Self.panelMIMEType,
            "text": panelHTML,
        ]]])]
    }

    /// The answer of a tool call.
    ///
    /// A tool that fails answers with `isError` and the reason; a failing tool
    /// never takes the server down.
    private func callTool(id: Any?, object: [String: Any]) async -> Data {
        let params = object["params"] as? [String: Any]
        let name = params?["name"] as? String ?? ""
        let arguments = params?["arguments"] as? [String: Any] ?? [:]
        do {
            switch name {
            case "get_usage_snapshot":
                let snapshot = try await toolService.usageSnapshot(
                    refresh: arguments["refresh"] as? Bool ?? false,
                    now: Date()
                )
                return MCPJSON.toolResult(
                    id: id,
                    text: snapshotSummary(snapshot),
                    structured: try MCPJSON.encode(snapshot)
                )
            case "get_model_health":
                let health = try await toolService.modelHealth(
                    windowDays: arguments["windowDays"] as? Int ?? 7,
                    now: Date()
                )
                return MCPJSON.toolResult(
                    id: id,
                    text: healthSummary(health),
                    structured: try MCPJSON.encode(health)
                )
            case "scan_reset_sources":
                let radar = try await toolService.scanResetSources(now: Date())
                return MCPJSON.toolResult(
                    id: id,
                    text: radarSummary(radar),
                    structured: try MCPJSON.encode(radar)
                )
            case "show_usage_panel":
                let snapshot = try await toolService.usageSnapshot(refresh: false, now: Date())
                return MCPJSON.response(id: id, result: [
                    "content": [["type": "text", "text": snapshotSummary(snapshot)]],
                    "isError": false,
                    "structuredContent": try MCPJSON.encode(snapshot),
                    "_meta": uiMetadata,
                ])
            case "open_dashboard":
                try await toolService.openDashboard()
                return MCPJSON.toolResult(
                    id: id,
                    text: "已打开 CodexInfo 面板",
                    structured: ["opened": true]
                )
            default:
                return MCPJSON.error(id: id, code: -32602, message: "unknown tool: \(name)")
            }
        } catch {
            return MCPJSON.toolError(id: id, message: Self.reason(for: error))
        }
    }

    // MARK: - The tools

    /// The tools the server offers.
    private var toolDescriptors: [[String: Any]] {
        [
            tool(
                "get_usage_snapshot",
                "Return the quota, the reset cards, the current session, the account, the rate and the health summary.",
                ["refresh": ["type": "boolean"]]
            ),
            tool(
                "get_model_health",
                "Return the local model-health verdict with its evidence.",
                ["windowDays": ["type": "integer"]]
            ),
            tool(
                "scan_reset_sources",
                "Scan the four reset sources and return their health.",
                // The sources are optional: an empty list scans every source.
                ["sourceIds": ["type": "array", "items": ["type": "string"]]]
            ),
            [
                "name": "show_usage_panel",
                "description": "Render the CodexInfo dashboard as an MCP App.",
                "inputSchema": ["type": "object", "properties": [:], "additionalProperties": false],
                "_meta": uiMetadata,
            ],
            tool(
                "open_dashboard",
                "Open the CodexInfo menu-bar dashboard.",
                [:]
            ),
        ]
    }

    /// The descriptor of a tool without a UI binding.
    private func tool(_ name: String, _ description: String, _ properties: [String: Any]) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": ["type": "object", "properties": properties, "additionalProperties": false],
        ]
    }

    /// The UI binding of the panel.
    ///
    /// The modern key, the legacy key and the Codex key all point at the same
    /// resource, so every host finds the panel.
    private var uiMetadata: [String: Any] {
        [
            "ui": ["resourceUri": Self.panelResourceURI],
            "ui/resourceUri": Self.panelResourceURI,
            "openai/outputTemplate": Self.panelResourceURI,
        ]
    }

    /// The panel the resources list offers.
    private var panelResource: [String: Any] {
        [
            "uri": Self.panelResourceURI,
            "name": "CodexInfo panel",
            "description": "The CodexInfo dashboard.",
            "mimeType": Self.panelMIMEType,
        ]
    }

    // MARK: - The summaries

    /// The one line a caller reads before it looks at the payload.
    private func snapshotSummary(_ snapshot: UsageSnapshot) -> String {
        let quota = snapshot.quota.weeklyRemainingPercent.map { "\($0)%" } ?? "—"
        let rate = snapshot.session.outputTokensPerSecond.map { String(format: "%.1f tok/s", $0) } ?? "—"
        return "周额度剩余 \(quota) · 输出速率 \(rate) · 模型状态 \(Self.healthLabel(snapshot.health.status))"
    }

    /// The one line of the health verdict.
    private func healthSummary(_ health: HealthSnapshot) -> String {
        "模型状态 \(Self.healthLabel(health.status)) · 基线 \(health.baselineWindowDays) 天 · 样本 \(health.sampleTurns) 轮"
    }

    /// The one line of the reset sources.
    private func radarSummary(_ radar: ResetRadarSnapshot) -> String {
        "重置源 \(radar.sourcesAvailable)/\(radar.sources.count) 可用 · 最近记录 \(radar.recent.count) 条"
    }

    /// The label of a verdict, in the wording of the panel.
    private static func healthLabel(_ status: HealthStatus) -> String {
        switch status {
        case .normal: return "正常"
        case .suspected: return "疑似降智"
        case .degraded: return "已降智"
        case .insufficient: return "数据不足"
        }
    }

    /// The reason of a failed tool, in a readable wording.
    private static func reason(for error: Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}
