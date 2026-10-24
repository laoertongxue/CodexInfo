import AppKit
import Combine
import SwiftUI
import CodexInfoCore

/// The menu bar item and the panel.
///
/// The item shows the parts of the title the user picked; the panel is the
/// web app in a popover. A left click opens the panel, a right click opens
/// the menu of the app.
@MainActor
final class MenuBarController: NSObject {
    private let environment: AppEnvironment
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let panel = PanelViewController()
    private var settingsWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()

    init(environment: AppEnvironment) {
        self.environment = environment
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        panel.onMessage = { [weak self] message in self?.handle(message) }
        popover.contentViewController = panel
        popover.contentSize = NSSize(width: 340, height: 780)
        popover.behavior = .transient
        popover.animates = true

        environment.onSnapshot = { [weak self] snapshot in self?.update(snapshot) }
        environment.onError = { [weak self] message in self?.panel.render(error: message) }
        // A change of the parts of the title is shown at once.
        environment.settings.$settings
            .dropFirst()
            .sink { [weak self] settings in self?.refreshTitle(segments: settings.segments) }
            .store(in: &cancellables)
    }

    /// Puts the item into the menu bar.
    func install() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .noImage
        button.attributedTitle = NSAttributedString(string: AppConstants.appName)
    }

    /// Shows a snapshot in the title and in the panel.
    func update(_ snapshot: UsageSnapshot) {
        update(snapshot, segments: environment.settings.settings.segments)
    }

    /// Shows a snapshot in the title and in the panel.
    ///
    /// - Parameters:
    ///   - snapshot: the snapshot the title is built from.
    ///   - segments: the parts of the title.
    private func update(_ snapshot: UsageSnapshot, segments: [StatusSegment]) {
        let title = StatusTitleFormatter.format(snapshot, segments: segments)
        statusItem.button?.attributedTitle = attributedTitle(title)
        panel.render(snapshot)
    }

    /// Opens the panel, or closes it when it is open.
    @objc func showPanel() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens the panel or the menu, depending on the button that was clicked.
    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popUpMenu()
            return
        }
        showPanel()
    }

    /// The menu of the right click.
    private func popUpMenu() {
        guard let button = statusItem.button else { return }
        let menu = makeContextMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    /// The menu of the right click.
    ///
    /// The menu is built again for every click, so the state of the login
    /// item is always the state of the system.
    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("刷新", #selector(refreshNow), "r"))
        menu.addItem(item("扫描重置源", #selector(scanNow), ""))
        menu.addItem(.separator())
        menu.addItem(item("设置…", #selector(showSettings), ","))
        let login = item("开机启动", #selector(toggleLaunchAtLogin), "")
        login.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        let quit = item("退出 CodexInfo", #selector(NSApplication.terminate(_:)), "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    /// A menu item of the app.
    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    /// Rebuilds the snapshot.
    @objc private func refreshNow() {
        Task { await environment.refresh() }
    }

    /// Scans the reset sources.
    @objc private func scanNow() {
        Task { await environment.scan() }
    }

    /// Opens the settings window.
    @objc private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(store: environment.settings, notifications: environment.notifications)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "CodexInfo 设置"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 420, height: 560))
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Starts the app at the next login, or stops it.
    @objc private func toggleLaunchAtLogin() {
        let enabled = !LaunchAtLogin.isEnabled
        do {
            try LaunchAtLogin.set(enabled)
        } catch {
            return
        }
        environment.settings.update { $0.launchAtLogin = enabled }
    }

    /// Handles a message of the panel.
    private func handle(_ message: PanelMessage) {
        switch message {
        case .ready:
            // The page is loaded and waits for the first snapshot.
            if let snapshot = environment.snapshot {
                panel.render(snapshot)
            }
        case .refresh:
            Task { await environment.refresh() }
        case .scan:
            Task { await environment.scan() }
        case .openURL(let value):
            if let url = URL(string: value),
               ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            }
        case .openSettings:
            showSettings()
        case .close:
            popover.performClose(nil)
        }
    }

    /// Shows the title of the snapshot again, e.g. after a change of the
    /// settings.
    private func refreshTitle(segments: [StatusSegment]) {
        guard let snapshot = environment.snapshot else { return }
        update(snapshot, segments: segments)
    }

    /// The title of the menu bar item.
    ///
    /// Every part keeps its own colour, so the state of the value is visible
    /// without opening the panel.
    private func attributedTitle(_ title: StatusTitle) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        let attributed = NSMutableAttributedString()
        for (index, part) in title.parts.enumerated() {
            if index > 0 {
                attributed.append(NSAttributedString(string: " · ", attributes: [
                    .font: font,
                    .foregroundColor: NSColor.secondaryLabelColor
                ]))
            }
            attributed.append(NSAttributedString(string: part.text, attributes: [
                .font: font,
                .foregroundColor: color(for: part.color)
            ]))
        }
        return attributed
    }

    /// The colour of a part of the title.
    private func color(for color: StatusColor) -> NSColor {
        switch color {
        case .normal: return .labelColor
        case .good: return .systemGreen
        case .warn: return .systemOrange
        case .danger: return .systemRed
        case .muted: return .secondaryLabelColor
        }
    }
}
