import AppKit
import Foundation
import CodexInfoCore
import CodexInfoMCPKit

/// Opens the panel of the menu bar app.
public protocol DashboardOpening: Sendable {
    /// Opens the dashboard.
    func openDashboard() async throws
}

/// Answers whether the menu bar app runs right now.
public protocol ApplicationRunningChecking: Sendable {
    /// Whether the app of the given bundle identifier runs.
    func isAppRunning(bundleIdentifier: String) -> Bool
}

/// Looks at the running applications of the system.
public struct RunningApplications: ApplicationRunningChecking {
    public init() {}

    public func isAppRunning(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }
}

/// The reasons the dashboard cannot be opened.
public enum DashboardError: LocalizedError, Equatable {
    /// The menu bar app is not running, so nothing would come up.
    case appNotRunning

    public var errorDescription: String? {
        switch self {
        case .appNotRunning:
            return "CodexInfo 菜单栏 App 没有运行，请先启动它（应用包 dist/CodexInfo.app）；"
                + "插件摘要仍然可用。"
        }
    }
}

/// Opens the dashboard with the handler of the system.
///
/// The app registers the URL scheme `codexinfo`, so the system browser hands
/// the request to the running app and the panel comes up. When the app does
/// not run, nothing would come up, so the tool answers with an install and
/// start hint instead (design 6.7).
public struct SystemBrowserDashboard: DashboardOpening {
    /// The URL that opens the panel.
    public static let dashboardURL = URL(string: "codexinfo://show")!
    /// The bundle identifier of the menu bar app.
    public static let bundleIdentifier = AppConstants.bundleIdentifier

    private let running: any ApplicationRunningChecking
    private let opener: @Sendable (URL) -> Void

    /// Creates the opener.
    ///
    /// - Parameters:
    ///   - running: the check for the running app; the default looks at the
    ///     running applications of the system.
    ///   - opener: the handler of the URL; the default hands it to the system.
    public init(
        running: any ApplicationRunningChecking = RunningApplications(),
        opener: @escaping @Sendable (URL) -> Void = { url in _ = NSWorkspace.shared.open(url) }
    ) {
        self.running = running
        self.opener = opener
    }

    public func openDashboard() async throws {
        guard running.isAppRunning(bundleIdentifier: Self.bundleIdentifier) else {
            throw DashboardError.appNotRunning
        }
        let url = Self.dashboardURL
        await MainActor.run {
            opener(url)
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
