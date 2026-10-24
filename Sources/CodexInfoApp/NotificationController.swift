import Foundation
import UserNotifications
import CodexInfoCore

/// The system notifications of the app.
///
/// The rules live in `NotificationEventEvaluator`; the controller only sends
/// the events and remembers the ones it has already sent, so the same event
/// never appears twice — not even after a restart of the app.
@MainActor
final class NotificationController: NSObject, UNUserNotificationCenterDelegate {
    /// The key the sent events are remembered under.
    static let sentKey = "codexinfo.sentNotifications"

    /// Called when the user opens a notification.
    var onOpen: (() -> Void)?

    private let center: UNUserNotificationCenter?
    private let defaults: UserDefaults

    init(center: UNUserNotificationCenter? = NotificationController.systemCenter(), defaults: UserDefaults = .standard) {
        self.center = center
        self.defaults = defaults
        super.init()
        center?.delegate = self
    }

    /// The notification center of the system.
    ///
    /// The system needs a bundle, so a binary that is run outside of an app
    /// bundle has no notification center and shows no notification.
    nonisolated static func systemCenter() -> UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    /// Asks for the permission of the system.
    func requestAuthorization() async -> Bool {
        guard let center else { return false }
        return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Evaluates the events of a snapshot and sends the new ones.
    ///
    /// The events are only sent when the notifications are enabled; the panel
    /// keeps showing the new events either way.
    ///
    /// - Parameters:
    ///   - snapshot: the snapshot the events are read from.
    ///   - settings: the settings of the app.
    ///   - now: the moment the expiry of the credits is measured from.
    func evaluate(snapshot: UsageSnapshot, settings: AppSettings, now: Date = Date()) {
        let sent = Set(defaults.stringArray(forKey: Self.sentKey) ?? [])
        let events = NotificationEventEvaluator.newEvents(snapshot: snapshot, now: now, sentKeys: sent)
        guard settings.notificationsEnabled, !events.isEmpty else { return }
        for event in events {
            let content = UNMutableNotificationContent()
            content.title = event.title
            content.body = event.body
            center?.add(UNNotificationRequest(identifier: event.key, content: content, trigger: nil))
        }
        defaults.set(sent.union(events.map(\.key)).sorted(), forKey: Self.sentKey)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor [weak self] in self?.onOpen?() }
        completionHandler()
    }
}
