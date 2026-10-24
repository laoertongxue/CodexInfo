import Foundation

/// The kinds of events the app notifies about.
public enum NotificationEventKind: String, Codable, Equatable, Hashable, Sendable {
    /// A reset two sources confirmed.
    case confirmedReset
    /// A reset the source verified and marked as strong.
    case strongSignal
    /// A reset credit that expires soon.
    case cardExpiring
    /// A weekly quota that is nearly used up.
    case lowQuota
}

/// One event the app may notify about.
///
/// The content of an event only carries the quota, the time and the source;
/// it never carries a line of the conversation.
public struct NotificationEvent: Equatable, Hashable, Sendable, Identifiable {
    /// The kind of the event.
    public let kind: NotificationEventKind
    /// The key that remembers the event.
    ///
    /// The key is stable for the event, so the same reset, the same card and
    /// the same quota cycle are only notified once.
    public let key: String
    /// The title of the notification.
    public let title: String
    /// The text of the notification.
    public let body: String

    public init(kind: NotificationEventKind, key: String, title: String, body: String) {
        self.kind = kind
        self.key = key
        self.title = title
        self.body = body
    }

    public var id: String { key }
}

/// Finds the events of a snapshot.
///
/// The four triggers of the design spec are evaluated here, so the rules can
/// be checked without asking for the permission of the system.
public enum NotificationEventEvaluator {
    /// The hours a reset credit may have left before the event is raised.
    public static let cardExpiryHours: TimeInterval = 24
    /// The remaining weekly quota below which the event is raised.
    public static let lowQuotaPercent = 10

    /// The events of a snapshot.
    ///
    /// - Parameters:
    ///   - snapshot: the snapshot the events are read from.
    ///   - now: the moment the expiry of the credits is measured from.
    public static func events(snapshot: UsageSnapshot, now: Date = Date()) -> [NotificationEvent] {
        var events: [NotificationEvent] = []
        let radar = snapshot.resetRadar

        if let reset = radar.latestConfirmed {
            events.append(NotificationEvent(
                kind: .confirmedReset,
                key: "reset:\(reset.id)",
                title: "检测到已确认重置",
                body: "\(reset.title) · \(reset.sourceName)"
            ))
        }

        if let strong = radar.latestStrong {
            events.append(NotificationEvent(
                kind: .strongSignal,
                key: "strong:\(strong.id)",
                title: "检测到强信号",
                body: "\(strong.title) · \(strong.sourceName)"
            ))
        }

        for card in snapshot.resetCredits.items where card.isAvailable {
            guard let expiry = card.expiresAt, expiry > now else { continue }
            let hours = expiry.timeIntervalSince(now) / 3600
            guard hours < cardExpiryHours else { continue }
            events.append(NotificationEvent(
                kind: .cardExpiring,
                key: "card:\(card.idSuffix)",
                title: "重置卡即将过期",
                body: "\(card.idSuffix) 将在 \(max(1, Int(hours.rounded()))) 小时内到期"
            ))
        }

        if let remaining = snapshot.quota.weeklyRemainingPercent, remaining < lowQuotaPercent {
            events.append(NotificationEvent(
                kind: .lowQuota,
                key: "quota:\(quotaCycle(snapshot))",
                title: "周额度低于 \(lowQuotaPercent)%",
                body: "剩余 \(remaining)%"
            ))
        }

        return events
    }

    /// The events of a snapshot that were not notified about yet.
    ///
    /// - Parameters:
    ///   - snapshot: the snapshot the events are read from.
    ///   - now: the moment the expiry of the credits is measured from.
    ///   - sentKeys: the keys of the events that were notified about.
    public static func newEvents(
        snapshot: UsageSnapshot,
        now: Date = Date(),
        sentKeys: Set<String>
    ) -> [NotificationEvent] {
        events(snapshot: snapshot, now: now).filter { !sentKeys.contains($0.key) }
    }

    /// The key of the quota cycle.
    ///
    /// The cycle of the quota is the moment the weekly window resets. Without
    /// that moment the week of the snapshot is used, so the quota is notified
    /// about once per week and not once per refresh.
    private static func quotaCycle(_ snapshot: UsageSnapshot) -> String {
        if let resetsAt = snapshot.quota.weeklyResetsAt {
            return String(Int(resetsAt.timeIntervalSince1970))
        }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: snapshot.generatedAt)
        return "\(parts.yearForWeekOfYear ?? 0)-\(parts.weekOfYear ?? 0)"
    }
}
