import AppKit
import IslandCore

/// The menu-bar presence: shows at a glance that island is alive, offers a
/// manual summon (so the hotkey is never the only way in), the login-item
/// toggle, and a way out.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let configuration: ResolvedConfiguration
    private let loginItem: LoginItemController
    private let onSummon: () -> Void
    private let onQuit: () -> Void

    /// Last `SMAppService` failure, surfaced in the menu instead of vanishing
    /// into a log the user cannot see.
    private var lastError: String?

    init(
        configuration: ResolvedConfiguration,
        loginItem: LoginItemController,
        onSummon: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.loginItem = loginItem
        self.onSummon = onSummon
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        installButton()
        rebuildMenu()
    }

    private func installButton() {
        guard let button = statusItem.button else { return }
        if let image = NSImage(
            systemSymbolName: "capsule.portrait.fill",
            accessibilityDescription: "island"
        ) {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "island"
        }
        button.toolTip = "island — summon with \(configuration.hotkey.spec.displayString)"
        log("menu bar item installed; launch at login: \(loginItem.status.rawValue)")
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        menu.addItem(
            action(
                "Summon overlay (\(configuration.hotkey.spec.displayString))",
                #selector(summon),
                keyEquivalent: ""
            )
        )
        menu.addItem(
            disabled(
                "hides itself after \(ResolvedConfiguration.secondsText(configuration.duration.seconds))s"
            ))
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
