import Foundation

public actor SessionIndexer {
    private struct FileState {
        var offset: UInt64
        var pending: Data
        var events: [SessionEvent]
        var modifiedAt: Date
        var size: UInt64
    }

    private struct CachedIndex: Codable {
        let size: UInt64
        let modifiedAt: Date
        let index: SessionIndex
    }

    private let rootURL: URL
    private let cacheURL: URL?
    private var states: [String: FileState] = [:]
    private var cachedIndexes: [String: CachedIndex] = [:]

    public init(rootURL: URL, cacheURL: URL? = nil) {
        self.rootURL = rootURL
        self.cacheURL = cacheURL
        if let cacheURL, let data = try? Data(contentsOf: cacheURL),
           let decoded = try? JSONDecoder().decode([String: CachedIndex].self, from: data) {
            self.cachedIndexes = decoded
        }
    }

    public func scan() async -> [SessionIndex] {
        let files = (try? FileManager.default.subpathsOfDirectory(atPath: rootURL.path))?
            .filter { $0.hasSuffix(".jsonl") } ?? []
        var results: [SessionIndex] = []
        for relative in files {
            let url = rootURL.appendingPathComponent(relative)
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = values.fileSize, let modifiedAt = values.contentModificationDate else { continue }
            let path = url.path
            if states[path] == nil,
               let cached = cachedIndexes[path],
               cached.size == UInt64(size),
               cached.modifiedAt == modifiedAt {
                results.append(cached.index)
                continue
            }
            var state = states[path] ?? FileState(offset: 0, pending: Data(), events: [], modifiedAt: .distantPast, size: 0)
            if UInt64(size) < state.offset {
                state = FileState(offset: 0, pending: Data(), events: [], modifiedAt: .distantPast, size: 0)
            }
            if UInt64(size) > state.offset || state.events.isEmpty {
                let data = read(from: url, offset: state.offset)
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
                state.offset = UInt64(size)
            }
            state.size = UInt64(size)
            state.modifiedAt = modifiedAt
            states[path] = state

            let aggregate = TurnAggregator.aggregate(state.events)
            var activeTurn: String?
            for event in state.events {
                switch event {
                case .taskStarted(let value): activeTurn = value.turnId
                case .taskComplete(let value): if activeTurn == value.turnId { activeTurn = nil }
                default: break
                }
            }
            let settings = state.events.compactMap { event -> ThreadSettingsEvent? in
                if case .threadSettings(let value) = event { return value }
                return nil
            }.last
            let latestTurn = aggregate.turns.last
            let lastContext = aggregate.lastTokenCount
            let modelMismatch = latestTurn?.model != nil && settings?.model != nil && latestTurn?.model != settings?.model
            let effortMismatch = latestTurn?.reasoningEffort != nil && settings?.reasoningEffort != nil && latestTurn?.reasoningEffort != settings?.reasoningEffort
            let routeMismatch = modelMismatch || effortMismatch
            let index = SessionIndex(
                path: path,
                modifiedAt: modifiedAt,
                turns: aggregate.turns,
                isActive: activeTurn != nil,
                model: latestTurn?.model ?? settings?.model,
                reasoningEffort: latestTurn?.reasoningEffort ?? settings?.reasoningEffort,
                serviceTier: settings?.serviceTier,
                contextTokens: lastContext?.lastUsage?.totalTokens,
                contextWindow: lastContext?.modelContextWindow,
                lastRateLimits: lastContext?.rateLimits,
                selectedModel: settings?.model,
                selectedEffort: settings?.reasoningEffort,
                selectedServiceTier: settings?.serviceTier,
                routeMismatch: routeMismatch
            )
            results.append(index)
            cachedIndexes[path] = CachedIndex(size: UInt64(size), modifiedAt: modifiedAt, index: index)
        }
        if let cacheURL, let data = try? JSONEncoder().encode(cachedIndexes) {
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheURL, options: .atomic)
        }
        return results.sorted { $0.modifiedAt < $1.modifiedAt }
    }

    private func read(from url: URL, offset: UInt64) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        try? handle.seek(toOffset: offset)
        return (try? handle.readToEnd()) ?? Data()
    }
}
