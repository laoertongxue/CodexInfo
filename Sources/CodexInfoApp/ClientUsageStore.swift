import Foundation
import Combine
import CodexInfoCore
import CodexInfoLive

/// The data of the clients that are not Codex.
///
/// The store feeds the compact client panels. The panel's refresh (and its
/// 30-second tick) asks the store for a new read.
@MainActor
final class ClientUsageStore: ObservableObject {
    /// The last snapshot of every client.
    @Published private(set) var snapshots: [ClientID: ClientUsageSnapshot] = [:]

    private let providers: [ClientID: @Sendable () async -> ClientUsageSnapshot?]
    private var refreshing = false
    private var refreshPending = false
    private var timer: Timer?

    init(providers: [ClientID: @Sendable () async -> ClientUsageSnapshot?]) {
        self.providers = providers
    }

    /// The live providers of this machine.
    static func live() -> ClientUsageStore {
        let qoder = QoderUsageProvider()
        let deepSeek = DeepSeekUsageProvider(http: ClientUsageHTTP.deepSeek())
        let miniMax = MiniMaxUsageProvider(http: ClientUsageHTTP.miniMax())
        let openCode = OpenCodeUsageProvider(
            goHTTP: ClientUsageHTTP.openCodeGo(),
            zenHTTP: ClientUsageHTTP.openCodeZen()
        )
        return ClientUsageStore(providers: [
            .qoder: { await qoder.snapshot() },
            .deepSeekHarness: { await deepSeek.snapshot() },
            .miniMaxCode: { await miniMax.snapshot() },
            .openCode: { await openCode.snapshot() },
        ])
    }

    /// The snapshots in the order of the panel tabs.
    var ordered: [ClientUsageSnapshot] {
        [.qoder, .miniMaxCode, .openCode, .deepSeekHarness].compactMap { snapshots[$0] }
    }

    /// Reads every client once at launch and then every 30 seconds.
    ///
    /// The native timer keeps the data fresh even when WebKit throttles the
    /// hidden panel page; the panel's own refresh is a second trigger.
    func start() {
        Task { await refreshAll() }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshAll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops the native refresh timer.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Reads every client in parallel.
    ///
    /// A request that arrives while a read is in flight is remembered and
    /// repeated after it, so a manual refresh is never silently lost.
    func refreshAll() async {
        if refreshing {
            refreshPending = true
            return
        }
        refreshing = true
        defer { refreshing = false }
        repeat {
            refreshPending = false
            let providers = self.providers
            await withTaskGroup(of: (ClientID, ClientUsageSnapshot?).self) { group in
                for (target, provider) in providers {
                    group.addTask { (target, await provider()) }
                }
                for await (target, snapshot) in group {
                    if let snapshot {
                        snapshots[target] = snapshot
                    }
                }
            }
        } while refreshPending
    }
}
