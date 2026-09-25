import AppKit
import IslandCore

/// A click-to-record control for the global hotkey.
///
/// Recording is explicit: it starts only when the user clicks the field, ends
/// after one combination, and Esc or clicking elsewhere cancels it and puts
/// the previous value back. So opening settings and pressing ⌘W closes the
/// window instead of rebinding the hotkey. While recording, the view also
/// swallows `performKeyEquivalent`, so ⌘-combos get recorded too. What each
/// key does is decided by `SettingsKey.action` (IslandCore, tested).
@MainActor
final class HotkeyRecorderView: NSView {
    /// The recorded combination, or nil when nothing is bound.
    var spec: HotkeySpec? {
        didSet { needsDisplay = true }
    }

    /// Fired when a new combination is recorded (not when `spec` is set
    /// programmatically — see `setSpec`).
    var onRecord: ((HotkeySpec) -> Void)?

    /// Fired when the user presses something that cannot be a hotkey, so the
    /// window can explain why instead of staying silent.
    var onReject: (() -> Void)?

    /// Fired when recording ends without a new combination (Esc, click away).
    var onCancel: (() -> Void)?

    private(set) var isRecording = false
    private var specBeforeRecording: HotkeySpec?

    /// Only while recording, so the window never picks the field on its own.
    override var acceptsFirstResponder: Bool { isRecording }

    /// Sets the displayed combination without treating it as a fresh recording.
    func setSpec(_ spec: HotkeySpec?) {
        self.spec = spec
    }

    override func draw(_ dirtyRect: NSRect) {
        let border = isRecording ? NSColor.controlAccentColor : NSColor.separatorColor
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.1) : .controlBackgroundColor)
            .setFill()
        path.fill()
        border.setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()

        let text: String
        let color: NSColor
        if isRecording {
            text = "Press a combination…"
            color = .secondaryLabelColor
        } else if let spec {
            text = spec.displayString
            color = .labelColor
        } else {
            text = "None"
            color = .secondaryLabelColor
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .medium),
            .foregroundColor: color,
        ]
        let size = text.size(withAttributes: attributes)
        let origin = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        text.draw(at: origin, withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        guard !isRecording else { return }
        specBeforeRecording = spec
        isRecording = true
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    /// Clicking another control (or closing the window) cancels a recording.
    override func resignFirstResponder() -> Bool {
        if isRecording { finishRecording(restoring: true) }
        return true
    }

    override func keyDown(with event: NSEvent) {
        if !handle(event) { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        isRecording && handle(event)
    }

    /// Returns true when the event was consumed by the recording.
    private func handle(_ event: NSEvent) -> Bool {
        let action = SettingsKey.action(
            isRecording: isRecording,
            keyCode: UInt32(event.keyCode),
            modifiers: Self.modifiers(from: event.modifierFlags)
        )
        switch action {
        case .record(let recorded):
            spec = recorded
            finishRecording(restoring: false)
            onRecord?(recorded)
        case .reject:
            reject()
        case .cancelRecording:
            finishRecording(restoring: true)
        case .closeWindow, .pass:
            return false
        }
        return true
    }

    private func finishRecording(restoring: Bool) {
        isRecording = false
        if restoring {
            spec = specBeforeRecording
            onCancel?()
        }
        if window?.firstResponder === self { window?.makeFirstResponder(nil) }
        needsDisplay = true
    }

    private func reject() {
        NSSound.beep()
        needsDisplay = true
        onReject?()
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> Set<HotkeySpec.Modifier> {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Set<HotkeySpec.Modifier> = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }
}
