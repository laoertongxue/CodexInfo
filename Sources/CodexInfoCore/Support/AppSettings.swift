import Foundation

/// The settings of the app.
///
/// The settings only describe how the app shows the data; they never change
/// the data itself.
public struct AppSettings: Codable, Equatable, Sendable {
    /// The size of the baseline window in days.
    public var baselineWindowDays: Int
    /// The number of turns the baseline needs at least.
    public var minimumTurns: Int
    /// Whether the system notifications are allowed.
    public var notificationsEnabled: Bool
    /// Whether the app starts when the user logs in.
    public var launchAtLogin: Bool
    /// The parts of the menu bar title, in the order they are shown.
    public var segments: [StatusSegment]

    public init(
        baselineWindowDays: Int = 7,
        minimumTurns: Int = 8,
        notificationsEnabled: Bool = false,
        launchAtLogin: Bool = false,
        segments: [StatusSegment] = [.quota, .rate, .health]
    ) {
        self.baselineWindowDays = baselineWindowDays
        self.minimumTurns = minimumTurns
        self.notificationsEnabled = notificationsEnabled
        self.launchAtLogin = launchAtLogin
        self.segments = segments
    }

    /// The settings of a fresh installation.
    public static let `default` = AppSettings()
}

/// Reads and writes the settings file.
///
/// The file lives in the support directory of the app and is replaced
/// atomically, so a reader either sees the previous settings or the new ones.
public struct SettingsFileStore: Sendable {
    /// The name of the settings file.
    public static let fileName = "settings.json"

    /// The file the settings live in.
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(AppConstants.supportDirectoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private let url: URL

    /// Creates the store of the given file.
    ///
    /// - Parameter url: the file the settings live in; the app uses the
    ///   support directory, the tests use a temporary one.
    public init(url: URL = SettingsFileStore.defaultURL) {
        self.url = url
    }

    /// The file the settings live in.
    public var fileURL: URL { url }

    /// Reads the settings.
    ///
    /// A missing file, an unreadable file and a file of another shape all
    /// return the default settings, so a broken file never keeps the app
    /// from starting.
    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    /// Writes the settings and replaces the previous file.
    public func save(_ settings: AppSettings) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: url, options: .atomic)
    }
}
