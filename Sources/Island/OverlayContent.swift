import AppKit
import IslandCore

/// Placeholder body of the overlay. The POC only needs something visible to
/// prove the panel pops up on the hotkey and disappears on its own.
@MainActor
enum OverlayContent {
    static func makeView(hotkey: HotkeySpec, duration: OverlayDuration) -> NSView {
        let effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 18
        effectView.layer?.masksToBounds = true

        let title = makeLabel(
            "island — POC overlay",
            font: .systemFont(ofSize: 15, weight: .semibold)
        )
        let hint = makeLabel(
            "press \(hotkey.displayString) to summon · hides itself in \(format(duration.seconds))s",
            font: .systemFont(ofSize: 12),
            color: .secondaryLabelColor
        )

        let stack = NSStackView(views: [title, hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: effectView.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            stack.leadingAnchor.constraint(
                greaterThanOrEqualTo: effectView.leadingAnchor, constant: 16),
        ])

        return effectView
    }

    private static func makeLabel(
        _ text: String,
        font: NSFont,
        color: NSColor = .labelColor
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.alignment = .center
        return label
    }

    /// `5` instead of `5.0`, `2.5` stays `2.5`.
    private static func format(_ seconds: TimeInterval) -> String {
        String(format: "%g", seconds)
    }
}
