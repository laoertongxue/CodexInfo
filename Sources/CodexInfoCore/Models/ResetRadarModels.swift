import Foundation

/// The health of one reset source.
public enum SourceState: String, Codable, Equatable, Sendable {
    /// The source answered and reported nothing wrong.
    case ok
    /// The source answered, but one of its parts reported a degraded state.
    case degraded
    /// The source failed; it is not scanned again before its backoff ends.
    case down
}

/// The last known state of one reset source.
public struct SourceHealth: Codable, Equatable, Sendable {
    /// The stable id of the source.
    public let sourceId: String
    /// The name shown in the panel.
    public let sourceName: String
    /// The health of the source.
    public let state: SourceState
    /// The moment of the last successful scan of the source.
    public let lastSuccessAt: Date?
    /// The message of the last failure of the source.
    public let lastError: String?
    /// The moment the source is scanned again.
    public let nextScanAt: Date?

    public init(
        sourceId: String,
        sourceName: String,
        state: SourceState,
        lastSuccessAt: Date?,
        lastError: String?,
        nextScanAt: Date?
    ) {
        self.sourceId = sourceId
        self.sourceName = sourceName
        self.state = state
        self.lastSuccessAt = lastSuccessAt
        self.lastError = lastError
        self.nextScanAt = nextScanAt
    }
}

/// The aggregated view of the four reset sources.
///
/// The snapshot is what the panel shows: the health of every source, the
/// newest confirmed reset and the recent records.
public struct ResetRadarSnapshot: Codable, Equatable, Sendable {
    /// The health of every configured source, ordered by the source id.
    public let sources: [SourceHealth]
    /// The newest group that two reset sources confirmed.
    public let latestConfirmed: ResetSignal?
    /// The newest group that carries a reset record, even when only one
    /// source published it.
    public let latestReset: ResetSignal?
    /// The newest forecast or announcement, even when it was merged into a
    /// reset group or only one source published it.
    public let latestForecast: ResetSignal?
    /// The recent groups, newest first.
    public let recent: [ResetSignal]
    /// The moment of the last scan.
    public let lastScanAt: Date?
    /// The moment of the next scan.
    public let nextScanAt: Date?

    public init(
        sources: [SourceHealth],
        latestConfirmed: ResetSignal?,
        latestReset: ResetSignal? = nil,
        latestForecast: ResetSignal? = nil,
        recent: [ResetSignal],
        lastScanAt: Date?,
        nextScanAt: Date?
    ) {
        self.sources = sources
        self.latestConfirmed = latestConfirmed
        self.latestReset = latestReset
        self.latestForecast = latestForecast
        self.recent = recent
        self.lastScanAt = lastScanAt
        self.nextScanAt = nextScanAt
    }

    /// The number of sources that are not down.
    public var sourcesAvailable: Int {
        sources.filter { $0.state != .down }.count
    }

    /// The number of configured sources.
    public var sourcesTotal: Int {
        sources.count
    }

    /// The newest group that may raise a strong notification.
    ///
    /// Only a `reset` signal that is verified and carries the `strong`
    /// severity qualifies; a plain `kind == .reset` never does.
    public var latestStrong: ResetSignal? {
        // The display list is capped; a strong reset that fell out of it must
        // still raise its notification.
        if let latestReset, latestReset.isStrongNotificationCandidate {
            return latestReset
        }
        return recent.first { $0.isStrongNotificationCandidate }
    }

    /// The snapshot of a radar that was never scanned.
    public static let empty = ResetRadarSnapshot(
        sources: [], latestConfirmed: nil, recent: [], lastScanAt: nil, nextScanAt: nil
    )
}
