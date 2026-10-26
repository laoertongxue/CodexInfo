import Foundation
import CodexInfoCore

/// The MiniMax Code coding-plan quota.
///
/// The app stores a plain OAuth token for its own backend. The token only
/// goes to the MiniMax origin, and only the weekly remaining percentage of
/// the answer is shown.
public struct MiniMaxUsageProvider: Sendable {
    private let authURL: URL
    private let configURL: URL
    private let http: any HTTPClient
    private let baseURL: URL
    private let now: @Sendable () -> Date

    /// Creates the provider.
    ///
    /// - Parameters:
    ///   - authURL: the OAuth store of the app.
    ///   - configURL: the model settings of the app.
    ///   - http: the client of the request.
    ///   - baseURL: the open platform origin.
    ///   - now: the clock that checks the expiry of the token.
    public init(
        authURL: URL = MiniMaxUsageProvider.defaultAuthURL,
        configURL: URL = MiniMaxUsageProvider.defaultConfigURL,
        http: any HTTPClient,
        baseURL: URL = URL(string: "https://www.minimaxi.com")!,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.authURL = authURL
        self.configURL = configURL
        self.http = http
        self.baseURL = baseURL
        self.now = now
    }

    /// The OAuth store of MiniMax Code (CN).
    public static var defaultAuthURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".minimax", isDirectory: true)
            .appendingPathComponent("auth", isDirectory: true)
            .appendingPathComponent("prod", isDirectory: true)
            .appendingPathComponent("cn", isDirectory: true)
            .appendingPathComponent("mcode-public", isDirectory: true)
            .appendingPathComponent("auth.json")
    }

    /// The model settings of MiniMax Code (CN).
    public static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".minimax", isDirectory: true)
            .appendingPathComponent("config.yaml")
    }

    /// The panel data of the coding plan.
    public func snapshot() async -> ClientUsageSnapshot? {
        let settings = MiniMaxSettings.read(from: configURL)
        let moment = now()
        guard let token = MiniMaxCredentials.read(from: authURL, now: moment) else {
            return unavailable(settings: settings, at: moment)
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/api/openplatform/coding_plan/remains"))
        request.httpMethod = "GET"
        request.timeoutInterval = AppConstants.clientUsageTimeoutSeconds
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let response = try await http.send(request)
            guard response.statusCode == 200,
                  let reading = MiniMaxQuota.reading(response.data) else {
                return unavailable(settings: settings, at: moment)
            }
            let resetCards = await fetchResetCards(token: token)
            return ClientUsageSnapshot(
                client: "miniMaxCode",
                name: "MiniMax",
                quotaPercent: reading.weeklyPercent,
                quotaLabel: "额度",
                detail: reading.intervalPercent.map { "5 小时窗口 \($0)%" },
                resetsAt: reading.weeklyResetsAt,
                resetLabel: "重置",
                model: settings.model,
                effort: settings.effort,
                source: "官方额度接口",
                updatedAt: moment,
                tone: ClientBadgeFormatter.tone(quotaPercent: reading.weeklyPercent),
                note: "5 小时与周额度来自官方接口；只读展示。",
                resetCards: resetCards?.cards,
                resetCardTotal: resetCards?.total,
                limits: reading.limits
            )
        } catch {
            return unavailable(settings: settings, at: moment)
        }
    }

    /// The available usage-reset cards of the account.
    ///
    /// The list endpoint already excludes used cards (the used one is only in
    /// the flows); the panel only shows the count and the expiry, never uses
    /// a card.
    private func fetchResetCards(token: String) async -> MiniMaxResetCards? {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("backend/account/reset_card/list"),
            resolvingAgainstBaseURL: false
        ) else { return nil }
        components.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "size", value: "20"),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = AppConstants.clientUsageTimeoutSeconds
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let response = try await http.send(request)
            guard response.statusCode == 200 else { return nil }
            return MiniMaxResetCards.parse(response.data)
        } catch {
            return nil
        }
    }

    private func unavailable(settings: MiniMaxSettings, at moment: Date) -> ClientUsageSnapshot {
        ClientUsageSnapshot(
            client: "miniMaxCode",
            name: "MiniMax",
            quotaLabel: "额度",
            model: settings.model,
            effort: settings.effort,
            source: "官方额度接口",
            updatedAt: moment,
            tone: .muted,
            note: "额度接口暂不可用；检查 MiniMax Code 的登录状态。"
        )
    }
}

/// The OAuth token of the MiniMax app.
enum MiniMaxCredentials {
    /// The token of the first `mcode.oauth` record that has not expired.
    ///
    /// - Parameters:
    ///   - url: the `auth.json` of the app.
    ///   - now: the moment the token has to be valid.
    static func read(from url: URL, now: Date) -> String? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = root["records"] as? [String: Any] else {
            return nil
        }
        for (key, value) in records where key.contains("mcode.oauth") {
            guard let record = value as? [String: Any],
                  let token = record["accessToken"] as? String,
                  !token.isEmpty else { continue }
            if let expires = number(record["expiresAtMs"]), expires > 0 {
                let expiry = Date(timeIntervalSince1970: expires / 1000)
                if expiry <= now { continue }
            }
            return token
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}

/// The model settings of MiniMax Code.
struct MiniMaxSettings: Equatable, Sendable {
    var model: String?
    var effort: String?

