import AppKit
import ApplicationServices
import CodexInfoCore

/// The frames of the composer and of its model selector.
///
/// The frames come from the accessibility tree of the client and count from
/// the top of the main display, like the window server bounds.
struct ClientSelectorAnchor: Sendable {
    var selector: CGRect
    var composer: CGRect?
}

/// Finds the model selector of a client.
///
/// The web content of the clients is not exposed by default; the locator
/// asks the client for its accessibility tree once and then caches the
/// selector element. A frame is a single accessibility read, so the follow
/// loop stays cheap. Without the accessibility permission the locator
/// returns `nil` and the overlay uses the measured window fallback.
final class ClientSelectorLocator: @unchecked Sendable {
    private final class Elements {
        let selector: AXUIElement
        let composer: AXUIElement?

        init(selector: AXUIElement, composer: AXUIElement?) {
            self.selector = selector
            self.composer = composer
        }
    }

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.laoer.codexinfo.overlay.ax", qos: .utility)
    private var elements: [ClientOverlayTarget: Elements] = [:]
    private var finding: Set<ClientOverlayTarget> = []
    private var lastAttempt: [ClientOverlayTarget: Date] = [:]

    /// The selector of the client, or `nil` while the tree is being read.
    ///
    /// - Parameters:
    ///   - target: the client of the badge.
    ///   - app: the running client.
    func anchor(for target: ClientOverlayTarget, app: NSRunningApplication) -> ClientSelectorAnchor? {
        guard AXIsProcessTrusted() else { return nil }
        lock.lock()
        let cached = elements[target]
        lock.unlock()
        if let cached {
            if let selector = Self.frame(of: cached.selector) {
                let composer = cached.composer.flatMap(Self.frame(of:))
                return ClientSelectorAnchor(selector: selector, composer: composer)
            }
            // The web UI rebuilt the element; read the tree again.
            lock.lock()
            elements.removeValue(forKey: target)
            lock.unlock()
        }
        scheduleFind(target, app)
        return nil
    }

    /// Reads the tree in the background, at most every three seconds after a
    /// miss; a slow client never blocks the follow loop.
    private func scheduleFind(_ target: ClientOverlayTarget, _ app: NSRunningApplication) {
        let now = Date()
        lock.lock()
        if finding.contains(target) {
            lock.unlock()
            return
        }
        if let last = lastAttempt[target], now.timeIntervalSince(last) < 3 {
            lock.unlock()
            return
        }
        lastAttempt[target] = now
        finding.insert(target)
        lock.unlock()
        let pid = app.processIdentifier
        queue.async { [weak self] in
            let found = Self.find(target, pid: pid)
            guard let self else { return }
            self.lock.lock()
            if let found {
                self.elements[target] = found
            }
            self.finding.remove(target)
            self.lock.unlock()
        }
    }

    /// The composer and its model selector.
    ///
    /// The model selector is recognized by its control label first: a stop
    /// or send button can become a wide control while the client generates,
    /// and a purely positional rule would put the badge on top of it. The
    /// rightmost wide control near the composer is the fallback for a client
    /// whose label is localized differently.
    private static func find(_ target: ClientOverlayTarget, pid: pid_t) -> Elements? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        _ = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        guard let windows = attr(app, kAXWindowsAttribute) as? [AXUIElement],
              let window = windows.first,
              let windowFrame = frame(of: window) else {
            return nil
        }
        var composers: [(AXUIElement, CGRect)] = []
        var controls: [(element: AXUIElement, frame: CGRect, label: String)] = []
        var count = 0
        func walk(_ element: AXUIElement, _ depth: Int) {
            // The composer is at the bottom of the tree, behind a long
            // conversation on a busy client; visit the last child first and
            // allow a larger tree so the composer is not skipped.
            guard depth <= 40, count < 30_000 else { return }
            count += 1
            let role = str(element, kAXRoleAttribute)
            if role == "AXTextArea", let frame = frame(of: element), frame.width >= 300, frame.height >= 20 {
                composers.append((element, frame))
            } else if ["AXButton", "AXPopUpButton", "AXComboBox"].contains(role),
                      let frame = frame(of: element),
                      frame.width >= 90,
                      frame.width <= 420,
                      frame.height >= 20,
                      frame.height <= 40,
                      frame.intersects(windowFrame) {
                let label = [
                    str(element, kAXTitleAttribute),
                    str(element, kAXDescriptionAttribute),
                    str(element, kAXValueAttribute)
                ]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                controls.append((element, frame, label))
            }
            for child in ((attr(element, kAXChildrenAttribute) as? [AXUIElement]) ?? []).reversed() {
                walk(child, depth + 1)
            }
        }
        walk(window, 1)
        guard let composer = composers.max(by: { $0.1.maxY < $1.1.maxY }) else { return nil }
        let composerFrame = composer.1
        let candidates = controls.filter { candidate in
            let frame = candidate.frame
            return frame.maxY >= composerFrame.maxY - 10
                && frame.maxY <= composerFrame.maxY + 120
                && frame.minX >= composerFrame.minX - 20
        }
        let fragments = selectorFragments(for: target)
        let labelled = candidates.filter { candidate in
            fragments.contains { candidate.label.localizedCaseInsensitiveContains($0) }
        }
        let pool = labelled.isEmpty ? candidates : labelled
        guard let selector = pool.max(by: { $0.frame.minX < $1.frame.minX }) else { return nil }
        return Elements(selector: selector.element, composer: composer.0)
    }

    /// The labels a model selector may carry; the send/stop controls do not
    /// match them.
    private static func selectorFragments(for target: ClientOverlayTarget) -> [String] {
        switch target {
        case .codex:
            return ["GPT-", "模型", "Model"]
        case .qoder:
            return ["模型:", "模型：", "模型", "Model"]
        case .deepSeekHarness:
            return ["选择模型", "Select model", "模型", "Model"]
        case .miniMaxCode:
            return ["选择模型", "Select model", "M3", "MiniMax", "模型", "Model"]
        }
    }

    private static func attr(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    private static func str(_ element: AXUIElement, _ name: String) -> String {
        (attr(element, name) as? String) ?? ""
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = attr(element, kAXPositionAttribute),
              let size = attr(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(),
              CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var value = CGSize.zero
        AXValueGetValue(position as! AXValue, .cgPoint, &point)
        AXValueGetValue(size as! AXValue, .cgSize, &value)
        guard value.width > 0, value.height > 0 else { return nil }
        return CGRect(origin: point, size: value)
    }
}
