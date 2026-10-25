import ApplicationServices

/// The accessibility permission of the precise badge anchor.
///
/// The window server gives the window bounds without a permission, but the
/// model selector lives in the web content of the client and is only exposed
/// through the accessibility tree. The fallback works without the permission;
/// the precise mode needs it.
enum AccessibilityPermission {
    /// Whether the app may read the accessibility tree.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Asks the system for the permission.
    ///
    /// The user grants it in System Settings; a restart of the app makes the
    /// new trust visible to every call.
    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
