import Foundation
import CodexInfoCore

/// The DeepSeek Harness balance.
///
/// The harness stores a platform grant in `~/.dsh/.credentials.yaml`. The
/// token only leaves the machine to its issuer, and only the balance strings
/// of the answer are shown.
public struct DeepSeekUsageProvider: Sendable {
    private let credentialsURL: URL
    private let settingsURL: URL
    private let http: any HTTPClient
    private let baseURL: URL

    /// Creates the provider.
    ///
    /// - Parameters:
    ///   - credentialsURL: the grant store of the harness.
    ///   - settingsURL: the model settings of the harness.
    ///   - http: the client of the request.
    ///   - baseURL: the platform origin the grant was issued for.
    public init(
        credentialsURL: URL = DeepSeekUsageProvider.defaultCredentialsURL,
        settingsURL: URL = DeepSeekUsageProvider.defaultSettingsURL,
        http: any HTTPClient,
        baseURL: URL = URL(string: "https://platform.deepseek.com")!
    ) {
        self.credentialsURL = credentialsURL
        self.settingsURL = settingsURL
        self.http = http
        self.baseURL = baseURL
    }

    /// The grant store of the harness.
    public static var defaultCredentialsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dsh", isDirectory: true)
            .appendingPathComponent(".credentials.yaml")
    }

    /// The model settings of the harness.
    public static var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dsh", isDirectory: true)
            .appendingPathComponent("settings.yaml.imported")
    }

    /// The panel data of the wallet.
    public func snapshot() async -> ClientUsageSnapshot? {
        let settings = DeepSeekSettings.read(from: settingsURL)
        guard let token = DeepSeekCredentials.read(from: credentialsURL) else {
            return unavailable(settings: settings)
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v0/users/get_user_summary"))
        request.httpMethod = "GET"
        request.timeoutInterval = AppConstants.clientUsageTimeoutSeconds
        request.setValue(token, forHTTPHeaderField: "x-dsh-auth-token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let response = try await http.send(request)
            guard response.statusCode == 200,
                  let balance = DeepSeekBalance.parse(response.data) else {
                return unavailable(settings: settings)
            }
            return ClientUsageSnapshot(
                client: "deepSeekHarness",
                name: "DeepSeek",
                quotaText: balance.text,
                quotaLabel: "余额",
                model: settings.model,
                effort: settings.effort,
                source: "官方钱包",
                updatedAt: Date(),
                tone: balance.tone,
                note: "余额为钱包可用金额（含赠送）。"
            )
        } catch {
            return unavailable(settings: settings)
        }
    }

    /// The overlay badge of the wallet.
    public func badge() async -> ClientBadge? {
        await snapshot()?.badge
    }

    private func unavailable(settings: DeepSeekSettings) -> ClientUsageSnapshot {
        ClientUsageSnapshot(
            client: "deepSeekHarness",
            name: "DeepSeek",
            quotaLabel: "余额",
            model: settings.model,
            effort: settings.effort,
            source: "官方钱包",
            updatedAt: Date(),
            tone: .muted,
            note: "余额接口暂不可用；检查 DeepSeek Harness 的登录状态。"
        )
    }
}

/// The platform grant of the harness.
enum DeepSeekCredentials {
    /// The token of the default account record.
    ///
    /// The file is a small YAML document; the reader follows the one record
    /// the harness uses instead of pulling in a YAML dependency.
    ///
    /// - Parameter url: the `.credentials.yaml` of the harness.
    /// - Returns: the token, or `nil` when the record is missing or points at
    ///   another issuer.
    static func read(from url: URL) -> String? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var inRecord = false
        var recordIndent = 0
        var token: String?
        var issuer: String?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let indent = line.prefix { $0 == " " }.count
            if trimmed.hasPrefix("deepseek-account-platform/default:") {
                inRecord = true
                recordIndent = indent
                token = nil
                issuer = nil
                continue
            }
            guard inRecord else { continue }
            if indent <= recordIndent { break }
            if trimmed.hasPrefix("token:") {
                token = value(after: "token:", in: trimmed)
            } else if trimmed.hasPrefix("issuer:") {
                issuer = value(after: "issuer:", in: trimmed)
            }
        }
        guard let token, !token.isEmpty else { return nil }
        // The grant is only used for the issuer it was written for; a record
        // without an issuer is refused instead of sending the token blindly.
        guard let issuer,
              let url = URL(string: issuer),
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "platform.deepseek.com" else {
            return nil
        }
        return token
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

/// The model settings of the harness.
struct DeepSeekSettings: Equatable, Sendable {
    var model: String?
    var effort: String?

    static func read(from url: URL) -> DeepSeekSettings {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return DeepSeekSettings()
        }
        var inBlock = false
        var blockIndent = 0
        var model: String?
        var effort: String?
        for rawLine in text.split(separator: "\n") {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let indent = line.prefix { $0 == " " }.count
            if trimmed.hasPrefix("agent-default-model:") {
                inBlock = true
                blockIndent = indent
                continue
            }
            guard inBlock else { continue }
            if indent <= blockIndent { break }
            if trimmed.hasPrefix("model:") {
                model = ClientBadgeFormatter.modelLabel(value(after: "model:", in: trimmed))
            } else if trimmed.hasPrefix("reasoningEffort:") {
                effort = ClientBadgeFormatter.effortLabel(value(after: "reasoningEffort:", in: trimmed))
            }
        }
        return DeepSeekSettings(model: model, effort: effort)
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

/// The balance of the platform answer.
struct DeepSeekBalance: Equatable, Sendable {
    var text: String
    var tone: ClientBadgeTone

    /// Reads the wallets of the summary answer.
    static func parse(_ data: Data) -> DeepSeekBalance? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let biz = payload["biz_data"] as? [String: Any] else {
            return nil
        }
        var totals: [String: Double] = [:]
        for key in ["normal_wallets", "bonus_wallets"] {
            guard let wallets = biz[key] as? [[String: Any]] else { continue }
            for wallet in wallets {
                guard let currency = wallet["currency"] as? String,
                      let raw = wallet["balance"] as? String,
                      let amount = Double(raw) else { continue }
                totals[currency, default: 0] += amount
            }
        }
        guard !totals.isEmpty else { return nil }
        let currency: String
        if totals["CNY"] != nil {
            currency = "CNY"
        } else if totals["USD"] != nil {
            currency = "USD"
        } else {
            currency = totals.keys.sorted()[0]
        }
        let amount = totals[currency] ?? 0
        let symbol: String
        switch currency {
        case "CNY": symbol = "¥"
        case "USD": symbol = "$"
        default: symbol = currency + " "
        }
        let text = symbol + String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), amount)
        let tone: ClientBadgeTone = amount <= 0 ? .danger : (amount < 5 ? .warn : .normal)
        return DeepSeekBalance(text: text, tone: tone)
    }
}
