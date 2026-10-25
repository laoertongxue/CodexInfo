import Foundation

/// The public Codex Resets service (`codex-reset.com`).
///
/// `/api/feed` publishes the timeline of the reset account and is the only
/// endpoint that can carry a reset claim; `/api/status` publishes the service
/// health only and never proves a quota reset.
public struct CodexResetsSource: ResetSource {
    public let id = "codex-resets"
    public let displayName = "Codex Resets"

    public init() {}

    public func fetch(using http: HTTPClient, now: Date) async throws -> [ResetSignal] {
        var feedRequest = URLRequest(url: URL(string: "https://codex-reset.com/api/feed")!)
        feedRequest.httpMethod = "GET"
        feedRequest.timeoutInterval = 10
        feedRequest.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
        let feedResponse = try await http.send(feedRequest)
        guard (200..<300).contains(feedResponse.statusCode) else { throw HTTPError.status(feedResponse.statusCode) }
        guard let root = try JSONSerialization.jsonObject(with: feedResponse.data) as? [String: Any] else { return [] }

        var signals: [ResetSignal] = []
        // The signal block is an announcement. Its severity is only used when
        // the payload publishes one, and a stale or inactive signal is dropped.
        if let signal = root["signal"] as? [String: Any],
           let summary = signal["summary"] as? String,
           (root["stale"] as? Bool) != true,
           (signal["active"] as? Bool) != false {
            signals.append(ResetSignal(
                id: "\(id):signal:\(signal["tweet_id"] as? String ?? summary)",
                sourceId: id, sourceName: displayName, kind: .verifying,
                severity: signal["severity"] as? String,
                title: summary, summary: summary,
                publishedAt: DateParsing.iso8601(signal["at"] as? String),
                url: (signal["url"] as? String).flatMap(URL.init(string:)),
                verified: false, scope: "Codex 用户", confirmingSources: [displayName],
                rawHash: PayloadHash.short(feedResponse.data)
            ))
        }
        for tweet in root["tweets"] as? [[String: Any]] ?? [] {
            // A `signal` tweet is a forecast even when the payload does not
            // mark it as an explicit reset claim (`By midnight PST`).
            let explicitClaim = (tweet["explicit_reset_claim"] as? Bool) == true
            let isSignal = (tweet["kind"] as? String) == "signal"
            guard explicitClaim || isSignal,
                  let text = tweet["text"] as? String else { continue }
            let verified = explicitClaim && Self.isConfirmed(tweet["reset_verification_status"] as? String)
            // A claim that the payload does not confirm is still a claim, not
            // a completed reset.
            let kind: ResetSignalKind = verified ? .reset : .verifying
            signals.append(ResetSignal(
                id: "\(id):tweet:\(tweet["id"] as? String ?? text)",
                sourceId: id, sourceName: displayName, kind: kind, severity: verified ? "strong" : nil,
                title: text.components(separatedBy: "\n").first ?? text,
                summary: text,
                publishedAt: DateParsing.iso8601(tweet["at"] as? String),
                url: (tweet["url"] as? String).flatMap(URL.init(string:)),
                verified: verified, scope: "Codex 用户", confirmingSources: [displayName],
                rawHash: PayloadHash.short(feedResponse.data)
            ))
        }

        // The status endpoint only reports the service health. Its failure
        // degrades the source but must not take the whole source down, so the
        // error is swallowed here and published as a degraded status.
        var statusRequest = URLRequest(url: URL(string: "https://codex-reset.com/api/status")!)
        statusRequest.httpMethod = "GET"
        statusRequest.timeoutInterval = 10
        statusRequest.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
        if let statusResponse = try? await http.send(statusRequest),
           (200..<300).contains(statusResponse.statusCode),
           let status = try? JSONSerialization.jsonObject(with: statusResponse.data) as? [String: Any] {
            let description = status["description"] as? String ?? "Unknown"
            let indicator = status["indicator"] as? String ?? "unknown"
            let codex = status["codex"] as? String ?? indicator
            let degraded = status["degraded"] as? Bool == true || codex != "operational"
            signals.append(ResetSignal(
                id: "\(id):status:\(indicator):\(codex)",
                sourceId: id, sourceName: displayName, kind: .status,
                severity: degraded ? "incident" : nil,
                title: "Codex Resets 服务状态：\(description)",
                summary: description,
                publishedAt: DateParsing.iso8601(status["checked_at"] as? String) ?? now,
                url: URL(string: "https://codex-reset.com/"),
                verified: false, scope: "所有用户", confirmingSources: [displayName],
                rawHash: PayloadHash.short(statusResponse.data)
            ))
        } else {
            signals.append(ResetSignal(
                id: "\(id):status:unavailable",
                sourceId: id, sourceName: displayName, kind: .status,
                severity: "degraded",
                title: "Codex Resets 服务状态不可用",
                summary: "/api/status 没有返回可读的服务状态",
                publishedAt: now,
                url: URL(string: "https://codex-reset.com/"),
                verified: false, scope: "所有用户", confirmingSources: [displayName],
                rawHash: nil
            ))
        }
        return signals
    }

    /// A tweet counts as confirmed only when the payload says so.
    ///
    /// The status is compared exactly, so a level such as `unconfirmed` or
    /// `not_confirmed` never reads as a confirmation.
    static func isConfirmed(_ status: String?) -> Bool {
        status?.lowercased() == "confirmed"
    }
}
