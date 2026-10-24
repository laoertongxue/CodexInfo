import Darwin
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
    private var initialization: Task<Void, Error>?

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

    /// Caches the handshake as a task so concurrent callers await the same
    /// `initialize` exchange despite actor reentrancy. A failed handshake is
    /// cleared before the task throws, so a later call can retry it.
    private func ensureInitialized() async throws {
        if initialized { return }
        if let initialization {
            try await initialization.value
            return
        }

        let transport = self.transport
        let task = Task { [weak self] in
            do {
                _ = try await transport.request(method: "initialize", params: [
                    "clientInfo": ["name": "CodexInfo", "title": "CodexInfo", "version": AppConstants.version],
                    "capabilities": [
                        "experimentalApi": false,
                        "requestAttestation": false,
                        "optOutNotificationMethods": [],
                    ],
                ])
                try? await transport.notify(method: "initialized", params: [:])
                await self?.finishInitialization()
            } catch {
                await self?.resetInitialization()
                throw error
            }
        }
        initialization = task
        try await task.value
    }

    private func finishInitialization() {
        initialized = true
        initialization = nil
    }

    private func resetInitialization() {
        initialization = nil
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
    /// Guards the continuation so the response and timeout paths can race
    /// without resuming it twice.
    private final class RequestCompletion: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<[String: Any], Error>?

        init(_ continuation: CheckedContinuation<[String: Any], Error>) {
            self.continuation = continuation
        }

        func resume(returning result: [String: Any]) {
            finish { $0.resume(returning: result) }
        }

        func resume(throwing error: Error) {
            finish { $0.resume(throwing: error) }
        }

        /// Resumes with `error` only if no other path delivered a result.
        @discardableResult
        func failIfPending(with error: Error) -> Bool {
            var delivered = false
            finish { continuation in
                delivered = true
                continuation.resume(throwing: error)
            }
            return delivered
        }

        private func finish(_ body: (CheckedContinuation<[String: Any], Error>) -> Void) {
            lock.lock()
            guard let continuation else {
                lock.unlock()
                return
            }
            self.continuation = nil
            lock.unlock()
            body(continuation)
        }
    }

    private let process: Process
    private let input: FileHandle
    private let output: FileHandle
    private let timeout: TimeInterval
    private let queue = DispatchQueue(label: "com.laoer.codexinfo.appserver")
    private let timeoutQueue = DispatchQueue(label: "com.laoer.codexinfo.appserver.timeout")
    private let writeLock = NSLock()
    private var buffer = Data()
    private var nextID = 1
    private var closed = false

    public init(binaryURL: URL, timeout: TimeInterval = 10) throws {
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        process.executableURL = binaryURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = stdin
        process.standardOutput = stdout
        // Discard stderr asynchronously: an undrained pipe eventually wedges
        // the child, and its content may contain token-bearing output.
        process.standardError = FileHandle.nullDevice
        // A dead child must surface as a throwing write, not a SIGPIPE crash.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try process.run()
        self.process = process
        self.input = stdin.fileHandleForWriting
        self.output = stdout.fileHandleForReading
        self.timeout = timeout
    }

    public func request(method: String, params: [String: Any]) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { continuation in
            let completion = RequestCompletion(continuation)
            queue.async {
                self.performRequest(method: method, params: params, completion: completion)
            }
        }
    }

    public func notify(method: String, params: [String: Any]) async throws {
        try send(["jsonrpc": "2.0", "method": method, "params": params])
    }

    public func close() {
        terminateProcess()
    }

    private func performRequest(method: String, params: [String: Any], completion: RequestCompletion) {
        let id = nextID
        nextID += 1
        let message: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params,
        ]
        do {
            try send(message)
        } catch {
            completion.resume(throwing: AppServerError.notRunning)
            return
        }

        // The deadline fires on its own queue: the serial queue is blocked in
        // `readLine`, so a timer scheduled there could never run. On expiry the
        // child is terminated so the blocked read observes EOF and the queue
        // drains instead of leaking a thread and a wedged process.
        let timeoutItem = DispatchWorkItem { [weak self] in
            guard let self, completion.failIfPending(with: AppServerError.timeout) else { return }
            self.terminateProcess()
        }
        timeoutQueue.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)

        while let line = readLine() {
            guard let data = try? JSONSerialization.jsonObject(with: line),
                  let object = data as? [String: Any] else { continue }
            guard (object["id"] as? NSNumber)?.intValue == id else { continue }
            timeoutItem.cancel()
            if let error = object["error"] as? [String: Any] {
                let code = (error["code"] as? NSNumber)?.intValue ?? -32603
                let text = error["message"] as? String ?? "app-server error"
                completion.resume(throwing: AppServerError.rpc(code: code, message: text))
                return
            }
            guard let result = object["result"] as? [String: Any] else {
                completion.resume(throwing: AppServerError.invalidResponse)
                return
            }
            completion.resume(returning: result)
            return
        }
        timeoutItem.cancel()
        completion.resume(throwing: AppServerError.notRunning)
    }

    private func send(_ message: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: message) + Data("\n".utf8)
        writeLock.lock()
        defer { writeLock.unlock() }
        guard !closed else { throw AppServerError.notRunning }
        try input.write(contentsOf: data)
    }

    private func terminateProcess() {
        writeLock.lock()
        guard !closed else {
            writeLock.unlock()
            return
        }
        closed = true
        try? input.close()
        writeLock.unlock()

        guard process.isRunning else { return }
        process.terminate()
        let process = self.process
        // Escalate if the child ignores SIGTERM so the blocked stdout read
        // still observes EOF.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
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
