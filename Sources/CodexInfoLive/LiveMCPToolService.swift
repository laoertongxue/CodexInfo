import AppKit
import Foundation
import CodexInfoCore
import CodexInfoMCPKit

/// Opens the panel of the menu bar app.
public protocol DashboardOpening: Sendable {
    /// Opens the dashboard.
    func openDashboard() async throws
}

/// Opens the dashboard with the handler of the system.
///
/// The app registers the URL scheme `codexinfo`, so the system browser hands
/// the request to the running app and the panel comes up.
public struct SystemBrowserDashboard: DashboardOpening {
    /// The URL that opens the panel.
    public static let dashboardURL = URL(string: "codexinfo://show")!

    /// Creates the opener.
    public init() {}

    public func openDashboard() async throws {
        let url = Self.dashboardURL
        await MainActor.run {
            _ = NSWorkspace.shared.open(url)
        }
    }
}

/// The live implementation of the MCP tools.
///
/// The service answers with the data of this machine: the snapshot of the
/// account, the local model-health verdict, the state of the reset sources
/// and the panel of the menu bar app.
public struct LiveMCPToolService: MCPToolService {
    private let builder: any SnapshotBuilding
    private let radar: any ResetRadarScanning
    private let dashboard: any DashboardOpening

    /// Creates the service for the given live environment.
    ///
    /// - Parameter environment: the live services of this machine.
    public init(environment: LiveEnvironment) {
        self.init(
            builder: environment,
            radar: environment,
            dashboard: SystemBrowserDashboard()
        )
    }

    /// Creates the service for the given services.
    ///
    /// - Parameters:
    ///   - builder: the source of the snapshot.
    ///   - radar: the source of the reset sources.
    ///   - dashboard: the opener of the panel.
    public init(
        builder: any SnapshotBuilding,
        radar: any ResetRadarScanning,
        dashboard: any DashboardOpening
    ) {
        self.builder = builder
        self.radar = radar
        self.dashboard = dashboard
    }

    public func usageSnapshot(refresh: Bool, now: Date) async throws -> UsageSnapshot {
        await builder.buildSnapshot(now: now, refresh: refresh, windowDays: 7)
    }

    public func modelHealth(windowDays: Int, now: Date) async throws -> HealthSnapshot {
        let snapshot = await builder.buildSnapshot(now: now, refresh: false, windowDays: windowDays)
        return snapshot.health
    }

    public func scanResetSources(now: Date) async throws -> ResetRadarSnapshot {
        await radar.scan(now: now)
    }

    public func openDashboard() async throws {
        try await dashboard.openDashboard()
    }
}
