import AppKit
import IslandCore

/// The settings window behind the menu's `Settings…` item, one tab per topic:
/// General (record the summon hotkey by pressing it, switch it on or off, or
/// clear it — PLAN § Scope #3, #5), Appearance (overlay theme, keyboard
/// hints), Notifications (the pop-up shown when a run finishes) and Agents
/// (which agent scenarios island watches, see `AgentSettingsView`).
///
/// It is a regular, key-capable window — unlike the overlay — because the user
/// has to be able to press keys into it.
@MainActor
final class HotkeySettingsWindow: NSObject, NSTextFieldDelegate {
    private let coordinator: HotkeySettingsCoordinator
    private let onHotkeyChanged: (HotkeySpec, Bool) -> Void
    private let onThemeChanged: (OverlayTheme) -> Void
    private let themePicker = NSPopUpButton()
    private let onHintsChanged: (Bool) -> Void
    private let hintsToggle = NSButton(
        checkboxWithTitle: "Show keyboard hints", target: nil, action: nil)
    private let onPopupChanged: (PopupSettings) -> Void
    private var popup: PopupSettings
    private let popupToggle = NSButton(
        checkboxWithTitle: "Pop up when an agent run finishes", target: nil, action: nil)
    private let popupSeconds = NSTextField(string: "")
    private let agentsView: AgentSettingsView
    private let window: SettingsWindow
    private let recorder: HotkeyRecorderView
    private let enabledToggle: NSButton
    private let feedback: NSTextField

    init(
        coordinator: HotkeySettingsCoordinator,
        theme: OverlayTheme,
        showsHints: Bool,
        popup: PopupSettings,
        scenarios: AgentScenarioSettings,
        onHotkeyChanged: @escaping (HotkeySpec, Bool) -> Void,
        onThemeChanged: @escaping (OverlayTheme) -> Void,
        onHintsChanged: @escaping (Bool) -> Void,
        onPopupChanged: @escaping (PopupSettings) -> Void,
        onScenariosChanged: @escaping (AgentScenarioSettings) -> Void
    ) {
        self.popup = popup
        self.onPopupChanged = onPopupChanged
        self.onHintsChanged = onHintsChanged
        self.coordinator = coordinator
        self.onHotkeyChanged = onHotkeyChanged
        self.onThemeChanged = onThemeChanged
        recorder = HotkeyRecorderView()
        enabledToggle = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
        feedback = NSTextField(labelWithString: "")
        agentsView = AgentSettingsView(settings: scenarios, onChange: onScenariosChanged)
        window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
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
        recorder.onCancel = { [weak self] in
            self?.refreshFromCoordinator()
        }
        enabledToggle.target = self
        enabledToggle.action = #selector(enabledToggled)
        themePicker.addItems(withTitles: OverlayTheme.allCases.map(\.displayName))
        themePicker.selectItem(at: OverlayTheme.allCases.firstIndex(of: theme) ?? 0)
        themePicker.target = self
        themePicker.action = #selector(themePicked)
        hintsToggle.state = showsHints ? .on : .off
        hintsToggle.target = self
        hintsToggle.action = #selector(hintsToggled)
        popupToggle.target = self
        popupToggle.action = #selector(popupToggled)
        popupSeconds.delegate = self
        refreshPopup()
        refreshFromCoordinator()
    }

    func show() {
        refreshFromCoordinator()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        // Nothing focused: recording starts only when the field is clicked.
        window.makeFirstResponder(nil)
    }

    // MARK: - Layout

    private func makeContentView() -> NSView {
        let tabs = NSTabView()
        tabs.translatesAutoresizingMaskIntoConstraints = false
        for (title, view) in [
            ("General", pane(generalSection())),
            ("Appearance", pane(appearanceSection())),
            ("Notifications", pane(notificationSection())),
            ("Agents", agentsView as NSView),
        ] {
            let item = NSTabViewItem(identifier: title)
            item.label = title
            item.view = view
            tabs.addTabViewItem(item)
        }

        let content = NSView()
        content.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            tabs.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            tabs.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            tabs.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        return content
    }

