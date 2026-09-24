import AppKit
import IslandCore

/// A click-to-record control for the global hotkey.
///
/// The user clicks it, then presses the combination they want; the raw
/// `NSEvent` is turned into a `HotkeySpec` by `HotkeySpec.captured`. While the
/// view is first responder it also swallows `performKeyEquivalent`, so combos
/// like ⌘Q that the window would otherwise route to the menu get recorded too.
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

    override var acceptsFirstResponder: Bool { true }

    private var isRecording: Bool { window?.firstResponder === self }

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
        if let spec {
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
        window?.makeFirstResponder(self)
    }

    override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return true
    }

    override func keyDown(with event: NSEvent) {
        if !record(event) { reject() }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return false }
        return record(event)
    }

    /// Returns true when the event produced a usable hotkey.
    @discardableResult
    private func record(_ event: NSEvent) -> Bool {
        let modifiers = Self.modifiers(from: event.modifierFlags)
        guard let spec = HotkeySpec.captured(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        else {
            return false
        }
        self.spec = spec
        onRecord?(spec)
        return true
    }

    private func reject() {
        NSSound.beep()
        needsDisplay = true
        onReject?()
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> Set<HotkeySpec.Modifier> {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Set<HotkeySpec.Modifier> = []
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }
}
