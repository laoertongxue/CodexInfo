import AppKit

/// The delegate of the app.
///
/// The delegate owns the environment and the menu bar item and opens the
/// panel when the app is asked to by its URL scheme.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The scheme the app is opened with.
    static let urlScheme = "codexinfo"

    private var environment: AppEnvironment?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment()
        let menuBar = MenuBarController(environment: environment)
        self.environment = environment
        self.menuBar = menuBar
        // A notification or the URL scheme opens the panel.
        environment.openRequested = { [weak menuBar] in menuBar?.showPanel() }
        menuBar.install()
        environment.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme?.lowercased() == Self.urlScheme }) else { return }
        menuBar?.showPanel()
    }

    /// The app stays in the menu bar when the settings window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
