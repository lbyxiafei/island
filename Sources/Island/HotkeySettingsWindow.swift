import AppKit
import IslandCore

/// The settings window behind the menu's `Settings…` item. Scope is deliberately
/// minimal (PLAN § Scope #3, #5): record the summon hotkey by pressing it,
/// switch it on or off, or clear it; and pick the overlay theme.
///
/// It is a regular, key-capable window — unlike the overlay — because the user
/// has to be able to press keys into it.
@MainActor
final class HotkeySettingsWindow: NSObject {
    private let coordinator: HotkeySettingsCoordinator
    private let onHotkeyChanged: (HotkeySpec, Bool) -> Void
    private let onThemeChanged: (OverlayTheme) -> Void
    private let themePicker = NSPopUpButton()
    private let window: NSWindow
    private let recorder: HotkeyRecorderView
    private let enabledToggle: NSButton
    private let feedback: NSTextField

    init(
        coordinator: HotkeySettingsCoordinator,
        theme: OverlayTheme,
        onHotkeyChanged: @escaping (HotkeySpec, Bool) -> Void,
        onThemeChanged: @escaping (OverlayTheme) -> Void
    ) {
        self.coordinator = coordinator
        self.onHotkeyChanged = onHotkeyChanged
        self.onThemeChanged = onThemeChanged
        recorder = HotkeyRecorderView()
        enabledToggle = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
        feedback = NSTextField(labelWithString: "")
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "island settings"
        window.isReleasedWhenClosed = false
        window.contentView = makeContentView()

        recorder.onRecord = { [weak self] spec in
            self?.recorderDidRecord(spec)
        }
        recorder.onReject = { [weak self] in
            self?.recorderDidReject()
        }
        enabledToggle.target = self
        enabledToggle.action = #selector(enabledToggled)
        themePicker.addItems(withTitles: OverlayTheme.allCases.map(\.displayName))
        themePicker.selectItem(at: OverlayTheme.allCases.firstIndex(of: theme) ?? 0)
        themePicker.target = self
        themePicker.action = #selector(themePicked)
        refreshFromCoordinator()
    }

    func show() {
        refreshFromCoordinator()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(recorder)
    }

    // MARK: - Layout