    static func read(from url: URL) -> MiniMaxSettings {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return MiniMaxSettings()
        }
        var model: String?
        var effort: String?
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("defaultModel:") {
                let raw = value(after: "defaultModel:", in: line)
                model = ClientBadgeFormatter.modelLabel(raw.replacingOccurrences(of: "minimax/", with: ""))
            } else if line.hasPrefix("defaultModelVariant:") {
                effort = ClientBadgeFormatter.effortLabel(value(after: "defaultModelVariant:", in: line))
            } else if line.hasPrefix("defaultModelThinking:"), effort == nil {
                effort = ClientBadgeFormatter.effortLabel(value(after: "defaultModelThinking:", in: line))
            }
        }
        return MiniMaxSettings(model: model, effort: effort)
    }

    private static func value(after key: String, in line: String) -> String {
        let raw = line.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        if raw.count >= 2,
           (raw.hasPrefix("\"") && raw.hasSuffix("\"")) || (raw.hasPrefix("'") && raw.hasSuffix("'")) {
            return String(raw.dropFirst().dropLast())
        }
        return raw
    }
}

/// The reset card list answer.
struct MiniMaxResetCards: Equatable, Sendable {
    var cards: [ClientResetCard]
    var total: Int

    static func parse(_ data: Data) -> MiniMaxResetCards? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base = root["base_resp"] as? [String: Any],
              number(base["status_code"]) == 0 else {
            return nil
        }
        let rawCards = root["cards"] as? [[String: Any]] ?? []
        let cards = rawCards.compactMap { card -> ClientResetCard? in
            guard let id = string(card["card_id"]) else { return nil }
            let source = card["source_type"] as? String
            return ClientResetCard(
                id: id,
                source: source,
                label: source == "mcode_signin" ? "完全重置" : source,
                expiresAt: date(card["expire_time"]),
                grantedAt: date(card["create_time"])
            )
        }
        let reported = Int(number(root["total"]) ?? Double(cards.count))
        return MiniMaxResetCards(cards: cards, total: max(reported, cards.count))
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func date(_ value: Any?) -> Date? {
        guard let milliseconds = number(value), milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}

/// The coding plan remains answer.
struct MiniMaxQuotaReading: Equatable, Sendable {
    var weeklyPercent: Int
    var intervalPercent: Int?
    var weeklyResetsAt: Date?
    var intervalResetsAt: Date?
    /// The weekly boost in permille; `1500` is a 150-point week.
    var weeklyBoostPermille: Int?
    /// The 5-hour boost in permille; the API usually omits it.
    var intervalBoostPermille: Int?

    /// The 5-hour and the weekly window as used / total points.
    var limits: [ClientQuotaLimit] {
        var limits: [ClientQuotaLimit] = []
        if let intervalPercent {
            let total = Self.totalPoints(boostPermille: intervalBoostPermille)
            let remaining = Int((Double(intervalPercent) * Double(total) / 100).rounded())
            limits.append(
                ClientQuotaLimit(
                    id: "fiveHour",
                    label: "5 小时限额",
                    usedPoints: max(0, total - remaining),
                    totalPoints: total,
                    resetAt: intervalResetsAt
                )
            )
        }
        let weeklyTotal = Self.totalPoints(boostPermille: weeklyBoostPermille)
        let weeklyRemaining = Int((Double(weeklyPercent) * Double(weeklyTotal) / 100).rounded())
        limits.append(
            ClientQuotaLimit(
                id: "weekly",
                label: "周限额",
                usedPoints: max(0, weeklyTotal - weeklyRemaining),
                totalPoints: weeklyTotal,
                resetAt: weeklyResetsAt
            )
        )
        return limits
    }

    private static func totalPoints(boostPermille: Int?) -> Int {
        guard let boostPermille, boostPermille > 0 else { return 100 }
        return max(1, boostPermille / 10)
    }
}

enum MiniMaxQuota {
    /// The weekly remaining percentage of the general model.
    static func reading(_ data: Data) -> MiniMaxQuotaReading? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let remains = root["model_remains"] as? [[String: Any]] else {
            return nil
        }
        let general = remains.first { ($0["model_name"] as? String) == "general" }
        guard let general,
              let weekly = number(general["current_weekly_remaining_percent"]) else {
            // A video model or a 5-hour value must not be shown as the
            // general weekly quota.
            return nil
        }
        return MiniMaxQuotaReading(
            weeklyPercent: Int(min(max(weekly, 0), 100).rounded()),
            intervalPercent: number(general["current_interval_remaining_percent"]).map {
                Int(min(max($0, 0), 100).rounded())
            },
            weeklyResetsAt: milliseconds(general["weekly_end_time"]),
            intervalResetsAt: milliseconds(general["end_time"]),
            weeklyBoostPermille: integer(general["weekly_boost_permille"]),
            intervalBoostPermille: integer(general["interval_boost_permille"])
        )
    }

    private static func milliseconds(_ value: Any?) -> Date? {
        guard let number = number(value), number > 0 else { return nil }
        return Date(timeIntervalSince1970: number / 1000)
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = number(value), number > 0 else { return nil }
        return Int(number.rounded())
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
