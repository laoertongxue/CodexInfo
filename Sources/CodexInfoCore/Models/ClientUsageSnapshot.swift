import Foundation

/// One quota window of a client, shown as used / total points.
public struct ClientQuotaLimit: Codable, Equatable, Sendable, Identifiable {
    /// `fiveHour` or `weekly`.
    public var id: String
    /// The label of the window, e.g. `5 小时限额`.
    public var label: String
    /// The used points of the window.
    public var usedPoints: Int
    /// The total points of the window; a boosted week can be above 100.
    public var totalPoints: Int
    /// The used percentage the client reports, when it differs from
    /// `usedPoints / totalPoints` (Qoder reports 42% for 826 / 2000).
    public var usedPercent: Int?
    /// The next reset of the window.
    public var resetAt: Date?
    /// The verb of `resetAt`: `重置` or `刷新`.
    public var resetLabel: String?

    public init(
        id: String,
        label: String,
        usedPoints: Int,
        totalPoints: Int,
        usedPercent: Int? = nil,
        resetAt: Date? = nil,
        resetLabel: String? = nil
    ) {
        self.id = id
        self.label = label
        self.usedPoints = usedPoints
        self.totalPoints = totalPoints
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.resetLabel = resetLabel
    }
}

/// One usage-reset card of a client.
public struct ClientResetCard: Codable, Equatable, Sendable, Identifiable {
    /// The card id of the client.
    public var id: String
    /// The raw source type, e.g. `mcode_signin`.
    public var source: String?
    /// The label of the source, e.g. `完全重置`.
    public var label: String?
    /// The moment the card expires.
    public var expiresAt: Date?
    /// The moment the card was granted.
    public var grantedAt: Date?

    public init(
        id: String,
        source: String? = nil,
        label: String? = nil,
        expiresAt: Date? = nil,
        grantedAt: Date? = nil
    ) {
        self.id = id
        self.source = source
        self.label = label
        self.expiresAt = expiresAt
        self.grantedAt = grantedAt
    }
}

/// The data of a client panel that is not Codex.
///
/// The menu bar panel switches between the full Codex panel and a compact
/// panel per client. The compact panel only carries what the client exposes:
/// a quota or a balance, the model, the reset or expiry, and the source.
public struct ClientUsageSnapshot: Codable, Equatable, Sendable {
    /// The identifier of the client: `qoder`, `miniMaxCode` or
    /// `deepSeekHarness`.
    public var client: String
    /// The name shown in the tab and the header.
    public var name: String
    /// The remaining quota, in percent.
    public var quotaPercent: Int?
    /// A quota that is not a percentage, e.g. `¥41.60`.
    public var quotaText: String?
    /// The label of the quota: `额度` or `余额`.
    public var quotaLabel: String
    /// A secondary line, e.g. `剩余 1174 / 2400 积分`.
    public var detail: String?
    /// The next reset or expiry.
    public var resetsAt: Date?
    /// The label of `resetsAt`: `重置` or `到期`.
    public var resetLabel: String?
    /// The model of the client, when it is known.
    public var model: String?
    /// The reasoning effort of the client, when it is known.
    public var effort: String?
    /// The source of the number, e.g. `本地用量日志`.
    public var source: String
    /// The moment the number was read.
    public var updatedAt: Date
    /// The tone of the quota.
    public var tone: ClientBadgeTone
    /// A short note about the freshness or the meaning of the number.
    public var note: String?
    /// The available reset cards; `nil` means the client has no card feed or
    /// the feed failed.
    public var resetCards: [ClientResetCard]?
    /// The number of cards the client reports, including cards not in the
    /// first page.
    public var resetCardTotal: Int?
    /// The quota windows of the client; MiniMax reports the 5-hour and the
    /// weekly window separately.
    public var limits: [ClientQuotaLimit]?

    public init(
        client: String,
        name: String,
        quotaPercent: Int? = nil,
        quotaText: String? = nil,
        quotaLabel: String = "额度",
        detail: String? = nil,
        resetsAt: Date? = nil,
        resetLabel: String? = nil,
        model: String? = nil,
        effort: String? = nil,
        source: String,
        updatedAt: Date,
        tone: ClientBadgeTone = .normal,
        note: String? = nil,
        resetCards: [ClientResetCard]? = nil,
        resetCardTotal: Int? = nil,
        limits: [ClientQuotaLimit]? = nil
    ) {
        self.client = client
        self.name = name
        self.quotaPercent = quotaPercent
        self.quotaText = quotaText
        self.quotaLabel = quotaLabel
        self.detail = detail
        self.resetsAt = resetsAt
        self.resetLabel = resetLabel
        self.model = model
        self.effort = effort
        self.source = source
        self.updatedAt = updatedAt
        self.tone = tone
        self.note = note
        self.resetCards = resetCards
        self.resetCardTotal = resetCardTotal
        self.limits = limits
    }

    /// The compact line of the overlay.
    public var badge: ClientBadge {
        ClientBadge(
            model: model,
            effort: effort,
            quotaPercent: quotaPercent,
            quotaText: quotaText,
            quotaLabel: quotaLabel,
            session: "会话 —",
            tone: tone
        )
    }
}
