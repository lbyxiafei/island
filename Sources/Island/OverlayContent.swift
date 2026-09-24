import AppKit
import IslandCore

/// The overlay body: a header plus one clickable row per finished agent run.
///
/// It stays inside a non-activating panel (`OverlayPanel`), so clicking a row
/// must not require the window to become key — rows handle `mouseUp`
/// themselves, and hovering pauses the auto-hide so the user can read and pick.
@MainActor
final class OverlayContentView: NSView {
    static let width: CGFloat = 420
    static let rowHeight: CGFloat = 46
    static let emptyHeight: CGFloat = 92

    var onSelect: ((AgentInbox.Entry) -> Void)?
    var onHoverChange: ((Bool) -> Void)?

    private let effectView = NSVisualEffectView()
    private let header = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "")
    private let list = NSStackView()
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("OverlayContentView is created in code only")
    }

    static func height(forEntryCount count: Int, limit: Int) -> CGFloat {
        guard count > 0 else { return emptyHeight }
        let shown = min(count, max(1, limit))
        return 58 + CGFloat(shown) * rowHeight + 16
    }

    func update(entries: [AgentInbox.Entry], unread: Int, limit: Int, hotkey: HotkeySpec) {
        for view in list.arrangedSubviews { view.removeFromSuperview() }

        if unread > 0 {
            header.stringValue = "island — \(unread) unread"
            header.textColor = .labelColor
        } else {
            header.stringValue = "island"
            header.textColor = .labelColor
        }

        if entries.isEmpty {
            let empty = NSTextField(labelWithString: "No finished agent runs yet")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .secondaryLabelColor
            empty.alignment = .center
            list.addArrangedSubview(empty)
            empty.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
        } else {
            for entry in entries.prefix(max(1, limit)) {
                let row = OverlayTaskRowView(entry: entry)
                row.onClick = { [weak self] picked in self?.onSelect?(picked) }
                list.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: list.widthAnchor).isActive = true
                row.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true
            }
        }

        hint.stringValue = "click a task to jump back · \(hotkey.displayString) to hide"
    }

    // MARK: - Layout

    private func build() {
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 18
        effectView.layer?.masksToBounds = true
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)

        header.font = .systemFont(ofSize: 13, weight: .semibold)
        header.textColor = .labelColor
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor

        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0

        let stack = NSStackView(views: [header, list, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(stack)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor),
            effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(
                lessThanOrEqualTo: effectView.bottomAnchor, constant: -12),
            list.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }
}

/// One task row: unread dot, title, and a `agent · time · directory` subtitle.
@MainActor
final class OverlayTaskRowView: NSView {
    let entry: AgentInbox.Entry
    var onClick: ((AgentInbox.Entry) -> Void)?

    private var trackingArea: NSTrackingArea?

    init(entry: AgentInbox.Entry) {
        self.entry = entry
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("OverlayTaskRowView is created in code only")
    }

    private func build() {
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5
        dot.layer?.backgroundColor =
            entry.isRead ? NSColor.clear.cgColor : NSColor.systemRed.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7),
        ])

        let title = NSTextField(labelWithString: entry.task.title)
        title.font = .systemFont(ofSize: 13, weight: entry.isRead ? .regular : .semibold)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let subtitle = NSTextField(labelWithString: Self.subtitle(for: entry.task))
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let text = NSStackView(views: [title, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1

        let row = NSStackView(views: [dot, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private static func subtitle(for task: AgentTask) -> String {
        var pieces = [task.agent.displayName]
        pieces.append(Self.relative(task.completedAt))
        if let cwd = task.cwd, !cwd.isEmpty {
            pieces.append((cwd as NSString).lastPathComponent)
        }
        return pieces.joined(separator: " · ")
    }

    private static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Interaction

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?(entry)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
