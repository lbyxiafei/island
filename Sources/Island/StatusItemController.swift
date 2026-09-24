import AppKit
import IslandCore

/// The menu-bar presence: shows at a glance that island is alive, offers a
/// manual summon (so the hotkey is never the only way in), the on/off switch for
/// the global hotkey, the settings window, the login-item toggle, and a way out.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let durationSeconds: TimeInterval
    private let loginItem: LoginItemController
    private let onSummon: () -> Void
    private let onToggleHotkey: (Bool) -> Void
    private let onSelectTask: (String) -> Void
    private let onOpenSettings: () -> Void
    private let onQuit: () -> Void

    private var hotkeyDisplay: String
    private var hotkeySourceNote: String
    private var hotkeyEnabled: Bool
    private var unreadCount = 0
    private var taskEntries: [AgentInbox.Entry] = []

    /// Last `SMAppService` failure, surfaced in the menu instead of vanishing
    /// into a log the user cannot see.
    private var lastError: String?

    init(
        hotkey: HotkeySpec,
        hotkeySource: HotkeySource,
        hotkeyEnabled: Bool,
        durationSeconds: TimeInterval,
        loginItem: LoginItemController,
        onSummon: @escaping () -> Void,
        onToggleHotkey: @escaping (Bool) -> Void,
        onSelectTask: @escaping (String) -> Void,
        onOpenSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.durationSeconds = durationSeconds
        self.loginItem = loginItem
        self.onSummon = onSummon
        self.onToggleHotkey = onToggleHotkey
        self.onSelectTask = onSelectTask
        self.onOpenSettings = onOpenSettings
        self.onQuit = onQuit
        hotkeyDisplay = hotkey.displayString
        hotkeySourceNote = Self.note(for: hotkeySource)
        self.hotkeyEnabled = hotkeyEnabled
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        installButton()
        rebuildMenu()
    }

    /// Called after the hotkey was changed in the settings window.
    func setHotkey(_ spec: HotkeySpec, source: HotkeySource) {
        hotkeyDisplay = spec.displayString
        hotkeySourceNote = Self.note(for: source)
        installButton()
        rebuildMenu()
    }

    /// Called after the hotkey was switched on or off in the settings window.
    func setHotkeyEnabled(_ enabled: Bool) {
        hotkeyEnabled = enabled
        installButton()
        rebuildMenu()
    }

    /// Called when the agent monitor sees a new finished run.
    func setUnreadCount(_ count: Int) {
        guard count != unreadCount else { return }
        unreadCount = count
        installButton()
    }

    /// The tasks the menu lists (same order as the overlay).
    func setTasks(_ entries: [AgentInbox.Entry]) {
        taskEntries = entries
        rebuildMenu()
    }

    private func installButton() {
        guard let button = statusItem.button else { return }
        button.image = IslandGlyph.menuBarImage()
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        button.title = unreadCount > 0 ? " \(unreadCount)" : ""
        button.toolTip =
            hotkeyEnabled
            ? "island — summon with \(hotkeyDisplay)"
            : "island — hotkey switched off"
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        menu.addItem(
            action("Summon overlay (\(hotkeyDisplay))", #selector(summon), keyEquivalent: "")
        )
        menu.addItem(
            action(
                "Summon hotkey",
                #selector(toggleHotkey),
                keyEquivalent: "",
                isChecked: hotkeyEnabled
            )
        )
        menu.addItem(
            disabled(
                hotkeyEnabled
                    ? "hotkey \(hotkeyDisplay) · \(hotkeySourceNote)"
                    : "hotkey off — the key is free for other apps"
            )
        )
        menu.addItem(
            disabled("hides itself after \(ResolvedConfiguration.secondsText(durationSeconds))s"))
        menu.addItem(.separator())

        if !taskEntries.isEmpty {
            for entry in taskEntries {
                let item = action(
                    entry.task.title, #selector(selectTask(_:)), keyEquivalent: "")
                item.representedObject = entry.id
                item.image = entry.isRead ? nil : Self.unreadDot()
                item.toolTip = Self.toolTip(for: entry.task)
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        menu.addItem(action("Settings…", #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())

        let presentation = LoginItemMenuPresentation.make(for: loginItem.status)
        menu.addItem(
            action(
                "Launch at login",
                #selector(toggleLoginItem),
                keyEquivalent: "",
                isChecked: presentation.isChecked
            )
        )
        if let hint = presentation.hint {
            menu.addItem(disabled(hint))
        }
        if let lastError {
            menu.addItem(disabled("last attempt failed: \(lastError)"))
        }
        menu.addItem(.separator())

        menu.addItem(action("Quit island", #selector(quit), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    private static func unreadDot() -> NSImage {
        let size = NSSize(width: 8, height: 8)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }

    private static func toolTip(for task: AgentTask) -> String {
        var pieces = [task.agent.displayName, task.title]
        if let cwd = task.cwd { pieces.append(cwd) }
        if let command = task.resumeCommand { pieces.append(command) }
        return pieces.joined(separator: "\n")
    }

    private static func note(for source: HotkeySource) -> String {
        switch source {
        case .menu: return "set in island"
        case .environment: return "from ISLAND_HOTKEY"
        case .builtInDefault: return "default"
        }
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(
        _ title: String,
        _ selector: Selector,
        keyEquivalent: String,
        isChecked: Bool = false
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: keyEquivalent)
        item.target = self
        item.state = isChecked ? .on : .off
        return item
    }

    @objc private func summon() {
        onSummon()
    }

    @objc private func toggleHotkey() {
        onToggleHotkey(!hotkeyEnabled)
    }

    @objc private func selectTask(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        onSelectTask(id)
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func quit() {
        onQuit()
    }

    @objc private func toggleLoginItem() {
        let shouldEnable = loginItem.status != .enabled
        do {
            try loginItem.setEnabled(shouldEnable)
            lastError = nil
            log("launch at login \(shouldEnable ? "enabled" : "disabled")")
        } catch {
            lastError = error.localizedDescription
            log("launch at login toggle failed: \(error)")
        }
        rebuildMenu()
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("[island] \(message)\n".utf8))
    }
}
