import Foundation
import WebKit
import CodexInfoCore

/// The bridge between the panel and the app.
///
/// The panel posts its messages over the `codexInfo` script message handler;
/// the app answers with a snapshot. The messages themselves live in
/// `CodexInfoCore`, so the protocol of the bridge is covered by the tests.
enum PanelMessageBridge {
    /// The name of the script message handler of the panel.
    static let handlerName = "codexInfo"

    /// The message of a script message.
    ///
    /// - Parameter message: the message of the panel.
    /// - Returns: the message, or `nil` when the body is unknown.
    static func message(of message: WKScriptMessage) -> PanelMessage? {
        PanelMessage.parse(message.body)
    }
}
