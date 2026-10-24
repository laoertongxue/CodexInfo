import Foundation
import CodexInfoCore

/// Builds the snapshot the live services publish.
///
/// The protocol keeps the live service testable: the tool service is checked
/// against a fake builder instead of the real file system and network.
public protocol SnapshotBuilding: Sendable {
    /// Builds the snapshot of the given moment.
    ///
    /// - Parameters:
    ///   - now: the moment the snapshot belongs to.
    ///   - refresh: whether a cached snapshot may be ignored.
    ///   - windowDays: the size of the baseline window in days.
    func buildSnapshot(now: Date, refresh: Bool, windowDays: Int) async -> UsageSnapshot
}

/// Scans the reset sources of the live environment.
public protocol ResetRadarScanning: Sendable {
    /// Scans the sources and returns the new radar snapshot.
    func scan(now: Date) async -> ResetRadarSnapshot
}

/// The live services of the app and of the MCP server.
///
/// The environment points at the real data of the machine: the sessions of
/// `~/.codex` (or of `CODEX_HOME`), the credentials of the signed-in account
/// and the support directory of the app.
public final class LiveEnvironment: @unchecked Sendable, SnapshotBuilding, ResetRadarScanning {
    /// The store the snapshot is written to.
    public let store: SnapshotStore
    /// The builder that combines the services into one snapshot.
    public let builder: SnapshotBuilder
    /// The radar that scans the four reset sources.
    public let radar: ResetRadarService
    /// The repository of the indexed sessions.
    public let repository: SessionRepository

    /// Creates the environment.
    ///
    /// - Parameters:
    ///   - store: the store the snapshot is written to.
    ///   - builder: the builder of the snapshot.
    ///   - radar: the radar of the reset sources.
    ///   - repository: the repository of the indexed sessions.
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

    /// Assembles the live services of this machine.
    ///
    /// - Parameter snapshotFileName: the name of the snapshot file; the MCP
    ///   server writes its own file, so it never overwrites the one of the
    ///   menu bar app.
    public static func live(snapshotFileName: String = SnapshotStore.fileName) -> LiveEnvironment {
        let support = SnapshotStore.defaultDirectory
        let store = SnapshotStore(directory: support, fileName: snapshotFileName)
        let http = URLSessionHTTPClient()
        let credentials = FileCredentialStore()
        let official = OfficialUsageClient(http: http, credentials: credentials)
        let credits = ResetCreditService(
            official: OfficialResetCreditsClient(http: http, credentials: credentials),
            fallback: nil
        )
        let codexHome = ProcessInfo.processInfo.environment[AppConstants.codexHomeEnvironmentKey]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
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
            sources: [
                CodexRadarCurrentSource(),
                CodexRadarFeedSource(),
                CodexResetsSource(),
                OpenAIStatusSource(),
            ],
            http: http
        )
        let builder = SnapshotBuilder(
            quota: quota, credits: credits, sessions: repository, account: account, radar: radar
        )
        return LiveEnvironment(store: store, builder: builder, radar: radar, repository: repository)
    }

    /// Builds the snapshot and writes it to the store.
    ///
    /// A snapshot that is younger than the refresh window is reused, so a
    /// host that asks twice in a row does not pay for the network twice.
    ///
    /// - Parameters:
    ///   - now: the moment the snapshot belongs to.
    ///   - refresh: whether the cached snapshot may be ignored.
    ///   - windowDays: the size of the baseline window in days.
    public func buildSnapshot(
        now: Date = Date(),
        refresh: Bool = false,
        windowDays: Int = 7
    ) async -> UsageSnapshot {
        if !refresh, let cached = try? store.load(maxAge: AppConstants.refreshQuotaSeconds, now: now) {
            return cached
        }
        let snapshot = await builder.build(now: now, windowDays: windowDays)
        try? store.save(snapshot)
        return snapshot
    }

    /// Scans the reset sources and returns the new radar snapshot.
    public func scan(now: Date) async -> ResetRadarSnapshot {
        await radar.scan(now: now)
    }
}

/// Reads the quota from the Codex app server, starting it on demand.
///
/// The binary is only started when the official endpoint failed, so a working
/// account never pays for the app server.
private struct LazyAppServerQuotaFallback: QuotaFallbackProviding {
    let binaryURL: URL

    func fallbackQuota(now: Date) async -> QuotaSnapshot? {
        guard let transport = try? ProcessAppServerTransport(binaryURL: binaryURL) else { return nil }
        defer { transport.close() }
        let client = CodexAppServerClient(transport: transport)
        return await AppServerQuotaFallback(client: client).fallbackQuota(now: now)
    }
}
