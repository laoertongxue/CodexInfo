import Foundation

/// The parts the menu bar title is built from.
///
/// The user picks the parts in the settings, so every part of the title is
/// named instead of being an anonymous string.
public enum StatusSegment: String, Codable, CaseIterable, Hashable, Sendable {
    /// The remaining weekly quota.
    case quota
    /// The output rate of the current session.
    case rate
    /// The local model-health verdict.
    case health
    /// The number of the available reset credits.
    case credits
    /// The moment the snapshot was built.
    case updated
}

/// The colour of a part of the menu bar title.
///
/// The colours only hint at the state of the value; they never change the
/// value itself.
public enum StatusColor: String, Codable, Hashable, Sendable {
    /// A plain value without a warning.
    case normal
    /// A healthy value.
    case good
    /// A value that deserves attention.
    case warn
    /// A value that is in danger.
    case danger
    /// A value that is not known.
    case muted
}

/// One part of the menu bar title.
public struct StatusTitlePart: Equatable, Hashable, Sendable {
    /// The text of the part.
    public let text: String
    /// The colour of the text.
    public let color: StatusColor

    public init(text: String, color: StatusColor) {
        self.text = text
        self.color = color
    }
}

/// The title of the menu bar item.
///
/// The parts keep their colours, so the app can build an attributed string
/// out of them instead of a plain text.
public struct StatusTitle: Equatable, Sendable {
    /// The parts of the title, in the order they are shown.
    public let parts: [StatusTitlePart]

    public init(parts: [StatusTitlePart]) {
        self.parts = parts
    }

    /// The title as one text.
    public var text: String {
        parts.map(\.text).joined(separator: " · ")
    }
}

/// Builds the title of the menu bar item.
///
/// A value that is not known is shown as `—` and never as a zero, so a missing
/// number never looks like a real one.
public enum StatusTitleFormatter {
    /// The weekly quota below which the title turns red.
    public static let dangerQuotaPercent = 10
    /// The weekly quota below which the title turns orange.
    public static let warnQuotaPercent = 30

    /// Formats the given parts of a snapshot.
    ///
    /// - Parameters:
    ///   - snapshot: the snapshot the title is built from.
    ///   - segments: the parts of the title, in the order they are shown.
    public static func format(
        _ snapshot: UsageSnapshot,
        segments: [StatusSegment] = [.quota, .rate, .health]
    ) -> StatusTitle {
        StatusTitle(parts: segments.map { part($0, of: snapshot) })
    }

    /// Formats one part of the title.
    private static func part(_ segment: StatusSegment, of snapshot: UsageSnapshot) -> StatusTitlePart {
        switch segment {
        case .quota:
            guard let value = snapshot.quota.weeklyRemainingPercent else {
                return StatusTitlePart(text: "—", color: .muted)
            }
            let color: StatusColor
            if value < dangerQuotaPercent {
                color = .danger
            } else if value < warnQuotaPercent {
                color = .warn
            } else {
                color = .good
            }
            return StatusTitlePart(text: "\(value)%", color: color)
        case .rate:
            guard let value = snapshot.session.outputTokensPerSecond else {
                return StatusTitlePart(text: "—", color: .muted)
            }
            return StatusTitlePart(text: String(format: "%.0f tok/s", value), color: .normal)
        case .health:
            switch snapshot.health.status {
            case .normal:
                return StatusTitlePart(text: "正常", color: .good)
            case .suspected:
                return StatusTitlePart(text: "疑似", color: .warn)
            case .degraded:
                return StatusTitlePart(text: "异常", color: .danger)
            case .insufficient:
                return StatusTitlePart(text: "数据不足", color: .muted)
            }
        case .credits:
            let count = snapshot.resetCredits.availableCount
            return StatusTitlePart(text: "\(count) 卡", color: count > 0 ? .good : .muted)
        case .updated:
            let text = snapshot.generatedAt.formatted(date: .omitted, time: .shortened)
            return StatusTitlePart(text: text, color: .muted)
        }
    }
}
