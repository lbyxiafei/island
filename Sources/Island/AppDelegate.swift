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
                self?.showOverlay()
            }
        }
        self.registrar = registrar

        let settings = HotkeySettingsCoordinator(
            current: configuration.hotkey.spec,
            store: UserDefaultsHotkeyStore(),
            registrar: registrar
        )
        self.settings = settings

        do {
            try registrar.register(configuration.hotkey.spec)
            log("hotkey registered: \(configuration.hotkey.spec.displayString)")
        } catch {
            log(
                "failed to register \(configuration.hotkey.spec.displayString): \(error.localizedDescription)"
            )
        }

        let settingsWindow = HotkeySettingsWindow(coordinator: settings) { [weak self] spec in
            self?.log("hotkey changed to \(spec.displayString) (\(spec.specText))")
            self?.statusItem?.setHotkey(spec, source: .menu)
        }
        self.settingsWindow = settingsWindow

        statusItem = StatusItemController(
            hotkey: configuration.hotkey.spec,
            hotkeySource: configuration.hotkey.source,
            durationSeconds: configuration.duration.seconds,
            loginItem: LoginItemController(),
            onSummon: { [weak self] in self?.showOverlay() },
            onOpenSettings: { [weak self] in self?.settingsWindow?.show() },
            onQuit: { NSApp.terminate(nil) }
        )
        log("menu bar item installed; launch at login: \(LoginItemController().status.rawValue)")

        // Show once at launch so the POC is visible without hunting for the hotkey.
        showOverlay()
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
