import AppKit
import IslandCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configuration: ResolvedConfiguration

    private var panel: OverlayPanel?
    private var registrar: HotkeyRegistrar?
    private var settings: HotkeySettingsCoordinator?
    private var settingsWindow: HotkeySettingsWindow?
    private var statusItem: StatusItemController?
    private var monitor: AgentMonitor?
    private var inbox: AgentInbox?
    private var overlayContent: OverlayContentView?
    private var reopenExecutor: AgentReopenExecutor?
    /// Serial, so two quick clicks cannot interleave their tmux/AppleScript steps.
    private let reopenQueue = DispatchQueue(label: "island.reopen", qos: .userInitiated)
    private var automationDenials = AutomationDenials()
    private let overlayStore = UserDefaultsOverlayStore()
    private let popupStore = UserDefaultsPopupStore()
    /// Whether a finished run pops the overlay up, and for how long.
    private var popup: PopupSettings
    /// Separate from `reopenQueue`: a pending automation prompt there must not
    /// stall the monitor.
    private let visibilityQueue = DispatchQueue(label: "island.visibility", qos: .utility)
    private var hideTask: Task<Void, Never>?

    init(configuration: ResolvedConfiguration) {
        self.configuration = configuration
        popup = popupStore.load(fallback: configuration.duration)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        reportConfiguration()
        VSCodeExtensionInstaller.installIfNeeded()
        reopenExecutor = AgentReopenExecutor { [weak self] check in
            DispatchQueue.main.async { self?.recordAutomation(check) }
        }

        let content = OverlayContentView(
            frame: NSRect(
                x: 0, y: 0,
                width: OverlayContentView.width,
                height: 120
            )
        )
        content.setTheme(overlayStore.load())
        content.setShowsHints(overlayStore.loadShowsHints())
        content.onOpenSettings = { [weak self] in
            self?.hideOverlay(reason: "overlay hidden to open settings")
            self?.settingsWindow?.show()
        }
        content.onSelect = { [weak self] entry in self?.selectTask(entry) }
        content.onHoverChange = { [weak self] hovering in self?.setOverlayHovered(hovering) }
        content.onDismiss = { [weak self] in self?.hideOverlay(reason: "overlay dismissed") }
        content.onHeightChange = { [weak self] height in
            self?.panel?.setContentSize(width: OverlayContentView.width, height: height)
        }
        overlayContent = content
        let panel = OverlayPanel(contentView: content)
        panel.setContentSize(width: OverlayContentView.width, height: content.preferredHeight)
        // Clicking anywhere else dismisses a summoned overlay.
        panel.onResignKey = { [weak self] in
            // Hiding clears acceptsKeyboard first, so this does not re-enter.
            guard self?.panel?.acceptsKeyboard == true else { return }
            self?.hideOverlay(reason: "overlay hidden after losing focus")
        }
        self.panel = panel

        let registrar = HotkeyRegistrar { [weak self] in
            MainActor.assumeIsolated {
                self?.toggleOverlay()
            }
        }
        self.registrar = registrar

        let settings = HotkeySettingsCoordinator(
            current: configuration.hotkey.spec,
            isEnabled: configuration.hotkeyEnabled,
            store: UserDefaultsHotkeyStore(),
            registrar: registrar
        )
        self.settings = settings

        do {
            try settings.start()
            if settings.isEnabled {
                log("hotkey registered: \(settings.current.displayString)")
            } else {
                log("hotkey is switched off; summon from the menu bar icon")
            }
        } catch {
            log(
                "failed to register \(settings.current.displayString): \(error.localizedDescription)"
            )
        }

        let settingsWindow = HotkeySettingsWindow(
            coordinator: settings,
            theme: content.theme,
            showsHints: content.showsHints,
            popup: popup,
            onHotkeyChanged: { [weak self] spec, enabled in
                self?.log("hotkey changed to \(spec.displayString) (enabled: \(enabled))")
                self?.statusItem?.setHotkey(spec, source: .menu)
                self?.statusItem?.setHotkeyEnabled(enabled)
            },
            onThemeChanged: { [weak self] theme in self?.setTheme(theme) },
            onHintsChanged: { [weak self] shows in self?.setShowsHints(shows) },
            onPopupChanged: { [weak self] popup in self?.setPopup(popup) }
        )
        self.settingsWindow = settingsWindow

        statusItem = StatusItemController(
            hotkey: settings.current,
            hotkeySource: configuration.hotkey.source,
            hotkeyEnabled: settings.isEnabled,
            popup: popup,
            loginItem: LoginItemController(),
            onSummon: { [weak self] in self?.showOverlay(interactive: true) },
            onToggleHotkey: { [weak self] enabled in self?.setHotkeyEnabled(enabled) },
            onSelectTask: { [weak self] id in self?.selectTask(id: id) },
            onOpenSettings: { [weak self] in self?.settingsWindow?.show() },
            onQuit: { NSApp.terminate(nil) }
        )
        log("menu bar item installed; launch at login: \(LoginItemController().status.rawValue)")

        startAgentMonitor()

        // Show once at launch so the POC is visible without hunting for the hotkey.
        if popup.isEnabled { showOverlay() }
    }

    /// Watches the local agent session stores and mirrors the unread count into
    /// the menu bar. PLAN § Design: only runs that finish while island is up are
    /// surfaced, so no history is ingested here.
    private func startAgentMonitor() {
        let inbox = AgentInbox(limit: configuration.taskLimit)
        self.inbox = inbox
        let monitor = AgentMonitor(
            scanner: .standard(sqlite: ProcessSQLiteQuerying()),
            inbox: inbox,
            inView: { [weak self] tasks in await self?.tasksInView(tasks) ?? [] },
            onChange: { [weak self] alerted in
                self?.refreshAgentUI()
                // PLAN § Goal: a finished run pops the overlay with its summary —
                // unless the user watched it finish, or switched pop-ups off.
                if alerted, self?.popup.isEnabled == true { self?.showOverlay() }
            }
        )
        self.monitor = monitor
        monitor.start()
        refreshAgentUI()
        // Walking back to a finished task clears its dot promptly.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.monitor?.poll() }
        }
    }

    /// Which of `tasks` the user is looking at: the frontmost app is read here,
    /// on the main thread; the shelling out happens on `visibilityQueue`.
    private func tasksInView(_ tasks: [AgentTask]) async -> Set<String> {
        guard let executor = reopenExecutor else { return [] }
        let frontmost = NSWorkspace.shared.frontmostApplication.map {
            RunningApp(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier)
        }
        let queue = visibilityQueue
        return await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: executor.tasksInView(tasks, frontmost: frontmost))
            }
        }
    }

    /// Pushes the inbox into the three places it shows up: the menu bar badge,
    /// the overlay list, and the menu's task section.
    private func refreshAgentUI() {
        guard let inbox else { return }
        let entries = inbox.visibleEntries
        statusItem?.setUnreadCount(inbox.unreadCount)
        statusItem?.setTasks(entries)
        overlayContent?.update(
            entries: entries,
            unread: inbox.unreadCount,
            hotkey: settings?.current ?? configuration.hotkey.spec
        )
        log("agent tasks: \(inbox.unreadCount) unread, \(inbox.allEntries.count) tracked")
    }

    // MARK: - Task selection

    private func selectTask(id: String) {
        guard let entry = inbox?.allEntries.first(where: { $0.id == id }) else { return }
        selectTask(entry)
    }

    /// PLAN § Design: opening a task marks it read (the red dot clears, the row
    /// stays) and then does its best to put the user back in that session.
    private func selectTask(_ entry: AgentInbox.Entry) {
        inbox?.markRead(id: entry.id)
        refreshAgentUI()
        // PLAN § Design / 下拉框 UX #2: picking a task dismisses the list.
        hideOverlay(reason: "overlay hidden after selecting a task")
        guard let executor = reopenExecutor else { return }
        let task = entry.task
        // Off the main thread: it shells out, and osascript waits for however
        // long the user takes to answer the automation prompt.
        reopenQueue.async {
            let action = executor.plan(for: task)
            executor.perform(action, for: task)
            FileHandle.standardError.write(
                Data("[island] selected \(task.title) -> \(action)\n".utf8))
        }
    }

    private func recordAutomation(_ check: AutomationCheck) {
        let before = automationDenials
        automationDenials.record(check)
        guard automationDenials != before else { return }
        statusItem?.setAutomationHint(automationDenials.menuTitle)
        log("automation for \(check.appName): \(check.authorized ? "allowed" : "denied")")
    }

    /// `interactive` (hotkey, menu): the panel takes the keyboard and stays until
    /// dismissed. Otherwise (a run just finished) it never takes focus and
    /// hides itself after the configured duration. A pop-up never downgrades an
    /// overlay the user is already typing into.
    private func showOverlay(interactive: Bool = false) {
        guard let panel, let content = overlayContent else { return }
        if panel.isKeyWindow && !interactive { return }

        hideTask?.cancel()
        hideTask = nil
        panel.acceptsKeyboard = interactive
        content.setKeyboardMode(interactive)
        panel.setContentSize(width: OverlayContentView.width, height: content.preferredHeight)
        if interactive {
            panel.makeKeyAndOrderFront(nil)
            content.focusQuery()
            log("overlay summoned for keyboard use")
        } else {
            panel.orderFrontRegardless()
            log("overlay shown, hiding in \(ResolvedConfiguration.secondsText(popup.seconds))s")
            scheduleHide()
        }
    }

    /// Settings picked a new theme: apply, remember, and show a preview.
    private func setTheme(_ theme: OverlayTheme) {
        overlayStore.save(theme)
        overlayContent?.setTheme(theme)
        log("overlay theme: \(theme.rawValue)")
        showOverlay()
    }

    /// Settings changed the pop-up: remember it; the next pop-up uses it.
    private func setPopup(_ popup: PopupSettings) {
        self.popup = popup
        popupStore.save(popup)
        statusItem?.setPopup(popup)
        log(
            "pop-up: \(popup.isEnabled ? "on" : "off"), \(ResolvedConfiguration.secondsText(popup.seconds))s"
        )
    }

    /// Settings switched the keyboard-mode footer on or off.
    private func setShowsHints(_ shows: Bool) {
        overlayStore.saveShowsHints(shows)
        overlayContent?.setShowsHints(shows)
        log("overlay keyboard hints: \(shows ? "on" : "off")")
    }

    /// Hovering a passive overlay pauses the auto-hide so the list stays
    /// clickable; leaving restarts it. A summoned overlay has no timer.
    private func setOverlayHovered(_ hovering: Bool) {
        guard panel?.acceptsKeyboard == false else { return }
        if hovering {
            hideTask?.cancel()
            hideTask = nil
        } else if panel?.isVisible == true {
            scheduleHide()
        }
    }

    private func scheduleHide(after seconds: TimeInterval? = nil) {
        let seconds = seconds ?? popup.seconds
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
            self?.log("overlay hidden")
        }
    }

    /// PLAN § Scope #5: the hotkey toggles the overlay, so a press while it is
    /// on screen dismisses it instead of only restarting the auto-hide timer.
    private func toggleOverlay() {
        switch OverlayToggle.hotkeyPress(isOverlayVisible: panel?.isVisible ?? false) {
        case .show:
            showOverlay(interactive: true)
        case .hide:
            hideOverlay(reason: "overlay hidden by hotkey")
        }
    }

    private func hideOverlay(reason: String = "overlay hidden") {
        hideTask?.cancel()
        hideTask = nil
        guard let panel, panel.isVisible else { return }
        panel.acceptsKeyboard = false
        panel.orderOut(nil)
        log(reason)
    }

    /// Switches the global hotkey on or off, from either the menu or the
    /// settings window. The status item is always re-synced from the
    /// coordinator, because a refused re-enable must stay visually off.
    private func setHotkeyEnabled(_ enabled: Bool) {
        guard let settings else { return }
        switch settings.setEnabled(enabled) {
        case .enabled(let spec):
            log("hotkey enabled: \(spec.displayString)")
        case .disabled:
            log("hotkey switched off")
        case .registrationFailed(let reason):
            log("could not enable hotkey: \(reason)")
        }
        statusItem?.setHotkeyEnabled(settings.isEnabled)
    }

    private func reportConfiguration() {
        log("island starting")
        for line in configuration.summary.split(separator: "\n") {
            log(String(line))
        }
    }

    /// Written to stderr, which is only visible when launch happens from a
    /// terminal — the way the POC is meant to be run.
    private func log(_ message: String) {
        FileHandle.standardError.write(Data("[island] \(message)\n".utf8))
    }
}
