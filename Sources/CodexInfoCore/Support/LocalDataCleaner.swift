import Foundation

/// Removes the files the app wrote (design 5.9).
///
/// The cleaner knows the files of the support directory of the app: the
/// snapshot of the menu bar, the snapshot of the MCP server, the index of the
/// sessions and the settings. It never touches a file outside of that
/// directory.
public struct LocalDataCleaner: Sendable {
    /// The names of the files the app wrote.
    public static let fileNames: [String] = [
        SnapshotStore.fileName,
        SnapshotStore.mcpFileName,
        SessionIndexer.cacheFileName,
        SettingsFileStore.fileName,
    ]

    /// The directory the files live in.
    public let directory: URL

    /// Creates the cleaner.
    ///
    /// - Parameter directory: the support directory of the app; the tests use
    ///   a temporary one.
    public init(directory: URL = SnapshotStore.defaultDirectory) {
        self.directory = directory
    }

    /// The files the cleaner removes.
    public var fileURLs: [URL] {
        Self.fileNames.map { directory.appendingPathComponent($0) }
    }

    /// Removes the files and returns how many of them were there.
    ///
    /// A file that is already gone is not an error, so the button of the
    /// settings can be pressed twice.
    @discardableResult
    public func clear() throws -> Int {
        var removed = 0
        for url in fileURLs {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            try FileManager.default.removeItem(at: url)
            removed += 1
        }
        return removed
    }
}
