import Foundation
import CodexInfoCore

/// The OpenCode Go, Zen and free-model state.
///
/// The Go API key is read from the app's own auth store and only sent to
/// `opencode.ai`. The optional Zen console token is read from the quota
/// sidebar's user-private store and only sent to `console.opencode.ai`.
public struct OpenCodeUsageProvider: Sendable {
    public typealias FreeModels = @Sendable () async -> [String]

    private let authURL: URL
    private let zenTokenURL: URL
    private let goHTTP: any HTTPClient
    private let zenHTTP: any HTTPClient
    private let now: @Sendable () -> Date
    private let freeModels: FreeModels

    public init(
        authURL: URL = OpenCodeUsageProvider.defaultAuthURL,
        zenTokenURL: URL = OpenCodeUsageProvider.defaultZenTokenURL,
        goHTTP: any HTTPClient,
        zenHTTP: any HTTPClient,
        now: @escaping @Sendable () -> Date = { Date() },
        freeModels: FreeModels? = nil
    ) {
        self.authURL = authURL
        self.zenTokenURL = zenTokenURL
        self.goHTTP = goHTTP
        self.zenHTTP = zenHTTP
        self.now = now
        self.freeModels = freeModels ?? { await OpenCodeModelCatalog.shared.freeModels() }
    }

    /// The auth store of the OpenCode CLI.
    public static var defaultAuthURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/auth.json")
    }

    /// The console token store of the optional quota sidebar plugin.
    public static var defaultZenTokenURL: URL {
        let environment = ProcessInfo.processInfo.environment
        let stateHome = environment["XDG_STATE_HOME"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/state", isDirectory: true)
        return stateHome
            .appendingPathComponent("opencode", isDirectory: true)
            .appendingPathComponent("quota-sidebar", isDirectory: true)
            .appendingPathComponent("auth.json")
    }

    /// The panel data of the current OpenCode account.
    public func snapshot() async -> ClientUsageSnapshot? {
        let moment = now()
        let goKey = OpenCodeCredentials.goKey(from: authURL)
        var goWindows: [OpenCodeWindow]?
        var goState = "unavailable"
        var goNote: String?

        if let goKey {
            let outcome = await fetchGo(key: goKey)
            switch outcome {
            case .success(let windows):
                goWindows = windows
                goState = "active"
            case .expired:
                goState = "expired"
                goNote = "Go Key 已过期，请在 OpenCode Console 重新生成"
            case .failure:
                goNote = "Go 额度暂不可用"
            }
        } else {
            goNote = "未登录 OpenCode Go"
        }

        let zen = await fetchZen(now: moment)
        let models = await freeModels()
        let remaining = goWindows?.map { max(0, 100 - $0.usedPercent) }.min()
        let tone: ClientBadgeTone
        if let remaining {
            tone = ClientBadgeFormatter.tone(quotaPercent: remaining)
        } else {
            tone = .muted
        }

        return ClientUsageSnapshot(
            client: "openCode",
            name: "OpenCode",
            quotaPercent: remaining,
            quotaText: remaining == nil ? zen.balance : nil,
            quotaLabel: remaining != nil ? "Go 额度" : (zen.balance != nil ? "Zen 余额" : "额度"),
            source: "OpenCode Go / Zen",
            updatedAt: moment,
            tone: tone,
            openCode: OpenCodeUsage(
                goWindows: goWindows,
                goState: goState,
                goNote: goNote,
                zenBalance: zen.balance,
                zenState: zen.state,
                freeModels: models.isEmpty ? nil : models
            )
        )
    }

    private enum GoOutcome: Sendable {
        case success([OpenCodeWindow])
        case expired
        case failure
    }

    private func fetchGo(key: String) async -> GoOutcome {
        guard let url = URL(string: "https://opencode.ai/zen/go/v1/usage") else { return .failure }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = AppConstants.clientUsageTimeoutSeconds
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let response = try await goHTTP.send(request)
            if response.statusCode == 200, let windows = OpenCodeGoUsage.windows(from: response.data) {
                return .success(windows)
            }
            if response.statusCode == 401 || response.statusCode == 403
                || OpenCodeGoUsage.isExpired(response.data) {
                return .expired
            }
            return .failure
        } catch {
            return .failure
        }
    }

    private struct ZenOutcome: Sendable {
        var balance: String?
        var state: String
    }

    private func fetchZen(now: Date) async -> ZenOutcome {
        guard let stored = OpenCodeZenToken.read(from: zenTokenURL) else {
            return ZenOutcome(balance: nil, state: "signedOut")
        }
        let token = await zenAccessToken(stored: stored, now: now)
        guard let token else {
            return ZenOutcome(balance: nil, state: "signedOut")
        }
        guard let url = URL(string: "https://console.opencode.ai/api/billing/status") else {
            return ZenOutcome(balance: nil, state: "unavailable")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = AppConstants.clientUsageTimeoutSeconds
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let response = try await zenHTTP.send(request)
            guard response.statusCode == 200 else {
                if response.statusCode == 401 || response.statusCode == 403 {
                    return ZenOutcome(balance: nil, state: "signedOut")
                }
                return ZenOutcome(balance: nil, state: "unavailable")
            }
            guard let balance = OpenCodeZenBalance.parse(response.data) else {
                return ZenOutcome(balance: nil, state: "unavailable")
            }
            return ZenOutcome(balance: balance, state: "signedIn")
        } catch {
            return ZenOutcome(balance: nil, state: "unavailable")
        }
    }

    /// Uses the stored access token or refreshes it in memory.
    private func zenAccessToken(stored: OpenCodeZenToken, now: Date) async -> String? {
        if let expiry = stored.expires, expiry > now.addingTimeInterval(30), !stored.accessToken.isEmpty {
            return stored.accessToken
        }
        guard !stored.refreshToken.isEmpty else {
            return stored.expires == nil && !stored.accessToken.isEmpty ? stored.accessToken : nil
        }
        guard let url = URL(string: "https://console.opencode.ai/auth/device/token") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = AppConstants.clientUsageTimeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": stored.refreshToken,
            "client_id": "opencode",
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        do {
            let response = try await zenHTTP.send(request)
            guard response.statusCode == 200,
                  let parsed = try? JSONSerialization.jsonObject(with: response.data),
                  let object = parsed as? [String: Any],
                  let token = object["access_token"] as? String,
                  !token.isEmpty else {
                return nil
            }
            return token
        } catch {
            return nil
        }
    }
}