    /// A tab's contents, pinned to its top edge.
    private func pane(_ stack: NSStackView) -> NSView {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        let view = NSView()
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
        ])
        return view
    }

    private func generalSection() -> NSStackView {
        let title = label("Summon hotkey", font: .systemFont(ofSize: 13, weight: .semibold))
        recorder.translatesAutoresizingMaskIntoConstraints = false

        let help = label(
            "Click to record, then press ⌘⌃⌥⇧ + a key. Esc cancels.",
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

        let stack = NSStackView(views: [title, recorder, help, enabledToggle, feedback, buttons])
        NSLayoutConstraint.activate([
            recorder.widthAnchor.constraint(equalTo: stack.widthAnchor),
            recorder.heightAnchor.constraint(equalToConstant: 44),
        ])
        return stack
    }

    private func appearanceSection() -> NSStackView {
        let themeTitle = label("Overlay theme", font: .systemFont(ofSize: 13, weight: .semibold))
        let themeHelp = label(
            "Applies immediately; the overlay shows a preview.",
            font: .systemFont(ofSize: 11),
            color: .secondaryLabelColor
        )
        let stack = NSStackView(views: [themeTitle, themePicker, themeHelp, hintsToggle])
        stack.setCustomSpacing(20, after: themeHelp)
        return stack
    }

    private func notificationSection() -> NSStackView {
        let popupTitle = label("Pop-up", font: .systemFont(ofSize: 13, weight: .semibold))
        popupSeconds.alignment = .right
        popupSeconds.widthAnchor.constraint(equalToConstant: 56).isActive = true
        let secondsRow = NSStackView(views: [
            label("Stay on screen for", font: .systemFont(ofSize: 13)), popupSeconds,
            label("seconds", font: .systemFont(ofSize: 13)),
        ])
        secondsRow.orientation = .horizontal
        secondsRow.spacing = 6
        let popupHelp = label(
            "Hovering the pop-up keeps it open. The menu bar counts unread runs either way;\nruns you watched finish are listed without a dot or a pop-up.",
            font: .systemFont(ofSize: 11),
            color: .secondaryLabelColor
        )
        return NSStackView(views: [popupTitle, popupToggle, secondsRow, popupHelp])
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

    private func refreshPopup() {
        popupToggle.state = popup.isEnabled ? .on : .off
        popupSeconds.stringValue = ResolvedConfiguration.secondsText(popup.seconds)
        popupSeconds.isEnabled = popup.isEnabled
    }

    // MARK: - Actions

    @objc private func popupToggled() {
        popup.isEnabled = popupToggle.state == .on
        refreshPopup()
        onPopupChanged(popup)
    }

    /// Saves every usable value as it is typed: Return belongs to `Apply`, so
    /// the field cannot wait for it.
    func controlTextDidChange(_ notification: Notification) {
        guard let seconds = PopupSettings.seconds(from: popupSeconds.stringValue),
            seconds != popup.seconds
        else { return }
        popup.seconds = seconds
        onPopupChanged(popup)
    }

    /// Leaving the field with an unusable value snaps it back.
    func controlTextDidEndEditing(_ notification: Notification) {
        refreshPopup()
    }

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

    /// The `↑↓ move · ↩ open …` footer shown while typing in the overlay.
    @objc private func hintsToggled() {
        onHintsChanged(hintsToggle.state == .on)
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

/// island is an accessory app with no main menu, so nothing routes ⌘W to the
/// window; this handles ⌘W and Esc itself (see `SettingsKey`). The recorder
/// gets the keys first while it is recording.
@MainActor
final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        return closeIfAsked(by: event)
    }

    /// Esc (or ⌘W) that no control consumed — e.g. nothing is focused.
    override func keyDown(with event: NSEvent) {
        if !closeIfAsked(by: event) { super.keyDown(with: event) }
    }

    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }

    private func closeIfAsked(by event: NSEvent) -> Bool {
        let action = SettingsKey.action(
            isRecording: false,
            keyCode: UInt32(event.keyCode),
            modifiers: HotkeyRecorderView.modifiers(from: event.modifierFlags)
        )
        guard action == .closeWindow else { return false }
        performClose(nil)
        return true
    }
}