    private func makeContentView() -> NSView {
        let title = label("Summon hotkey", font: .systemFont(ofSize: 13, weight: .semibold))
        recorder.translatesAutoresizingMaskIntoConstraints = false

        let help = label(
            "Click the field, then press a combination (at least one of ⌘⌃⌥⇧).",
            font: .systemFont(ofSize: 11),
            color: .secondaryLabelColor
        )
        feedback.font = .systemFont(ofSize: 11)
        feedback.translatesAutoresizingMaskIntoConstraints = false

        let clear = NSButton(title: "Clear", target: self, action: #selector(clearTapped))
        let reset = NSButton(
            title: "Reset to default", target: self, action: #selector(resetTapped))
        let apply = NSButton(title: "Apply", target: self, action: #selector(applyTapped))
        apply.keyEquivalent = "\r"
        let buttons = NSStackView(views: [clear, reset, apply])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let themeTitle = label("Overlay theme", font: .systemFont(ofSize: 13, weight: .semibold))
        let themeHelp = label(
            "Applies immediately; the overlay shows a preview.",
            font: .systemFont(ofSize: 11),
            color: .secondaryLabelColor
        )

        let stack = NSStackView(views: [
            title, recorder, help, enabledToggle, feedback, buttons, themeTitle, themePicker,
            themeHelp,
        ])
        stack.setCustomSpacing(20, after: buttons)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            recorder.widthAnchor.constraint(equalTo: stack.widthAnchor),
            recorder.heightAnchor.constraint(equalToConstant: 44),
        ])
        return content
    }

    private func label(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        return label
    }

    // MARK: - State

    /// Pushes the coordinator's state into the controls; never notifies back.
    private func refreshFromCoordinator() {
        recorder.setSpec(coordinator.current)
        enabledToggle.state = coordinator.isEnabled ? .on : .off
        if coordinator.isEnabled {
            feedback.textColor = .secondaryLabelColor
            feedback.stringValue = "active: \(coordinator.current.displayString)"
        } else {
            feedback.textColor = .secondaryLabelColor
            feedback.stringValue = "hotkey is off — Apply a combination to switch it back on"
        }
    }

    // MARK: - Actions

    private func recorderDidRecord(_ spec: HotkeySpec) {
        feedback.textColor = .secondaryLabelColor
        feedback.stringValue = "press Apply to bind \(spec.displayString)"
    }

    private func recorderDidReject() {
        showFailure("needs a key plus at least one modifier, e.g. ⌃⌘,")
    }

    @objc private func applyTapped() {
        guard let spec = recorder.spec else {
            showFailure("press a key combination first, or use Clear to switch the hotkey off")
            return
        }

        // While off, `apply` only remembers the key; switch on afterwards so a
        // refused registration cannot lose the recording.
        switch coordinator.apply(spec.specText) {
        case .invalidText(let error):
            showFailure(describe(error))
        case .registrationFailed(let reason):
            showFailure("macOS refused it (\(reason)); kept \(coordinator.current.displayString)")
        case .applied(let applied):
            if coordinator.isEnabled {
                reportSuccess(applied)
            } else {
                enable(with: applied)
            }
        }
    }

    private func enable(with spec: HotkeySpec) {
        switch coordinator.setEnabled(true) {
        case .enabled:
            reportSuccess(spec)
        case .registrationFailed(let reason):
            showFailure("macOS refused it (\(reason)); the hotkey stays off")
            refreshFromCoordinator()
        case .disabled:
            break
        }
    }

    @objc private func clearTapped() {
        if coordinator.isEnabled {
            _ = coordinator.setEnabled(false)
        }
        recorder.setSpec(nil)
        enabledToggle.state = .off
        feedback.textColor = .secondaryLabelColor
        feedback.stringValue = "hotkey switched off; the key is free for other apps"
        onHotkeyChanged(coordinator.current, false)
    }

    @objc private func resetTapped() {
        recorder.setSpec(HotkeyConfiguration.fallbackSpec)
        applyTapped()
    }

    @objc private func themePicked() {
        let index = themePicker.indexOfSelectedItem
        guard OverlayTheme.allCases.indices.contains(index) else { return }
        onThemeChanged(OverlayTheme.allCases[index])
    }

    @objc private func enabledToggled() {
        let shouldEnable = enabledToggle.state == .on
        switch coordinator.setEnabled(shouldEnable) {
        case .enabled(let spec):
            reportSuccess(spec)
        case .disabled:
            feedback.textColor = .secondaryLabelColor
            feedback.stringValue = "hotkey switched off"
            onHotkeyChanged(coordinator.current, false)
        case .registrationFailed(let reason):
            showFailure("macOS refused it (\(reason)); the hotkey stays off")
            refreshFromCoordinator()
        }
    }

    private func reportSuccess(_ spec: HotkeySpec) {
        recorder.setSpec(spec)
        enabledToggle.state = .on
        feedback.textColor = .secondaryLabelColor
        feedback.stringValue = "saved: \(spec.displayString) — already active"
        onHotkeyChanged(spec, true)
    }

    private func showFailure(_ message: String) {
        feedback.textColor = .systemRed
        feedback.stringValue = message
    }

    private func describe(_ error: HotkeySpecError) -> String {
        switch error {
        case .empty: return "press a key combination first"
        case .missingModifier: return "needs at least one modifier, e.g. ⌃⌘,"
        case .unknownModifier(let name): return "unknown modifier \"\(name)\""
        case .unknownKey(let name): return "unknown key \"\(name)\""
        }
    }
}
