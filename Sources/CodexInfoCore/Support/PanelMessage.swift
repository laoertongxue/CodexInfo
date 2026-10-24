import Foundation

/// The messages the panel posts over the native bridge.
///
/// The panel never talks to the network itself: it asks the app for work and
/// the app answers with a snapshot. The parsing lives in the core library, so
/// the protocol of the bridge can be checked without starting the app.
public enum PanelMessage: Equatable, Hashable, Sendable {
    /// The page finished loading and waits for the first snapshot.
    case ready
    /// The panel asks for a fresh snapshot.
    case refresh
    /// The panel asks for a scan of the reset sources.
    case scan
    /// The panel asks for a link to be opened in the system browser.
    case openURL(String)
    /// The panel asks for the settings window.
    case openSettings
    /// The panel asks to be closed.
    case close

    /// Parses the body of a script message.
    ///
    /// A body of another shape and a link that is not a web link are
    /// refused, so the bridge never opens a local file or a script.
    ///
    /// - Parameter body: the body of the script message.
    /// - Returns: the message, or `nil` when the body is unknown.
    public static func parse(_ body: Any) -> PanelMessage? {
        guard let dictionary = body as? [String: Any],
              let type = dictionary["type"] as? String else { return nil }
        switch type {
        case "ready":
            return .ready
        case "refresh":
            return .refresh
        case "scan":
            return .scan
        case "openURL":
            guard let value = dictionary["url"] as? String,
                  let url = URL(string: value),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
            return .openURL(value)
        case "openSettings":
            return .openSettings
        case "close":
            return .close
        default:
            return nil
        }
    }
}
