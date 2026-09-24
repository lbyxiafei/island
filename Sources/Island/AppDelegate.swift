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
    private var hideTask: Task<Void, Never>?

    init(configuration: ResolvedConfiguration) {
        self.configuration = configuration
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        reportConfiguration()

        let panel = OverlayPanel(
            contentView: OverlayContent.makeView(
                hotkey: configuration.hotkey.spec,
                duration: configuration.duration
            )
        )
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

        let settingsWindow = HotkeySettingsWindow(coordinator: settings) {
            [weak self] spec, enabled in
            self?.log("hotkey changed to \(spec.displayString) (enabled: \(enabled))")
            self?.statusItem?.setHotkey(spec, source: .menu)
            self?.statusItem?.setHotkeyEnabled(enabled)
        }
        self.settingsWindow = settingsWindow

        statusItem = StatusItemController(
            hotkey: settings.current,
            hotkeySource: configuration.hotkey.source,
            hotkeyEnabled: settings.isEnabled,
            durationSeconds: configuration.duration.seconds,
            loginItem: LoginItemController(),
            onSummon: { [weak self] in self?.showOverlay() },
            onToggleHotkey: { [weak self] enabled in self?.setHotkeyEnabled(enabled) },
            onOpenSettings: { [weak self] in self?.settingsWindow?.show() },
            onQuit: { NSApp.terminate(nil) }
        )
        log("menu bar item installed; launch at login: \(LoginItemController().status.rawValue)")

        startAgentMonitor()

        // Show once at launch so the POC is visible without hunting for the hotkey.
        showOverlay()
    }

    /// Watches the local agent session stores and mirrors the unread count into
    /// the menu bar. PLAN § Design: only runs that finish while island is up are
    /// surfaced, so no history is ingested here.
    private func startAgentMonitor() {
        let inbox = AgentInbox(limit: configuration.taskLimit)
        self.inbox = inbox
        let monitor = AgentMonitor(scanner: .standard(), inbox: inbox) { [weak self] in
            guard let count = self?.inbox?.unreadCount else { return }
            self?.statusItem?.setUnreadCount(count)
            self?.log("agent tasks: \(count) unread, \(inbox.allEntries.count) tracked")
        }
        self.monitor = monitor
        monitor.start()
    }

    private func showOverlay() {
        guard let panel else { return }
        panel.positionNearTopOfScreen()
        panel.orderFrontRegardless()
        log("overlay shown, hiding in \(configuration.duration.seconds)s")

        let seconds = configuration.duration.seconds
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
            showOverlay()
        case .hide:
            hideOverlay()
        }
    }

    private func hideOverlay() {
        hideTask?.cancel()
        hideTask = nil
        panel?.orderOut(nil)
        log("overlay hidden by hotkey")
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
