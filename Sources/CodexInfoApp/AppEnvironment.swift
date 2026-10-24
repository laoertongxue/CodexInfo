import Foundation
import Combine
import CodexInfoCore
import CodexInfoLive

/// The state of the app.
///
/// The environment builds the snapshot, hands it to the panel and asks the
/// notification controller about the events of the snapshot.
@MainActor
final class AppEnvironment: ObservableObject {
    /// The snapshot the panel shows.
    @Published private(set) var snapshot: UsageSnapshot?
    /// The last error of the refresh.
    ///
    /// The panel shows it through the bridge, so a broken write is visible
    /// instead of silent.
    var onError: ((String) -> Void)?
    @Published private(set) var error: String?
    /// The settings of the app.
    let settings: SettingsStore
    /// The notifications of the app.
    let notifications: NotificationController
    /// The live services of this machine.
    let live: LiveEnvironment

    /// Called with every new snapshot.
    var onSnapshot: ((UsageSnapshot) -> Void)?
    /// Called when the panel should be opened.
    var openRequested: (() -> Void)?

    private var refreshTask: Task<Void, Never>?

    init(live: LiveEnvironment = .live()) {
        self.live = live
        self.settings = SettingsStore()
        self.notifications = NotificationController()
    }

    /// Starts the refresh loop and the notifications.
    ///
    /// The snapshot is rebuilt every few seconds, so the rate of the current
    /// session stays fresh without the user asking for it.
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

    /// Stops the refresh loop.
    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Rebuilds the snapshot and hands it to the panel.
    func refresh() async {
        let current = settings.settings
        let value = await live.builder.build(
            now: Date(),
            windowDays: current.baselineWindowDays,
            minimumTurns: current.minimumTurns
        )
        snapshot = value
        do {
            try live.store.save(value)
            error = nil
        } catch {
            // The panel still shows the snapshot; only the file is missing.
            self.error = "快照写入失败：\(error.localizedDescription)"
            onError?(self.error ?? "")
        }
        onSnapshot?(value)
        notifications.evaluate(snapshot: value, settings: current)
    }

    /// Scans the reset sources and rebuilds the snapshot.
    func scan() async {
        _ = await live.radar.scan(now: Date())
        await refresh()
    }
}
