import AppKit

// The app is an accessory app: it lives in the menu bar and has neither a
// Dock icon nor a main window. The delegate is kept alive by the global.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
