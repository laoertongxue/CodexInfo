import Foundation

/// The tone of a client panel: the quota is plain, low or critical.
public enum ClientBadgeTone: String, Codable, Equatable, Sendable {
    case normal
    case warn
    case danger
    case muted
}

/// The labels of a client panel.
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
