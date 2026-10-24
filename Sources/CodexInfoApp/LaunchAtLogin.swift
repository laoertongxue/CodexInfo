import Foundation
import ServiceManagement

/// The error of the login item.
enum LaunchAtLoginError: Error {
    /// The app runs outside of an app bundle, so the system has no login
    /// item for it.
    case notBundled
}

/// Starts the app when the user logs in.
///
/// The login item is managed by the system, so the app never writes a launch
/// agent of its own.
enum LaunchAtLogin {
    /// Whether the app starts when the user logs in.
    static var isEnabled: Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    /// Starts the app at the next login, or stops it.
    ///
    /// - Parameter enabled: whether the app should start at the next login.
    /// - Throws: the error of the system when the login item cannot be
    ///   changed.
    static func set(_ enabled: Bool) throws {
        guard Bundle.main.bundleIdentifier != nil else {
            throw LaunchAtLoginError.notBundled
        }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
