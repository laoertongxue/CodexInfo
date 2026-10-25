import Foundation

/// The kinds of events the app notifies about.
public enum NotificationEventKind: String, Codable, Equatable, Hashable, Sendable {
    /// A reset two sources confirmed.
    case confirmedReset
    /// A reset the source verified and marked as strong.
    case strongSignal
    /// The weekly window is about to reset.
    case resetApproaching
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

/// Keeps the keys of the events that were already handled.
///
/// The keys are kept in insertion order, not sorted order: when the limit is
/// reached the oldest key is dropped and a recent one is not re-sent.
public enum NotificationKeyHistory {
    /// Appends the fresh keys and trims the oldest ones.
    ///
    /// - Parameters:
    ///   - existing: the keys in the order they were first handled.
    ///   - fresh: the keys that were not handled before.
    ///   - limit: the maximum number of keys to remember.
    public static func appended(
        _ existing: [String],
        fresh: Set<String>,
        limit: Int = 200
    ) -> [String] {
        guard limit > 0 else { return [] }
        var ordered = existing
        for key in fresh.sorted() where !ordered.contains(key) {
            ordered.append(key)
        }
        if ordered.count > limit {
            ordered.removeFirst(ordered.count - limit)
        }
        return ordered
    }
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
    /// How long before the weekly reset the reminder is raised.
    public static let resetLeadTime: TimeInterval = 15 * 60

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

        if let reset = snapshot.quota.weeklyResetsAt {
            let seconds = reset.timeIntervalSince(now)
            if seconds > 0, seconds <= resetLeadTime {
                let minutes = max(1, Int((seconds / 60).rounded()))
                let remaining = snapshot.quota.weeklyRemainingPercent.map { "\($0)%" } ?? "—"
                events.append(NotificationEvent(
                    kind: .resetApproaching,
                    // The exact reset moment can drift by a second; the reset
                    // hour is stable for the reminder window.
                    key: "resetSoon:\(quotaCycle(snapshot))",
                    title: "周额度将在 \(minutes) 分钟后重置",
                    body: "北京时间 \(beijingTime(reset)) 重置 · 当前剩余 \(remaining)"
                ))
            }
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
                key: "quota:\(lowQuotaCycle(snapshot))",
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

    /// What the app should do with the events of a snapshot.
    ///
    /// The keys of the events are remembered even when the notifications are
    /// off, so that turning them on later does not raise a burst of old
    /// events.
    public struct NotificationPlan: Equatable, Sendable {
        public let events: [NotificationEvent]
        public let nextSentKeys: Set<String>

        public init(events: [NotificationEvent], nextSentKeys: Set<String>) {
            self.events = events
            self.nextSentKeys = nextSentKeys
        }
    }

    /// The plan of one snapshot.
    ///
    /// - Parameters:
    ///   - snapshot: the snapshot the events are read from.
    ///   - notificationsEnabled: whether the events may be shown.
    ///   - now: the moment the expiry of the credits is measured from.
    ///   - sentKeys: the keys of the events that were already seen.
    public static func plan(
        snapshot: UsageSnapshot,
        notificationsEnabled: Bool,
        now: Date = Date(),
        sentKeys: Set<String>
    ) -> NotificationPlan {
        let fresh = events(snapshot: snapshot, now: now).filter { !sentKeys.contains($0.key) }
        return NotificationPlan(
            events: notificationsEnabled ? fresh : [],
            nextSentKeys: sentKeys.union(fresh.map(\.key))
        )
    }

    /// The key of the quota cycle.
    ///
    /// The cycle is the reset hour, rounded to the nearest hour. A reset
    /// timestamp that drifts by a second keeps the same key, while a second
    /// reset in the same week gets its own reminder.
    private static func quotaCycle(_ snapshot: UsageSnapshot) -> String {
        let raw = snapshot.quota.weeklyResetsAt ?? snapshot.generatedAt
        return String(Int((raw.timeIntervalSince1970 / 3600).rounded()))
    }

    /// The key of the low-quota event.
    ///
    /// Without a reset instant the snapshot time would form an hourly key and
    /// repeat the warning every hour. Fall back to the ISO week instead.
    private static func lowQuotaCycle(_ snapshot: UsageSnapshot) -> String {
        guard snapshot.quota.weeklyResetsAt == nil else {
            return quotaCycle(snapshot)
        }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let parts = calendar.dateComponents(
            [.yearForWeekOfYear, .weekOfYear], from: snapshot.generatedAt
        )
        return "\(parts.yearForWeekOfYear ?? 0)-\(parts.weekOfYear ?? 0)"
    }

    /// The reset moment in Beijing time, for the notification body.
    private static func beijingTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
}
