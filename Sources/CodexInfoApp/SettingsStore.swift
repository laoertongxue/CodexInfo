import Foundation
import Combine
import CodexInfoCore

/// The settings of the app.
///
/// The store keeps the settings in memory and writes them to the settings
/// file, so a change survives a restart of the app.
@MainActor
final class SettingsStore: ObservableObject {
    /// The settings of the app.
    @Published private(set) var settings: AppSettings {
        didSet { save() }
    }

    private let fileStore: SettingsFileStore

    init(fileStore: SettingsFileStore = SettingsFileStore()) {
        self.fileStore = fileStore
        self.settings = fileStore.load()
        // The file is written right away, so it exists with the current
        // settings even before the user changes one.
        try? fileStore.save(settings)
    }

    /// Changes the settings and writes them to the file.
    ///
    /// - Parameter change: the change of the settings.
    func update(_ change: (inout AppSettings) -> Void) {
        var updated = settings
        change(&updated)
        guard updated != settings else { return }
        settings = updated
    }

    /// Writes the settings to the file.
    private func save() {
        try? fileStore.save(settings)
    }
}
