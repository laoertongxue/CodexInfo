import AppKit
import Combine
import CodexInfoCore

/// The badge inside the clients.
///
/// The controller owns one clickable panel per client. A panel only
/// appears while its client is the frontmost app and a window is visible, so
/// the badge never floats over an unrelated app.
@MainActor
final class ClientOverlayController {
    private let environment: AppEnvironment
    private var panels: [ClientOverlayTarget: ClientOverlayPanel] = [:]
    private var badges: [ClientOverlayTarget: ClientBadge] = [:]
    private var renderedBadges: [ClientOverlayTarget: ClientBadge] = [:]
    private let selectorLocator = ClientSelectorLocator()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()

    /// A click on a badge asks the menu bar to open the panel on that client.
    var onSelect: ((ClientOverlayTarget) -> Void)?

    /// The top of the main display in AppKit points.
    ///
    /// The window server reports window bounds from the top of the main
    /// display; AppKit counts from its bottom.
    private var mainScreenMaxY: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        // The Codex badge comes from the snapshot the panel already shows, so
        // the overlay never asks the network twice.
        environment.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                if let badge = snapshot?.codexBadge {
                    self.badges[.codex] = badge
                } else {
                    self.badges.removeValue(forKey: .codex)
                }
                self.tick()
            }
            .store(in: &cancellables)
        environment.settings.$settings
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.tick() }
            .store(in: &cancellables)
        // The other clients come from the same store as their panel tabs.
        environment.clients.$snapshots
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshots in
                guard let self else { return }
                for (target, snapshot) in snapshots {
                    self.badges[target] = snapshot.badge
                }
                self.tick()
            }
            .store(in: &cancellables)
    }
    deinit {
        timer?.invalidate()
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Starts the follow loop and the workspace observers.
    func start() {
        let activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        let screen = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        observers = [activation, screen]
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // The common mode keeps the badge following the window while a menu
        // or a scroll is tracking the run loop.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    /// Places the badge of the frontmost client, or hides every badge.
    private func tick() {
        guard environment.settings.settings.overlayEnabled else {
            hidePanels(except: nil)
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              let target = ClientOverlayTarget.target(for: app) else {
            hidePanels(except: nil)
            return
        }
        guard let badge = badges[target] else {
            hidePanels(except: nil)
            return
        }
        guard let window = ClientWindowLocator.largestWindow(of: app) else {
            hidePanels(except: nil)
            return
        }
        let panel = panel(for: target)
        if renderedBadges[target] != badge {
            _ = panel.update(badge)
            renderedBadges[target] = badge
        }
        let size = panel.frame.size
        let anchor = selectorLocator.anchor(for: target, app: app)
        if anchor == nil, target.requiresPreciseAnchor {
            // Qoder has no safe window-only fallback in its split layout;
            // hiding is better than covering its model selector.
            hidePanels(except: nil)
            return
        }
        let frame: CGRect
        if let anchor {
            guard let precise = target.layout.frame(
                forSelector: anchor.selector,
                composer: anchor.composer,
                size: size,
                mainScreenMaxY: mainScreenMaxY
            ) else {
                // The composer has no room for the badge; covering the model
                // selector would be worse than hiding it.
                hidePanels(except: nil)
                return
            }
            frame = precise
        } else {
            guard let fallback = target.layout.frame(
                for: window,
                size: size,
                mainScreenMaxY: mainScreenMaxY
            ) else {
                hidePanels(except: nil)
                return
            }
            frame = fallback
        }
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        hidePanels(except: target)
    }

    /// The panel of a client, created on first use.
    private func panel(for target: ClientOverlayTarget) -> ClientOverlayPanel {
        if let panel = panels[target] { return panel }
        let panel = ClientOverlayPanel()
        panel.onClick = { [weak self] in
            guard let self,
                  let front = NSWorkspace.shared.frontmostApplication,
                  ClientOverlayTarget.target(for: front) == target else {
                return
            }
            self.onSelect?(target)
        }
        panels[target] = panel
        return panel
    }

    /// Hides every badge except the one of the given client.
    private func hidePanels(except target: ClientOverlayTarget?) {
        for (key, panel) in panels where key != target {
            if panel.isVisible {
                panel.orderOut(nil)
            }
        }
    }
}

/// The window of one badge.
///
/// The window never becomes key. A click on the badge is delivered to the
/// panel, which asks the menu bar to open the panel of that client; the click
/// never reaches the composer behind it.
final class ClientOverlayPanel: NSPanel {
    private let badgeView = ClientBadgeView()

    /// The action of a click on the badge.
    var onClick: (() -> Void)?

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: 220, height: 24),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = badgeView
        badgeView.onActivate = { [weak self] in self?.onClick?() }
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick))
        badgeView.addGestureRecognizer(click)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows a badge and returns the new size of the window.
    func update(_ badge: ClientBadge) -> CGSize {
        let size = badgeView.update(badge)
        setContentSize(size)
        return size
    }

    @objc private func handleClick() {
        onClick?()
    }
}

