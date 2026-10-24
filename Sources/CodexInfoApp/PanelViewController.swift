import AppKit
import WebKit
import CodexInfoCore

/// The panel of the app.
///
/// The panel is the single file build of the web app. The script message
/// handler is registered before the page is loaded, so the page never falls
/// back to the mock host and never shows fake numbers.
final class PanelViewController: NSViewController, WKScriptMessageHandler, WKNavigationDelegate {
    /// The message the panel sends when it is ready for the first snapshot.
    var onMessage: ((PanelMessage) -> Void)?

    private let webView: WKWebView

    init() {
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        configuration.userContentController = contentController
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(nibName: nil, bundle: nil)
        // The handler has to exist before the page is loaded: the page posts
        // its `ready` message as soon as it runs.
        contentController.add(ScriptMessageRelay(handler: self), name: PanelMessageBridge.handlerName)
        webView.navigationDelegate = self
        webView.underPageBackgroundColor = .clear
        if let development = ProcessInfo.processInfo.environment["CODEXINFO_DEV_URL"],
           let url = URL(string: development) {
            webView.load(URLRequest(url: url))
        } else {
            webView.loadHTMLString(WebAssets.panelHTML, baseURL: nil)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    /// Pushes a snapshot into the page.
    ///
    /// The JSON is written like the snapshot file, so the page reads the same
    /// numbers as the menu bar and the MCP server.
    func render(_ snapshot: UsageSnapshot) {
        guard let json = Self.json(snapshot) else { return }
        webView.evaluateJavaScript("window.CodexInfoHost && window.CodexInfoHost.render(\(json));")
    }

    /// Reports an error to the page.
    func render(error message: String) {
        let json = Self.jsonString(message)
        webView.evaluateJavaScript("window.CodexInfoHost && window.CodexInfoHost.error(\(json));")
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let parsed = PanelMessageBridge.message(of: message) else { return }
        onMessage?(parsed)
    }

    /// Keeps the panel inside the app.
    ///
    /// A link of the panel is opened in the system browser, so the panel
    /// never navigates away from the built page.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url,
           ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
           navigationAction.navigationType == .linkActivated {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    /// The snapshot as JSON with ISO-8601 dates.
    private static func json(_ snapshot: UsageSnapshot) -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// A string as JSON.
    private static func jsonString(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let json = String(data: data, encoding: .utf8) else { return "\"\"" }
        return json
    }
}

/// Forwards the messages of the panel without keeping the panel alive.
///
/// The user content controller keeps its handlers, so a handler that holds
/// the view controller strongly would keep it alive for ever.
private final class ScriptMessageRelay: NSObject, WKScriptMessageHandler {
    weak var handler: WKScriptMessageHandler?

    init(handler: WKScriptMessageHandler) {
        self.handler = handler
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        handler?.userContentController(userContentController, didReceive: message)
    }
}
