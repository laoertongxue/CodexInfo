import Foundation
import CodexInfoCore

/// The data the MCP tools need, behind a protocol.
///
/// The router owns the protocol; the service owns where the numbers come from.
/// The split keeps the router testable with a fake and lets the live service
/// (with its file system and network access) arrive later.
public protocol MCPToolService: Sendable {
    /// The whole snapshot of the account.
    func usageSnapshot(refresh: Bool, now: Date) async throws -> UsageSnapshot
    /// The local model-health verdict with its evidence.
    func modelHealth(windowDays: Int, now: Date) async throws -> HealthSnapshot
    /// The health of the four reset sources.
    func scanResetSources(now: Date) async throws -> ResetRadarSnapshot
    /// Opens the menu-bar dashboard of the app.
    func openDashboard() async throws
}
