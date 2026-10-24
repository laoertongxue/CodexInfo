import Foundation

/// Persists the snapshot as JSON.
///
/// The file is replaced atomically, so a reader either sees the previous
/// snapshot or the new one, never a half written file. The JSON uses ISO-8601
/// dates and camelCase keys, because the web panel reads it directly.
public struct SnapshotStore: Sendable {
    /// The name of the snapshot file.
    public static let fileName = "snapshot.json"

    /// The directory the app writes its files to.
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(AppConstants.supportDirectoryName, isDirectory: true)
    }

    private let directory: URL
    private let url: URL

    /// Creates the store for the given directory.
    ///
    /// - Parameter directory: the directory the snapshot file lives in; the
    ///   app uses the support directory, the tests use a temporary one.
    public init(directory: URL = SnapshotStore.defaultDirectory) {
        self.directory = directory
        self.url = directory.appendingPathComponent(SnapshotStore.fileName)
    }

    /// The URL of the snapshot file.
    public var fileURL: URL { url }

    /// Writes the snapshot and replaces the previous file.
    public func save(_ snapshot: UsageSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    /// Reads the snapshot when it is young enough.
    ///
    /// A missing file, an unreadable file and a file that is older than
    /// `maxAge` all return `nil`, so the caller can compute its own snapshot.
    ///
    /// - Parameters:
    ///   - maxAge: the age the snapshot may have at most.
    ///   - now: the moment the age is measured from.
    public func load(maxAge: TimeInterval, now: Date = Date()) throws -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(UsageSnapshot.self, from: data) else { return nil }
        guard now.timeIntervalSince(snapshot.generatedAt) <= maxAge else { return nil }
        return snapshot
    }

    /// Removes the snapshot file.
    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