/// The drawing of one badge.
final class ClientBadgeView: NSView {
    private var badge: ClientBadge?
    private var text: NSAttributedString?
    private var textSize: CGSize = .zero
    private var hovered = false
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }

    /// The action the accessibility tree exposes for the clickable badge.
    var onActivate: (() -> Void)?

    /// The first click of an inactive client still belongs to the badge.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func accessibilityPerformPress() -> Bool {
        onActivate?()
        return true
    }

    override func viewDidHide() {
        super.viewDidHide()
        hovered = false
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    /// Sets the badge and returns the size the window needs.
    func update(_ badge: ClientBadge) -> CGSize {
        self.badge = badge
        let string = Self.makeText(badge)
        text = string
        textSize = string.size()
        let size = CGSize(
            width: ceil(min(textSize.width, Self.maxTextWidth)) + Self.horizontalPadding * 2,
            height: Self.height
        )
        frame.size = size
        needsDisplay = true
        setAccessibilityLabel(accessibilityText(badge))
        setAccessibilityRole(.button)
        setAccessibilityHelp("打开 CodexInfo 面板")
        return size
    }

    override func draw(_ dirtyRect: NSRect) {
        // A filled label, not a bordered control: the chip blends into the
        // composer instead of looking like a second input field. The hover
        // fill is one step darker, so the badge is visible as clickable.
        let path = NSBezierPath(roundedRect: bounds, xRadius: 6.5, yRadius: 6.5)
        (hovered ? Self.chipBackgroundHover : Self.chipBackground).setFill()
        path.fill()
        guard let text else { return }
        let rect = CGRect(
            x: Self.horizontalPadding,
            y: (bounds.height - textSize.height) / 2,
            width: min(textSize.width, Self.maxTextWidth),
            height: textSize.height
        )
        text.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private func accessibilityText(_ badge: ClientBadge) -> String {
        var parts: [String] = []
        if let model = badge.model { parts.append(model) }
        if let effort = badge.effort { parts.append(effort) }
        if let quota = badge.quotaText ?? badge.quotaPercent.map({ "\($0)%" }) {
            parts.append("\(badge.quotaLabel) \(quota)")
        }
        if let session = badge.session { parts.append(session) }
        return "CodexInfo " + parts.joined(separator: " ")
    }

    /// The line of the badge, with the tone of the quota.
    ///
    /// The client already shows its model next to the badge, so the badge
    /// only carries the part the client does not show: the quota and the
    /// state of the session.
    private static func makeText(_ badge: ClientBadge) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let baseFont = NSFont.systemFont(ofSize: 11.5)
        let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
        let textColor = NSColor.labelColor.withAlphaComponent(0.85)
        let base: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        let result = NSMutableAttributedString()
        let dotColor: NSColor
        switch badge.tone {
        case .normal: dotColor = .systemGreen
        case .warn: dotColor = .systemOrange
        case .danger: dotColor = .systemRed
        case .muted: dotColor = .tertiaryLabelColor
        }
        result.append(NSAttributedString(string: "●", attributes: [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: dotColor,
            .baselineOffset: 0.5,
            .paragraphStyle: paragraph
        ]))
        result.append(NSAttributedString(string: "  \(badge.quotaLabel) ", attributes: base))
        if let quota = badge.quotaText ?? badge.quotaPercent.map({ "\($0)%" }) {
            result.append(NSAttributedString(string: quota, attributes: [
                .font: numberFont,
                .foregroundColor: textColor,
                .paragraphStyle: paragraph
            ]))
        } else {
            result.append(NSAttributedString(string: "—", attributes: base))
        }
        if let session = badge.session {
            result.append(NSAttributedString(string: "  ·  ", attributes: [
                .font: baseFont,
                .foregroundColor: NSColor.tertiaryLabelColor,
                .paragraphStyle: paragraph
            ]))
            result.append(NSAttributedString(string: session, attributes: base))
        }
        return result
    }

    /// The fill of the badge.
    ///
    /// The light mode uses the soft gray of the reference; the dark mode a
    /// translucent white so the chip stays visible on a dark composer.
    private static var chipBackground: NSColor {
        NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedWhite: 1, alpha: 0.12)
            }
            return NSColor(calibratedWhite: 0.95, alpha: 1)
        }
    }

    /// The fill of the badge under the pointer.
    private static var chipBackgroundHover: NSColor {
        NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedWhite: 1, alpha: 0.18)
            }
            return NSColor(calibratedWhite: 0.90, alpha: 1)
        }
    }

    private static let horizontalPadding: CGFloat = 10
    private static let height: CGFloat = 24
    private static let maxTextWidth: CGFloat = 320
}
