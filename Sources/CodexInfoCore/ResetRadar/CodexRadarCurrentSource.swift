import Foundation

/// The public summary of the AI sentinel site (`codexradar.com/current.json`).
///
/// The site publishes one record at a time. The adapter only reports a reset
/// when the record itself says the reset is confirmed; an announced but
/// unconfirmed window produces no signal.
public struct CodexRadarCurrentSource: ResetSource {
    public let id = "ai-sentinel-records"
    public let displayName = "AI 哨兵记录"

    public init() {}

    public func fetch(using http: HTTPClient, now: Date) async throws -> [ResetSignal] {
        var request = URLRequest(url: URL(string: "https://codexradar.com/current.json")!)
        request.timeoutInterval = 10
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
        let response = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else { throw HTTPError.status(response.statusCode) }
        guard let root = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else { return [] }

        let window = root["window"] as? [String: Any]
        let timeZone = Self.timeZone(from: root["timezone"] as? String)
        guard let record = (root["completion_observation"] as? [String: Any]) ?? window.flatMap(Self.windowRecord) else { return [] }

        let confirmation = record["confirmation_level"] as? String ?? ""
        let status = record["status"] as? String ?? ""
        guard Self.isConfirmed(status: status, confirmation: confirmation) else { return [] }

        let urlString = record["announcement_url"] as? String
            ?? record["source_url"] as? String
            ?? window?["source_url"] as? String
        let publishedAt = DateParsing.iso8601(record["occurred_at"] as? String)
            ?? DateParsing.dateOnly(record["occurred_on"] as? String, timeZone: timeZone)
            ?? DateParsing.iso8601(root["monitored_at"] as? String)
        let title = record["title_zh"] as? String ?? "Codex 重置完成"
        let summary = record["evidence_zh"] as? String ?? record["message"] as? String ?? ""
        let scope = window?["scope"] as? String ?? "Codex 用户"
        let eventID = (record["event_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let identity = eventID ?? "\(title):\(record["occurred_on"] as? String ?? "")"
        return [ResetSignal(
            id: "\(id):\(identity)",
            sourceId: id,
            sourceName: displayName,
            kind: .reset,
            severity: confirmation.contains("stationmaster") ? "strong" : nil,
            title: title,
            summary: summary,
            publishedAt: publishedAt,
            url: urlString.flatMap(URL.init(string:)),
            verified: true,
            scope: scope,
            confirmingSources: [displayName],
            rawHash: PayloadHash.short(response.data)
        )]
    }

    /// A record counts as confirmed only when the payload says so.
    ///
    /// The site writes levels such as `stationmaster_confirmed`, but a negated
    /// level (`unconfirmed`, `not_confirmed`) must never be read as a
    /// confirmation.
    static func isConfirmed(status: String, confirmation: String) -> Bool {
        let level = confirmation.lowercased()
        guard !level.isEmpty else { return status == "completed" }
        guard !level.hasPrefix("un"), !level.hasPrefix("not_"),
              !level.contains("unconfirmed"), !level.contains("not_confirmed") else { return false }
        return level == "confirmed" || level.hasSuffix("_confirmed")
    }

    /// The window block carries the same fields when no completion record exists.
    static func windowRecord(_ window: [String: Any]) -> [String: Any]? {
        guard window["status"] != nil || window["confirmation_level"] != nil else { return nil }
        return [
            "status": window["status"] as? String ?? "",
            "confirmation_level": window["confirmation_level"] as? String ?? "",
            "occurred_on": window["occurred_on"] as? String ?? "",
            "event_id": window["event_id"] as? String ?? "",
            "title_zh": window["title"] as? String ?? "",
            "message": window["message"] as? String ?? "",
            "source_url": window["source_url"] as? String ?? "",
        ]
    }

    /// The time zone the payload publishes, with the local zone as fallback.
    static func timeZone(from identifier: String?) -> TimeZone? {
        guard let identifier, !identifier.isEmpty else { return nil }
        return TimeZone(identifier: identifier)
    }
}
