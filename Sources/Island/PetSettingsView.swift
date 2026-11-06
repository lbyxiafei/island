import AppKit
import IslandCore

/// Settings → Pet: the on/off switch, the look, how see-through the pet is
/// while idle, and whether it moves. State lives in `PetSettings`.
@MainActor
final class PetSettingsView: NSView {
    private var settings: PetSettings
    private let onChange: (PetSettings) -> Void

    private let enabledToggle = NSButton(
        checkboxWithTitle: "Show the pet", target: nil, action: nil)
    private let avatarPicker = NSPopUpButton()
    private let opacitySlider = NSSlider(
        value: 0.4, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let opacityLabel = NSTextField(labelWithString: "")
    private let animatesToggle = NSButton(
        checkboxWithTitle: "Bob gently, hop when a run finishes", target: nil, action: nil)

    private static let customTag = 1000

    init(settings: PetSettings, onChange: @escaping (PetSettings) -> Void) {
        self.settings = settings
        self.onChange = onChange
        super.init(frame: .zero)
        build()
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    func set(_ settings: PetSettings) {
        self.settings = settings
        refresh()
    }

    private func build() {
        for control in [enabledToggle, animatesToggle] {
            control.target = self
            control.action = #selector(togglesChanged)
        }
        avatarPicker.target = self
        avatarPicker.action = #selector(avatarPicked)
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged)
        opacitySlider.isContinuous = true
        opacitySlider.widthAnchor.constraint(equalToConstant: 200).isActive = true
        opacityLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        opacityLabel.widthAnchor.constraint(equalToConstant: 44).isActive = true

        let title = Self.label("Pet mode", size: 13, weight: .semibold)
        let intro = Self.label(
            "A little companion that stays on top of every window. When a run finishes it shows\nthe title in a bubble beside it; click the bubble to jump back, × to dismiss it.\nWhile the pet is on, the overlay no longer pops up by itself (the hotkey still works).",
            size: 11, color: .secondaryLabelColor)

        let avatarRow = Self.row([Self.label("Looks like", size: 13), avatarPicker])
        let opacityRow = Self.row([
            Self.label("Idle opacity", size: 13), opacitySlider, opacityLabel,
        ])
        let opacityHelp = Self.label(
            "0% hides it until a run finishes. Hovering or an unread run shows it in full.",
            size: 11, color: .secondaryLabelColor)
        let usage = Self.label(
            "Drag the pet anywhere; it remembers the spot. Click it for the task list, right-click\nfor more.",
            size: 11, color: .secondaryLabelColor)

        let stack = NSStackView(views: [
            title, intro, enabledToggle, avatarRow, opacityRow, opacityHelp, animatesToggle, usage,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(14, after: intro)
        stack.setCustomSpacing(14, after: opacityHelp)
        stack.setCustomSpacing(14, after: animatesToggle)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 20),
        ])
    }

    private func refresh() {
        enabledToggle.state = settings.isEnabled ? .on : .off
        animatesToggle.state = settings.animates ? .on : .off
        opacitySlider.doubleValue = settings.idleOpacity
        opacityLabel.stringValue = "\(Int((settings.idleOpacity * 100).rounded()))%"

        avatarPicker.removeAllItems()
        for (index, character) in PetCharacter.allCases.enumerated() {
            avatarPicker.addItem(withTitle: "\(character.emoji)  \(character.displayName)")
            avatarPicker.lastItem?.tag = index
        }
        avatarPicker.menu?.addItem(.separator())
        if case .image(let path) = settings.avatar {
            avatarPicker.addItem(withTitle: "🖼  \((path as NSString).lastPathComponent)")
            avatarPicker.lastItem?.tag = Self.customTag + 1
        }
        avatarPicker.addItem(withTitle: "Choose an image…")
        avatarPicker.lastItem?.tag = Self.customTag
        switch settings.avatar {
        case .builtIn(let character):
            avatarPicker.selectItem(withTag: PetCharacter.allCases.firstIndex(of: character) ?? 0)
        case .image:
            avatarPicker.selectItem(withTag: Self.customTag + 1)
        }
    }

    @objc private func togglesChanged() {
        settings.isEnabled = enabledToggle.state == .on
        settings.animates = animatesToggle.state == .on
        onChange(settings)
    }

    @objc private func opacityChanged() {
        settings.idleOpacity = (opacitySlider.doubleValue * 20).rounded() / 20
        opacityLabel.stringValue = "\(Int((settings.idleOpacity * 100).rounded()))%"
        onChange(settings)
    }

    @objc private func avatarPicked() {
        let tag = avatarPicker.selectedTag()
        if tag == Self.customTag {
            chooseImage()
            return
        }
        guard PetCharacter.allCases.indices.contains(tag) else { return }
        settings.avatar = .builtIn(PetCharacter.allCases[tag])
        onChange(settings)
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message =
            "Pick a picture for your pet (a square PNG with a transparent background looks best)."
        if panel.runModal() == .OK, let url = panel.url {
            settings.avatar = .image(path: url.path)
            onChange(settings)
        }
        refresh()
    }

    private static func row(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    private static func label(
        _ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
        color: NSColor = .labelColor
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        return label
    }
}
