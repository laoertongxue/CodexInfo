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
        guard let observation = root["completion_observation"] as? [String: Any] else { return [] }
        let confirmation = observation["confirmation_level"] as? String ?? ""
        let status = observation["status"] as? String ?? ""
        guard status == "completed" || confirmation.contains("confirmed") else { return [] }
        let window = root["window"] as? [String: Any]
        let urlString = observation["announcement_url"] as? String
            ?? window?["source_url"] as? String
        let publishedAt = DateParsing.iso8601(observation["occurred_at"] as? String)
            ?? DateParsing.iso8601(observation["occurred_on"] as? String)
            ?? DateParsing.iso8601(root["monitored_at"] as? String)
        let title = observation["title_zh"] as? String ?? "Codex 重置完成"
        return [ResetSignal(
            id: "\(id):\(title):\(observation["occurred_on"] as? String ?? "")",
            sourceId: id,
            sourceName: displayName,
            kind: .reset,
            severity: confirmation.contains("stationmaster") ? "strong" : nil,
            title: title,
            summary: observation["evidence_zh"] as? String ?? "",
            publishedAt: publishedAt,
            url: urlString.flatMap(URL.init(string:)),
            verified: true,
            scope: window?["scope"] as? String ?? "Codex 用户",
            confirmingSources: [displayName]
        )]
    }
}