/// Reads the Go API key from the OpenCode auth store.
enum OpenCodeCredentials {
    static func goKey(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let record = root["opencode-go"] as? [String: Any],
              let key = record["key"] as? String,
              !key.isEmpty else {
            return nil
        }
        return key
    }
}

/// The console token file written by the optional quota sidebar plugin.
struct OpenCodeZenToken: Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expires: Date?

    static func read(from url: URL) -> OpenCodeZenToken? {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let access = object["accessToken"] as? String ?? ""
        let refresh = object["refreshToken"] as? String ?? ""
        guard !access.isEmpty || !refresh.isEmpty else { return nil }
        let expires = (object["expires"] as? NSNumber).map {
            Date(timeIntervalSince1970: $0.doubleValue / 1000)
        }
        return OpenCodeZenToken(
            accessToken: access,
            refreshToken: refresh,
            expires: expires
        )
    }
}

/// Parses the Go usage response.
enum OpenCodeGoUsage {
    static func windows(from data: Data) -> [OpenCodeWindow]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usage = root["usage"] as? [String: Any] else {
            return nil
        }
        let definitions: [(String, String)] = [
            ("rolling", "5 小时"),
            ("weekly", "周"),
            ("monthly", "月"),
        ]
        let windows = definitions.compactMap { key, label -> OpenCodeWindow? in
            guard let object = usage[key] as? [String: Any],
                  let percent = number(object["percent"]) else {
                return nil
            }
            return OpenCodeWindow(
                id: key,
                label: label,
                usedPercent: Int(min(max(percent, 0), 100).rounded()),
                resetAt: DateParsing.iso8601(object["resetsAt"] as? String)
            )
        }
        return windows.isEmpty ? nil : windows
    }

    static func isExpired(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if let error = root["error"] as? [String: Any],
           let code = error["code"] as? String {
            return code == "api_key_expired"
        }
        return false
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}

/// Parses the Zen billing response.
enum OpenCodeZenBalance {
    static func parse(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let micro: Double?
        if let value = number(root["availableMicroCents"]) {
            micro = value
        } else if let value = number(root["balanceMicroCents"]) {
            micro = value
        } else if let value = number(root["balance"]) {
            micro = value * 100_000_000
        } else {
            micro = nil
        }
        guard let micro else { return nil }
        let dollars = micro / 100_000_000
        guard dollars.isFinite else { return nil }
        return String(
            format: "$%.2f",
            locale: Locale(identifier: "en_US_POSIX"),
            dollars
        )
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}

/// Reads the free model IDs from the local OpenCode CLI.
///
/// The list is cached for ten minutes: spawning the CLI on every 30-second
/// panel refresh would be wasteful.
actor OpenCodeModelCatalog {
    static let shared = OpenCodeModelCatalog()

    private var cached: [String]?
    private var cachedAt: Date?

    func freeModels(now: Date = Date()) async -> [String] {
        if let cached, let cachedAt, now.timeIntervalSince(cachedAt) < 600 {
            return cached
        }
        let models = Self.read()
        cached = models
        cachedAt = now
        return models
    }

    private static func read() -> [String] {
        guard let binary = binaryURL() else { return [] }
        let process = Process()
        process.executableURL = binary
        process.arguments = ["models"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do {
            try process.run()
        } catch {
            return []
        }
        if done.wait(timeout: .now() + 5) == .timedOut {
            process.terminate()
            return []
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let lines = String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let free = lines.filter { line in
            line.contains("/")
                && !line.contains(" ")
                && line.lowercased().contains("free")
        }
        return Array(Set(free)).sorted()
    }

    private static func binaryURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".opencode/bin/opencode"),
            URL(fileURLWithPath: "/opt/homebrew/bin/opencode"),
            URL(fileURLWithPath: "/usr/local/bin/opencode"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
