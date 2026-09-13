import AppKit
import IslandCore

/// The settings window behind the menu's `Settings…` item. Scope is deliberately
/// minimal (PLAN § Scope #3): set the summon hotkey, or reset it.
///
/// It is a regular, key-capable window — unlike the overlay — because the user
/// has to be able to type into it.
@MainActor
final class HotkeySettingsWindow: NSObject, NSTextFieldDelegate {
    private let coordinator: HotkeySettingsCoordinator
    private let onHotkeyChanged: (HotkeySpec) -> Void
    private let window: NSWindow
    private let field: NSTextField
    private let feedback: NSTextField

    init(coordinator: HotkeySettingsCoordinator, onHotkeyChanged: @escaping (HotkeySpec) -> Void) {
        self.coordinator = coordinator
        self.onHotkeyChanged = onHotkeyChanged
        field = NSTextField(string: coordinator.current.specText)
        feedback = NSTextField(labelWithString: "")
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 172),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "island settings"
        window.isReleasedWhenClosed = false
        window.contentView = makeContentView()
        field.delegate = self
        refreshFeedback()
    }

    func show() {
        field.stringValue = coordinator.current.specText
        refreshFeedback()
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field)
    }

    // MARK: - Layout

    private func makeContentView() -> NSView {
        let title = label("Summon hotkey", font: .systemFont(ofSize: 13, weight: .semibold))
        field.placeholderString = HotkeyConfiguration.fallbackText
        field.translatesAutoresizingMaskIntoConstraints = false

        let help = label(
            "modifiers: cmd / ctrl / opt / shift (or ⌘⌃⌥⇧) + a key, e.g. cmd+ctrl+,",
            font: .systemFont(ofSize: 11),
            color: .secondaryLabelColor
        )
        feedback.font = .systemFont(ofSize: 11)
        feedback.translatesAutoresizingMaskIntoConstraints = false

        let apply = NSButton(title: "Apply", target: self, action: #selector(applyTapped))
        apply.keyEquivalent = "\r"
        let reset = NSButton(
            title: "Reset to default", target: self, action: #selector(resetTapped))
        let buttons = NSStackView(views: [reset, apply])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let stack = NSStackView(views: [title, field, help, feedback, buttons])
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
            field.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        return content
    }

    private func label(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        return label
    }

    // MARK: - Actions

    @objc private func applyTapped() {
        switch coordinator.apply(field.stringValue) {
        case .applied(let spec):
            field.stringValue = spec.specText
            feedback.textColor = .secondaryLabelColor
            feedback.stringValue = "saved: \(spec.displayString) — already active"
            onHotkeyChanged(spec)
        case .invalidText(let error):
            showFailure("cannot use that: \(describe(error))")
        case .registrationFailed(let reason):
            showFailure("macOS refused it (\(reason)); kept \(coordinator.current.displayString)")
        }
    }

    @objc private func resetTapped() {
        field.stringValue = HotkeyConfiguration.fallbackText
        applyTapped()
    }

    func controlTextDidChange(_ notification: Notification) {
        refreshFeedback()
    }

    private func refreshFeedback() {
        do {
            let spec = try HotkeySpec.parse(field.stringValue)
            feedback.textColor = .secondaryLabelColor
            feedback.stringValue = "will bind \(spec.displayString)"
        } catch let error as HotkeySpecError {
            feedback.textColor = .systemRed
            feedback.stringValue = describe(error)
        } catch {
            feedback.stringValue = ""
        }
    }

    private func showFailure(_ message: String) {
        feedback.textColor = .systemRed
        feedback.stringValue = message
    }

    private func describe(_ error: HotkeySpecError) -> String {
        switch error {
        case .empty: return "type a hotkey first"
        case .missingModifier: return "needs at least one modifier, e.g. cmd+ctrl+,"
        case .unknownModifier(let name): return "unknown modifier \"\(name)\""
        case .unknownKey(let name): return "unknown key \"\(name)\""
        }
    }
}
