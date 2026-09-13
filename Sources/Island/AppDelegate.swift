import AppKit
import IslandCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let configuration: ResolvedConfiguration

    private var panel: OverlayPanel?
    private var registrar: HotkeyRegistrar?
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

        registrar = HotkeyRegistrar(spec: configuration.hotkey.spec) { [weak self] in
            MainActor.assumeIsolated {
                self?.showOverlay()
            }
        }
        if registrar == nil {
            log(
                "failed to register \(configuration.hotkey.spec.displayString); is another app holding it?"
            )
        }

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
        log("island POC starting")
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
