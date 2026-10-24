import Foundation

/// The official OpenAI service status (`status.openai.com`).
///
/// The source reports service health only. It never claims a quota reset, so
/// its signal is always `.status` and never verified.
public struct OpenAIStatusSource: ResetSource {
    public let id = "openai-status"
    public let displayName = "官方状态"

    public init() {}

    public func fetch(using http: HTTPClient, now: Date) async throws -> [ResetSignal] {
        var request = URLRequest(url: URL(string: "https://status.openai.com/api/v2/summary.json")!)
        request.timeoutInterval = 10
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
        let response = try await http.send(request)
        guard (200..<300).contains(response.statusCode) else { throw HTTPError.status(response.statusCode) }
        guard let root = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let status = root["status"] as? [String: Any] else { return [] }
        let indicator = status["indicator"] as? String ?? "unknown"
        let description = status["description"] as? String ?? "Unknown"
        return [ResetSignal(
            id: "\(id):\(indicator):\(now.timeIntervalSince1970)",
            sourceId: id,
            sourceName: displayName,
            kind: .status,
            severity: indicator == "none" ? nil : "strong",
            title: "OpenAI 服务状态：\(description)",
            summary: "服务状态指示灯：\(indicator)",
            publishedAt: now,
            url: URL(string: "https://status.openai.com/"),
            verified: false,
            scope: "所有用户",
            confirmingSources: [displayName]
        )]
    }
}
