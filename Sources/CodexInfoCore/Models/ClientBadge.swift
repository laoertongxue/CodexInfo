import Foundation

/// The tone of a badge: the quota is plain, low or critical.
public enum ClientBadgeTone: String, Codable, Equatable, Sendable {
    case normal
    case warn
    case danger
    case muted
}

/// The compact line a client overlay shows inside the composer.
///
/// The badge repeats the numbers of the panel in one line: the model, the
/// remaining quota and the state of the current session.
public struct ClientBadge: Equatable, Sendable {
    /// The model the client runs, already formatted for display.
    public var model: String?
    /// The reasoning effort, already formatted for display.
    public var effort: String?
    /// The remaining weekly quota, in percent.
    public var quotaPercent: Int?
    /// A quota that is not a percentage, e.g. `¥12.34`.
    public var quotaText: String?
    /// The label of the quota: `额度` for a percentage, `余额` for money.
    public var quotaLabel: String
    /// The state of the session, e.g. `45 tok/s` or `会话 —`.
    public var session: String?
    /// The tone of the quota.
    public var tone: ClientBadgeTone

    public init(
        model: String? = nil,
        effort: String? = nil,
        quotaPercent: Int? = nil,
        quotaText: String? = nil,
        quotaLabel: String = "额度",
        session: String? = nil,
        tone: ClientBadgeTone = .normal
    ) {
        self.model = model
        self.effort = effort
        self.quotaPercent = quotaPercent
        self.quotaText = quotaText
        self.quotaLabel = quotaLabel
        self.session = session
        self.tone = tone
    }

    /// Whether the badge carries a value worth showing.
    public var hasContent: Bool {
        model != nil || quotaPercent != nil || quotaText != nil || session != nil
    }
}

/// The labels of a badge.
///
/// The raw values of the session log are not labels: `gpt-6.1-sol` is shown
/// as `GPT-6.1 Sol` and `xhigh` as `极高`.
public enum ClientBadgeFormatter {
    /// The model as it is shown in the badge.
    public static func modelLabel(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if let slash = value.lastIndex(of: "/") {
            value = String(value[value.index(after: slash)...])
        }
        let tokens = value.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
        var parts: [String] = []
        for token in tokens {
            let lower = token.lowercased()
            let label: String
            if lower == "gpt" || lower == "api" {
                label = lower.uppercased()
            } else if lower == "deepseek" {
                label = "DeepSeek"
            } else if lower == "minimax" {
                label = "MiniMax"
            } else if let first = token.first {
                label = first.uppercased() + token.dropFirst()
            } else {
                label = token
            }
            // The version belongs to the family: `gpt-6.1-sol` is one name,
            // not `GPT 6.1 Sol`.
            if parts.last == "GPT", token.first?.isNumber == true {
                parts[parts.count - 1] = "GPT-" + label
            } else {
                parts.append(label)
            }
        }
        return parts.joined(separator: " ")
    }

    /// The effort as it is shown in the badge.
    public static func effortLabel(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        switch value.lowercased() {
        case "minimal": return "极低"
        case "low": return "低"
        case "medium": return "中"
        case "high": return "高"
        case "xhigh", "extrahigh", "extra-high": return "极高"
        case "max": return "Max"
        case "thinking": return "思考"
        default: return value
        }
    }

    /// The state of the session as it is shown in the badge.
    public static func sessionLabel(isActive: Bool, rate: Double?) -> String {
        guard isActive else { return "会话 —" }
        guard let rate, rate > 0 else { return "生成中" }
        return "\(Int(rate.rounded())) tok/s"
    }

    /// The tone of a quota; a degraded model raises the tone as well.
    public static func tone(quotaPercent: Int?, health: HealthStatus? = nil) -> ClientBadgeTone {
        if let quotaPercent {
            if quotaPercent < 10 { return .danger }
            if quotaPercent < 30 { return .warn }
        }
        switch health {
        case .degraded: return .danger
        case .suspected: return .warn
        default: return .normal
        }
    }
}

extension UsageSnapshot {
    /// The badge of the Codex client.
    ///
    /// The values come from the same snapshot as the menu bar and the panel,
    /// so the overlay never shows a second, differently aged number.
    public var codexBadge: ClientBadge? {
        let badge = ClientBadge(
            model: ClientBadgeFormatter.modelLabel(session.model),
            effort: ClientBadgeFormatter.effortLabel(session.effort),
            quotaPercent: quota.weeklyRemainingPercent,
            session: ClientBadgeFormatter.sessionLabel(
                isActive: session.isActive,
                rate: session.outputTokensPerSecond
            ),
            tone: ClientBadgeFormatter.tone(
                quotaPercent: quota.weeklyRemainingPercent,
                health: health.status
            )
        )
        return badge.hasContent ? badge : nil
    }
}
