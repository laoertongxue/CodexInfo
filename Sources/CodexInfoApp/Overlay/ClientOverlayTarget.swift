import AppKit

/// A client the badge can sit in.
///
/// The badge is a small clickable panel that follows the composer of the
/// client. The target list is fixed, so an unknown app never gets a badge.
enum ClientOverlayTarget: String, CaseIterable, Hashable, Sendable {
    case codex
    case qoder
    case deepSeekHarness
    case miniMaxCode

    /// The bundle identifiers the client may be installed with.
    var bundleIdentifiers: [String] {
        switch self {
        case .codex: return ["com.openai.codex"]
        case .qoder: return ["com.qodercn.app"]
        case .deepSeekHarness: return ["com.deepseek.dsh"]
        case .miniMaxCode: return ["com.minimax.agent.cn"]
        }
    }

    /// The name of the client in the settings and the logs.
    var displayName: String {
        switch self {
        case .codex: return "ChatGPT"
        case .qoder: return "Qoder"
        case .deepSeekHarness: return "DeepSeek Harness"
        case .miniMaxCode: return "MiniMax Code"
        }
    }

    /// Where the badge sits inside the window.
    var layout: ClientOverlayLayout {
        switch self {
        case .codex: return ClientOverlayLayout(rightInset: 735, bottomInset: 42)
        case .qoder: return ClientOverlayLayout(rightInset: 747, bottomInset: 66)
        case .deepSeekHarness: return ClientOverlayLayout(rightInset: 471, bottomInset: 52)
        case .miniMaxCode: return ClientOverlayLayout(rightInset: 677, bottomInset: 46)
        }
    }

    /// The target of a running app.
    static func target(for app: NSRunningApplication?) -> ClientOverlayTarget? {
        guard let identifier = app?.bundleIdentifier else { return nil }
        return allCases.first { $0.bundleIdentifiers.contains(identifier) }
    }

    /// Qoder's split layout and MiniMax's crowded/right-panel layout have no
    /// reliable window-only fallback; their badges appear only with the
    /// precise accessibility anchor.
    var requiresPreciseAnchor: Bool {
        self == .qoder || self == .miniMaxCode
    }
}

/// The anchor of the badge inside a client window.
///
/// The values are measured from the right and the bottom of the window, so
/// the badge keeps its place when the window is resized.
struct ClientOverlayLayout: Sendable {
    /// The distance from the right edge of the window to the right edge of the
    /// badge when the accessibility tree is not available.
    var rightInset: CGFloat
    /// The distance from the bottom edge of the window to the middle of the
    /// badge when the accessibility tree is not available.
    var bottomInset: CGFloat
    /// The gap between the badge and the model selector in the precise mode.
    ///
    /// The accessibility frame is the text of the selector; its hover
    /// background extends about ten points to the left of the frame, so the
    /// gap includes that padding and leaves a visible space.
    var selectorGap: CGFloat = 24

    /// The frame of the badge above a window when the accessibility tree is
    /// not available.
    ///
    /// - Parameters:
    ///   - window: the frame of the client window, in window-server points.
    ///   - size: the size of the badge.
    ///   - mainScreenMaxY: the top of the main display, in AppKit points.
    /// - Returns: the frame, or `nil` when the fixed inset would put the badge
    ///   outside a narrow window.
    func frame(for window: CGRect, size: CGSize, mainScreenMaxY: CGFloat) -> CGRect? {
        let topLeftX = window.maxX - rightInset - size.width
        let topLeftY = window.maxY - bottomInset - size.height / 2
        guard topLeftX >= window.minX + 6,
              topLeftX + size.width <= window.maxX - 6,
              topLeftY >= window.minY,
              topLeftY + size.height <= window.maxY else {
            return nil
        }
        return CGRect(
            x: topLeftX,
            y: mainScreenMaxY - (topLeftY + size.height),
            width: size.width,
            height: size.height
        )
    }

    /// The frame of the badge next to the real model selector.
    ///
    /// The selector frame comes from the accessibility tree and counts from
    /// the top of the main display. The badge sits to the left of the
    /// selector; when the composer is too narrow for that place, `nil` is
    /// returned so the badge is hidden instead of covering a control.
    ///
    /// - Parameters:
    ///   - selector: the frame of the model selector.
    ///   - composer: the frame of the composer input, when the tree carries it.
    ///   - size: the size of the badge.
    ///   - mainScreenMaxY: the top of the main display, in AppKit points.
    func frame(
        forSelector selector: CGRect,
        composer: CGRect?,
        size: CGSize,
        mainScreenMaxY: CGFloat
    ) -> CGRect? {
        let topLeftX = selector.minX - selectorGap - size.width
        let minX = (composer?.minX ?? selector.minX - 500) + 6
        guard topLeftX >= minX else { return nil }
        let topLeftY = selector.midY - size.height / 2
        return CGRect(
            x: topLeftX,
            y: mainScreenMaxY - (topLeftY + size.height),
            width: size.width,
            height: size.height
        )
    }
}

/// Reads the frame of the visible window of an app.
///
/// The window server reports the bounds without asking for the accessibility
/// permission, so the badge works for a fresh installation.
enum ClientWindowLocator {
    /// The largest visible window of the app.
    ///
    /// - Parameter app: the running client.
    /// - Returns: the frame in window-server points, or `nil` when the app has
    ///   no visible window (for example when it is minimized).
    static func largestWindow(of app: NSRunningApplication) -> CGRect? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        var best: CGRect?
        for info in windows {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid == app.processIdentifier,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let alpha = info[kCGWindowAlpha as String] as? Double,
                  alpha > 0.01,
                  let bounds = info[kCGWindowBounds as String] as? [String: NSNumber],
                  let x = bounds["X"]?.doubleValue,
                  let y = bounds["Y"]?.doubleValue,
                  let width = bounds["Width"]?.doubleValue,
                  let height = bounds["Height"]?.doubleValue,
                  width >= 320,
                  height >= 320 else { continue }
            let frame = CGRect(x: x, y: y, width: width, height: height)
            if best == nil || frame.width * frame.height > best!.width * best!.height {
                best = frame
            }
        }
        return best
    }
}
