import Foundation

/// The kind of a normalized reset signal.
///
/// - `reset`: a completed usage reset.
/// - `banked`: a reset that was credited in advance.
/// - `limits`: a change of the limit itself.
/// - `verifying`: a reset that is announced but not confirmed yet.
/// - `status`: a service-health signal that never proves a quota reset.
/// - `note`: an informational entry without a reset claim.
public enum ResetSignalKind: String, Codable, Equatable, Sendable {
    case reset
    case banked
    case limits
    case verifying
    case status
    case note
}

/// One normalized entry of a reset source.
///
/// The same shape is produced by every reset source so that the aggregation
/// layer can compare them without knowing the origin of an entry.
public struct ResetSignal: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let sourceId: String
    public let sourceName: String
    public let kind: ResetSignalKind
    public let severity: String?
    public let title: String
    public let summary: String
    public let publishedAt: Date?
    /// The moment the source expects the reset to land, when it publishes one.
    public let expectedAt: Date?
    public let url: URL?
    public let verified: Bool
    public let scope: String?
    public let confirmingSources: [String]
    /// A short hash of the raw payload the source published for this record.
    public let rawHash: String?

    /// Creates a signal. The labels match the normalized field names of the
    /// design spec, so the separate test module can build signals directly.
    public init(
        id: String,
        sourceId: String,
        sourceName: String,
        kind: ResetSignalKind,
        severity: String? = nil,
        title: String,
        summary: String,
        publishedAt: Date? = nil,
        expectedAt: Date? = nil,
        url: URL? = nil,
        verified: Bool,
        scope: String? = nil,
        confirmingSources: [String] = [],
        rawHash: String? = nil
    ) {
        self.id = id
        self.sourceId = sourceId
        self.sourceName = sourceName
        self.kind = kind
        self.severity = severity
        self.title = title
        self.summary = summary
        self.publishedAt = publishedAt
        self.expectedAt = expectedAt
        self.url = url
        self.verified = verified
        self.scope = scope
        self.confirmingSources = confirmingSources
        self.rawHash = rawHash
    }

    /// Whether the signal may raise a strong notification.
    ///
    /// A strong notification needs a completed reset that the source verified
    /// and marked as `strong`. A plain `kind == .reset` never qualifies.
    public var isStrongNotificationCandidate: Bool {
        kind == .reset && verified && severity == "strong"
    }
}

/// A source of reset signals.
public protocol ResetSource: Sendable {
    /// Stable identifier of the source, used for de-duplication and health.
    var id: String { get }
    /// Human readable name shown in the panel.
    var displayName: String { get }
    /// Fetches the current signals of the source.
    func fetch(using http: HTTPClient, now: Date) async throws -> [ResetSignal]
}
