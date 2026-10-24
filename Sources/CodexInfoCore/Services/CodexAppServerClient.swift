import Foundation

public protocol AppServerTransport: Sendable {
    func request(method: String, params: [String: Any]) async throws -> [String: Any]
    func notify(method: String, params: [String: Any]) async throws
    func close()
}

public enum AppServerError: Error, Equatable {
    case binaryNotFound
    case notRunning
    case invalidResponse
    case rpc(code: Int, message: String)
    case timeout
}

public struct AppServerRateLimits: Equatable, Sendable {
    public let rateLimits: RateLimitSnapshot?
    public let rateLimitsByLimitID: [String: RateLimitSnapshot]
}

public actor CodexAppServerClient {
    private let transport: AppServerTransport
    private var initialized = false

    public init(transport: AppServerTransport) {
        self.transport = transport
    }

    public func readRateLimits() async throws -> AppServerRateLimits {
        try await ensureInitialized()
        let result = try await transport.request(method: "account/rateLimits/read", params: [:])
        let snapshot = (result["rateLimits"] as? [String: Any]).flatMap(RateLimitPayloadDecoder.snapshot)
        let byID = (result["rateLimitsByLimitId"] as? [String: Any]).map(RateLimitPayloadDecoder.snapshotMap) ?? [:]
        return AppServerRateLimits(rateLimits: snapshot, rateLimitsByLimitID: byID)
    }

    private func ensureInitialized() async throws {
        guard !initialized else { return }
        _ = try await transport.request(method: "initialize", params: [
            "clientInfo": ["name": "CodexInfo", "title": "CodexInfo", "version": AppConstants.version],
            "capabilities": [
                "experimentalApi": false,
                "requestAttestation": false,
                "optOutNotificationMethods": [],
            ],
        ])
        try? await transport.notify(method: "initialized", params: [:])
        initialized = true
    }
}

public struct AppServerQuotaFallback: QuotaFallbackProviding {
    private let client: CodexAppServerClient

    public init(client: CodexAppServerClient) {
        self.client = client
    }

    public func fallbackQuota(now: Date) async -> QuotaSnapshot? {
        guard let result = try? await client.readRateLimits() else { return nil }
        let bucket = RateLimitBucketSelector.select(result.rateLimitsByLimitID) ?? result.rateLimits
        guard let weekly = bucket.flatMap(RateLimitWindowSelector.weekly) else { return nil }
        return QuotaSnapshot(
            planType: bucket?.planType,
            weeklyRemainingPercent: weekly.remainingPercent,
            weeklyResetsAt: weekly.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            source: .appServer,
            fetchedAt: now
        )
    }
}

public struct CompositeQuotaFallback: QuotaFallbackProviding {
    private let providers: [QuotaFallbackProviding]

    public init(_ providers: [QuotaFallbackProviding]) {
        self.providers = providers
    }

    public func fallbackQuota(now: Date) async -> QuotaSnapshot? {
        for provider in providers {
            if let snapshot = await provider.fallbackQuota(now: now) { return snapshot }
        }
        return nil
    }
}

public enum CodexBinaryLocator {
    public static func find(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        if let override = environment["CODEX_CLI_PATH"], fileManager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }
        let home = fileManager.homeDirectoryForCurrentUser.path
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "\(home)/.codex/packages/standalone/current/bin/codex",
            "\(home)/.local/bin/codex",
        ]
        return candidates.first(where: fileManager.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }
}

public final class ProcessAppServerTransport: AppServerTransport, @unchecked Sendable {
    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private let queue = DispatchQueue(label: "com.laoer.codexinfo.appserver")
    private var buffer = Data()
    private var nextID = 1
    private var closed = false

    public init(binaryURL: URL) throws {
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = binaryURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        self.process = process
        self.input = stdin.fileHandleForWriting
        self.output = stdout.fileHandleForReading
    }

    public func request(method: String, params: [String: Any]) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let id = self.nextID
                    self.nextID += 1
                    let message: [String: Any] = [
                        "jsonrpc": "2.0",
                        "id": id,
                        "method": method,
                        "params": params,
                    ]
                    self.input.write(try JSONSerialization.data(withJSONObject: message) + Data("\n".utf8))
                    while let line = self.readLine() {
                        guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                        guard (object["id"] as? NSNumber)?.intValue == id else { continue }
                        if let error = object["error"] as? [String: Any] {
                            let code = (error["code"] as? NSNumber)?.intValue ?? -32603
                            let text = error["message"] as? String ?? "app-server error"
                            throw AppServerError.rpc(code: code, message: text)
                        }
                        guard let result = object["result"] as? [String: Any] else { throw AppServerError.invalidResponse }
                        continuation.resume(returning: result)
                        return
                    }
                    throw AppServerError.notRunning
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func notify(method: String, params: [String: Any]) async throws {
        let message: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params]
        input.write(try JSONSerialization.data(withJSONObject: message) + Data("\n".utf8))
    }

    public func close() {
        guard !closed else { return }
        closed = true
        input.closeFile()
        output.closeFile()
        if process.isRunning { process.terminate() }
    }

    private func readLine() -> Data? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer = buffer[(newline + 1)...]
                if !line.isEmpty { return Data(line) }
                continue
            }
            let chunk = output.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
        }
    }
}
