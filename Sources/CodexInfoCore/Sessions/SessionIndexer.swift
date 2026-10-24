import Foundation

public actor SessionIndexer {
    /// The name of the cache file of the index.
    public static let cacheFileName = "session-index.json"

    private struct FileState {
        /// Bytes consumed from the file, including the bytes held in `pending`.
        var offset: UInt64
        /// Trailing bytes of a line that is not complete yet.
        var pending: Data
        var events: [SessionEvent]
        var modifiedAt: Date
        /// Size observed at the last successful scan.
        var size: UInt64
    }

    private struct CachedIndex: Codable, Equatable {
        let size: UInt64
        let modifiedAt: Date
        let index: SessionIndex
        /// Cumulative `thread_token_usage.total_tokens` of the newest token usage record.
        let threadTotalTokens: Int?
    }

    /// The shortest time between two writes of the cache file.
    ///
    /// The app scans the log every few seconds, and the cache holds the
    /// metrics of every session. Writing it on every scan would rewrite
    /// hundreds of kilobytes over and over, so the cache is written when it
    /// changed and at most once per interval.
    public static let cacheWriteInterval: TimeInterval = 30

    private let rootURL: URL
    private let cacheURL: URL?
    private let cacheWriteInterval: TimeInterval
    private var states: [String: FileState] = [:]
    private var cachedIndexes: [String: CachedIndex] = [:]
    private var scanCount = 0
    /// Whether the cache holds a change that was not written yet.
    private var cacheDirty = false
    /// The moment the cache file was written the last time.
    private var lastCacheWrite: Date?
    /// The number of times the cache file was written.
    private var cacheWriteCount = 0

    public init(
        rootURL: URL,
        cacheURL: URL? = nil,
        cacheWriteInterval: TimeInterval = SessionIndexer.cacheWriteInterval
    ) {
        self.rootURL = rootURL
        self.cacheURL = cacheURL
        self.cacheWriteInterval = cacheWriteInterval
        if let cacheURL, let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode([String: CachedIndex].self, from: data) {
            self.cachedIndexes = decoded
            // The file on disk is as fresh as its moment, so a scan that does
            // not change anything does not write it again.
            let values = try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey])
            self.lastCacheWrite = values?.contentModificationDate
        }
    }

    /// The number of scans the indexer has performed.
    ///
    /// The counter shows whether the areas of a build shared one scan of the
    /// session log.
    public var scans: Int { scanCount }

    /// The number of times the cache file was written.
    ///
    /// The counter shows that the cache is not rewritten on every scan.
    public var cacheWrites: Int { cacheWriteCount }

    public func scan() async -> [SessionIndex] {
        performScan().indexes
    }

    /// Module-internal scan that additionally returns the session level token totals
    /// (`thread_token_usage.total_tokens` of the newest token usage record) keyed by session path.
    ///
    /// The totals are deliberately kept out of `SessionIndex`: the public model stays the
    /// documented shape, while the repository still prefers the thread total for the
    /// session token sum (design spec 5.3).
    func scanWithTotals() async -> (indexes: [SessionIndex], threadTotals: [String: Int]) {
        performScan()
    }

    private func performScan() -> (indexes: [SessionIndex], threadTotals: [String: Int]) {
        scanCount += 1
        let files = (try? FileManager.default.subpathsOfDirectory(atPath: rootURL.path))?
            .filter { $0.hasSuffix(".jsonl") } ?? []
        var results: [SessionIndex] = []
        var threadTotals: [String: Int] = [:]
        var seenPaths: Set<String> = []

        for relative in files {
            let url = rootURL.appendingPathComponent(relative)
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize, let modifiedAt = values.contentModificationDate else { continue }
            let path = url.path
            seenPaths.insert(path)
            let currentSize = UInt64(size)

            if states[path] == nil,
               let cached = cachedIndexes[path],
               cached.size == currentSize,
               cached.modifiedAt == modifiedAt {
                results.append(cached.index)
                if let total = cached.threadTotalTokens { threadTotals[path] = total }
                continue
            }

            var state = states[path] ?? FileState(offset: 0, pending: Data(), events: [], modifiedAt: .distantPast, size: 0)
            if currentSize < state.offset {
                // The file shrank: it was truncated or rotated, the recorded state is meaningless.
                state = FileState(offset: 0, pending: Data(), events: [], modifiedAt: .distantPast, size: 0)
            }
            if currentSize == state.offset, state.offset == state.size, state.modifiedAt != modifiedAt {
                // The file was rewritten in place with the same byte length. The recorded
                // events describe the previous content, so drop them and read from the start.
                state = FileState(offset: 0, pending: Data(), events: [], modifiedAt: .distantPast, size: 0)
            }
            var readFailed = false
            if currentSize > state.offset || state.events.isEmpty {
                if let data = read(from: url, offset: state.offset) {
                    var combined = state.pending + data
                    let lines = combined.split(separator: 0x0A, omittingEmptySubsequences: false)
                    var remaining = Data()
                    if let last = lines.last, !last.isEmpty {
                        remaining = Data(last)
                        combined = Data(combined.dropLast(last.count))
                    }
                    for line in combined.split(separator: 0x0A) where !line.isEmpty {
                        if let event = SessionLogParser.parse(line: Data(line)) {
                            state.events.append(event)
                        }
                    }
                    state.pending = remaining
                    // Advance by the bytes actually consumed, not by the size observed before
                    // the read: a file that grows while being read would otherwise leave the
                    // offset behind and make the next scan re-parse the overlap.
                    state.offset = state.offset + UInt64(data.count)
                } else {
                    readFailed = true
                }
            }
            if !readFailed {
                state.size = currentSize
                state.modifiedAt = modifiedAt
            }
            states[path] = state

            let aggregate = TurnAggregator.aggregate(state.events)
            var activeTurn: String?
            for event in state.events {
                switch event {
                case .taskStarted(let value): activeTurn = value.turnId
                case .taskComplete(let value): if activeTurn == value.turnId { activeTurn = nil }
                case .turnAborted(let value): if activeTurn == value.turnId { activeTurn = nil }
                default: break
                }
            }
            let settings = state.events.compactMap { event -> ThreadSettingsEvent? in
                if case .threadSettings(let value) = event { return value }
                return nil
            }.last
            let latestTurn = aggregate.turns.last
            let lastContext = aggregate.lastTokenCount
            let threadTotal = lastThreadTotalTokens(state.events)
            let modelMismatch = latestTurn?.model != nil && settings?.model != nil && latestTurn?.model != settings?.model
            let effortMismatch = latestTurn?.reasoningEffort != nil && settings?.reasoningEffort != nil && latestTurn?.reasoningEffort != settings?.reasoningEffort
            let routeMismatch = modelMismatch || effortMismatch
            // A downgrade is only decided when the two routes are comparable
            // (design 5.6.3). A model swap is a mismatch, not a downgrade.
            let routeDowngrade = RouteComparison.isDowngrade(
                actualModel: latestTurn?.model,
                actualEffort: latestTurn?.reasoningEffort,
                selectedModel: settings?.model,
                selectedEffort: settings?.reasoningEffort
            )
            let index = SessionIndex(
                path: path,
                modifiedAt: modifiedAt,
                turns: aggregate.turns,
                isActive: activeTurn != nil,
                model: latestTurn?.model ?? settings?.model,
                reasoningEffort: latestTurn?.reasoningEffort ?? settings?.reasoningEffort,
                serviceTier: settings?.serviceTier,
                // Context tokens fall back to the thread total when `last_token_usage` is missing.
                contextTokens: lastContext?.lastUsage?.totalTokens ?? threadTotal,
                contextWindow: lastContext?.modelContextWindow,
                lastRateLimits: lastContext?.rateLimits,
                selectedModel: settings?.model,
                selectedEffort: settings?.reasoningEffort,
                selectedServiceTier: settings?.serviceTier,
                routeMismatch: routeMismatch,
                routeDowngrade: routeDowngrade
            )
            results.append(index)
            if let threadTotal { threadTotals[path] = threadTotal }
            let cached = CachedIndex(
                size: currentSize,
                modifiedAt: modifiedAt,
                index: index,
                threadTotalTokens: threadTotal
            )
            if cachedIndexes[path] != cached { cacheDirty = true }
            cachedIndexes[path] = cached
        }

        // Sessions that disappeared must not keep occupying the cache or the memory.
        let pruned = cachedIndexes.filter { seenPaths.contains($0.key) }
        if pruned.count != cachedIndexes.count { cacheDirty = true }
        cachedIndexes = pruned
        states = states.filter { seenPaths.contains($0.key) }

        writeCacheIfNeeded()
        return (indexes: results.sorted { $0.modifiedAt < $1.modifiedAt }, threadTotals: threadTotals)
    }

    /// Writes the cache file when it changed and the interval is over.
    ///
    /// The cache is an optimization, so a scan that found nothing new leaves
    /// the file alone. The first scan writes it, so the file exists even when
    /// the log never changes.
    private func writeCacheIfNeeded() {
        guard let cacheURL else { return }
        guard cacheDirty || lastCacheWrite == nil else { return }
        let now = Date()
        if let lastCacheWrite, now.timeIntervalSince(lastCacheWrite) < cacheWriteInterval { return }
        guard let data = try? JSONEncoder().encode(cachedIndexes) else { return }
        try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)
        cacheDirty = false
        lastCacheWrite = now
        cacheWriteCount += 1
    }

    /// Cumulative thread token total of the newest token usage record. A zero total means the
    /// record carried no thread usage, so it is treated as "not available".
    private func lastThreadTotalTokens(_ events: [SessionEvent]) -> Int? {
        events.compactMap { event -> Int? in
            if case .tokenUsageRecord(let value) = event { return value.threadTokenUsage.totalTokens }
            return nil
        }.last(where: { $0 > 0 })
    }

    /// Reads from `offset` to the end of the file. Returns nil when the file cannot be opened
    /// or seeked, so the caller can keep the previous state and retry later.
    private func read(from url: URL, offset: UInt64) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
        } catch {
            return nil
        }
        return (try? handle.readToEnd()) ?? Data()
    }
}
