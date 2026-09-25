import AppKit
import IslandCore

/// The overlay body, laid out like Alfred: a query field on top, then one row
/// per finished agent run with its app icon, and `↩` / `⌘N` hints on the right.
///
/// Two modes (see `setKeyboardMode`): when summoned by the user the panel is
/// key and the query field takes typing, arrows, Enter, ⌘1–9 and Esc; when it
/// pops up by itself it never takes focus and rows are clicked with the mouse.
@MainActor
final class OverlayContentView: NSView, NSTextFieldDelegate {
    static let width: CGFloat = 560
    static let rowHeight: CGFloat = 50
    private static let queryHeight: CGFloat = 52
    private static let padding: CGFloat = 10
    private static let hintHeight: CGFloat = 22

    var onSelect: ((AgentInbox.Entry) -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    var onDismiss: (() -> Void)?
    /// The row count changed (typing filters the list), so the panel resizes.
    var onHeightChange: ((CGFloat) -> Void)?

    private(set) var theme = OverlayTheme.fallback
    private var palette = OverlayTheme.fallback.palette(systemIsDark: false)
    private var selection = OverlaySelection(entries: [])
    private var unread = 0
    private var hotkey: HotkeySpec?
    private var isKeyboardMode = false

    private let blurView = NSVisualEffectView()
    private let tintView = NSView()
    private let queryBox = NSView()
    private let queryField = NSTextField()
    private let list = NSStackView()
    private let hint = NSTextField(labelWithString: "")
    private var rowViews: [OverlayTaskRowView] = []
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        build()
        applyPalette()
    }

    required init?(coder: NSCoder) {
        fatalError("OverlayContentView is created in code only")
    }

    var preferredHeight: CGFloat {
        let rows = max(selection.rows.count, 1)
        return Self.padding * 2 + Self.queryHeight + 6 + CGFloat(rows) * Self.rowHeight
            + Self.hintHeight
    }

    func update(entries: [AgentInbox.Entry], unread: Int, hotkey: HotkeySpec) {
        self.unread = unread
        self.hotkey = hotkey
        selection.setEntries(entries)
        render()
    }

    func setTheme(_ theme: OverlayTheme) {
        self.theme = theme
        applyPalette()
    }

    /// Keyboard mode starts from an empty query with the first row highlighted.
    func setKeyboardMode(_ enabled: Bool) {
        isKeyboardMode = enabled
        queryField.isEditable = enabled
        queryField.isSelectable = enabled
        queryField.stringValue = ""
        selection.setQuery("")
        render()
    }

    /// Hands typing to the query field once the panel is key.
    func focusQuery() {
        window?.makeFirstResponder(queryField)
    }

    // MARK: - Rendering

    private func render() {
        for view in list.arrangedSubviews { view.removeFromSuperview() }
        rowViews = []

        if selection.rows.isEmpty {
            let text = selection.query.isEmpty ? "No finished agent runs yet" : "No matching tasks"
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: 13)
            label.textColor = NSColor(palette.subtitle)
            label.translatesAutoresizingMaskIntoConstraints = false
            let empty = NSView()
            empty.addSubview(label)
            list.addArrangedSubview(empty)
            NSLayoutConstraint.activate([
                empty.widthAnchor.constraint(equalTo: list.widthAnchor),
                empty.heightAnchor.constraint(equalToConstant: Self.rowHeight),
                label.centerXAnchor.constraint(equalTo: empty.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: empty.centerYAnchor),
            ])
        } else {
            for (index, entry) in selection.rows.enumerated() {
                let row = OverlayTaskRowView(entry: entry, palette: palette)
                row.onClick = { [weak self] picked in self?.onSelect?(picked) }
                row.onHover = { [weak self] in self?.highlight(index) }
                list.addArrangedSubview(row)
                NSLayoutConstraint.activate([
                    row.widthAnchor.constraint(equalTo: list.widthAnchor),
                    row.heightAnchor.constraint(equalToConstant: Self.rowHeight),
                ])
                rowViews.append(row)
            }
        }

        refreshHighlight()
        refreshPlaceholder()
        hint.stringValue = hintText()
        onHeightChange?(preferredHeight)
    }

    private func highlight(_ index: Int) {
        selection.select(index: index)
        refreshHighlight()
    }

    private func refreshHighlight() {
        for (index, row) in rowViews.enumerated() {
            row.setSelected(
                index == selection.selectedIndex,
                shortcut: OverlaySelection.shortcutLabel(
                    row: index, selectedRow: selection.selectedIndex)
            )
        }
    }

    private func refreshPlaceholder() {
        let text: String
        if isKeyboardMode {
            text = "Search \(selection.rows.count) task\(selection.rows.count == 1 ? "" : "s")…"
        } else {
            text = unread > 0 ? "island — \(unread) unread" : "island"
        }
        queryField.placeholderAttributedString = NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: NSColor(isKeyboardMode ? palette.subtitle : palette.queryText),
                .font: queryField.font ?? NSFont.systemFont(ofSize: 24),
            ]
        )
    }

    private func hintText() -> String {
        let hide = hotkey.map { " · \($0.displayString) to hide" } ?? ""
        if isKeyboardMode {
            return "↑↓ select · ↩ open · ⌘1–9 jump · esc close\(hide)"
        }
        return "click a task to jump back\(hide)"
    }

    private func applyPalette() {
        palette = theme.palette(systemIsDark: effectiveAppearance.isDark)
        blurView.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
        blurView.material = palette.isDark ? .hudWindow : .popover
        blurView.layer?.cornerRadius = palette.cornerRadius
        blurView.layer?.borderWidth = palette.borderWidth
        blurView.layer?.borderColor = NSColor(palette.borderColor).cgColor
        tintView.layer?.backgroundColor = NSColor(palette.background).cgColor
        queryBox.layer?.backgroundColor = NSColor(palette.queryBackground).cgColor
        queryField.textColor = NSColor(palette.queryText)
        hint.textColor = NSColor(palette.hint)
        render()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if theme == .system { applyPalette() }
    }

    // MARK: - Layout

    private func build() {
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.wantsLayer = true
        blurView.layer?.masksToBounds = true
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)

        tintView.wantsLayer = true
        tintView.translatesAutoresizingMaskIntoConstraints = false
        blurView.addSubview(tintView)

        queryBox.wantsLayer = true
        queryBox.layer?.cornerRadius = 6
        queryBox.translatesAutoresizingMaskIntoConstraints = false

        queryField.font = .systemFont(ofSize: 24, weight: .regular)
        queryField.isBordered = false
        queryField.drawsBackground = false
        queryField.focusRingType = .none
        queryField.isEditable = false
        queryField.isSelectable = false
        queryField.lineBreakMode = .byTruncatingTail
        queryField.cell?.usesSingleLineMode = true
        queryField.delegate = self
        queryField.translatesAutoresizingMaskIntoConstraints = false
        queryBox.addSubview(queryField)

        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0
        list.translatesAutoresizingMaskIntoConstraints = false

        hint.font = .systemFont(ofSize: 11)
        hint.lineBreakMode = .byTruncatingTail
        hint.translatesAutoresizingMaskIntoConstraints = false

        for view in [queryBox, list, hint] { blurView.addSubview(view) }

        let pad = Self.padding
        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            tintView.leadingAnchor.constraint(equalTo: blurView.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: blurView.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: blurView.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: blurView.bottomAnchor),

            queryBox.leadingAnchor.constraint(equalTo: blurView.leadingAnchor, constant: pad),
            queryBox.trailingAnchor.constraint(equalTo: blurView.trailingAnchor, constant: -pad),
            queryBox.topAnchor.constraint(equalTo: blurView.topAnchor, constant: pad),
            queryBox.heightAnchor.constraint(equalToConstant: Self.queryHeight),
            queryField.leadingAnchor.constraint(equalTo: queryBox.leadingAnchor, constant: 12),
            queryField.trailingAnchor.constraint(equalTo: queryBox.trailingAnchor, constant: -12),
            queryField.centerYAnchor.constraint(equalTo: queryBox.centerYAnchor),

            list.leadingAnchor.constraint(equalTo: queryBox.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: queryBox.trailingAnchor),
            list.topAnchor.constraint(equalTo: queryBox.bottomAnchor, constant: 6),

            hint.leadingAnchor.constraint(equalTo: queryBox.leadingAnchor, constant: 4),
            hint.trailingAnchor.constraint(equalTo: queryBox.trailingAnchor, constant: -4),
            hint.bottomAnchor.constraint(equalTo: blurView.bottomAnchor, constant: -pad + 2),
        ])
    }

    // MARK: - Keyboard

    func controlTextDidChange(_ notification: Notification) {
        selection.setQuery(queryField.stringValue)
        render()
    }

    func control(
        _ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector
    ) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            selection.move(by: -1)
            refreshHighlight()
        case #selector(NSResponder.moveDown(_:)):
            selection.move(by: 1)
            refreshHighlight()
        case #selector(NSResponder.insertNewline(_:)):
            if let entry = selection.selected { onSelect?(entry) }
        case #selector(NSResponder.cancelOperation(_:)):
            onDismiss?()
        default:
            return false
        }
        return true
    }

    /// ⌘1…⌘9 open the N-th visible row, like Alfred.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard isKeyboardMode, modifiers == .command,
            let digit = event.charactersIgnoringModifiers.flatMap(Int.init),
            let entry = selection.entry(forShortcut: digit)
        else { return super.performKeyEquivalent(with: event) }
        onSelect?(entry)
        return true
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

/// One task row: agent icon (with an unread dot), title, an
/// `agent · time · directory` subtitle, and the shortcut hint on the right.
@MainActor
final class OverlayTaskRowView: NSView {
    let entry: AgentInbox.Entry
    var onClick: ((AgentInbox.Entry) -> Void)?
    var onHover: (() -> Void)?

    private let palette: OverlayPalette
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let shortcut = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?

    init(entry: AgentInbox.Entry, palette: OverlayPalette) {
        self.entry = entry
        self.palette = palette
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("OverlayTaskRowView is created in code only")
    }

    func setSelected(_ selected: Bool, shortcut label: String?) {
        layer?.backgroundColor =
            selected ? NSColor(palette.selectionBackground).cgColor : NSColor.clear.cgColor
        title.textColor = NSColor(selected ? palette.selectionTitle : palette.title)
        subtitle.textColor = NSColor(selected ? palette.selectionSubtitle : palette.subtitle)
        shortcut.textColor = NSColor(selected ? palette.selectionTitle : palette.shortcut)
        shortcut.stringValue = label ?? ""
    }

    private func build() {
        let icon = AgentIconView(agent: entry.task.agent, unread: !entry.isRead)
        icon.translatesAutoresizingMaskIntoConstraints = false

        title.stringValue = entry.task.title
        title.font = .systemFont(ofSize: 15, weight: entry.isRead ? .regular : .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        subtitle.stringValue = Self.subtitle(for: entry.task)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.lineBreakMode = .byTruncatingMiddle
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        shortcut.font = .systemFont(ofSize: 15, weight: .medium)
        shortcut.alignment = .right
        shortcut.setContentHuggingPriority(.required, for: .horizontal)
        shortcut.setContentCompressionResistancePriority(.required, for: .horizontal)

        let text = NSStackView(views: [title, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        // The text column takes the slack so the shortcut hugs the right edge.
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [icon, text, shortcut])
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 34),
            icon.heightAnchor.constraint(equalToConstant: 34),
            shortcut.widthAnchor.constraint(greaterThanOrEqualToConstant: 34),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
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
        onHover?()
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?(entry)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// The agent's app icon (or an SF Symbol when the app is not installed), with
/// a red dot in the top-right corner while the run is unread.
@MainActor
final class AgentIconView: NSView {
    private static var cache: [AgentKind: NSImage] = [:]

    init(agent: AgentKind, unread: Bool) {
        super.init(frame: .zero)
        let image = NSImageView(image: Self.image(for: agent))
        image.imageScaling = .scaleProportionallyUpOrDown
        image.translatesAutoresizingMaskIntoConstraints = false
        addSubview(image)

        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 5
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.borderColor = NSColor.white.cgColor
        dot.layer?.borderWidth = 1.5
        dot.isHidden = !unread
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)

        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: leadingAnchor),
            image.trailingAnchor.constraint(equalTo: trailingAnchor),
            image.topAnchor.constraint(equalTo: topAnchor),
            image.bottomAnchor.constraint(equalTo: bottomAnchor),
            dot.widthAnchor.constraint(equalToConstant: 10),
            dot.heightAnchor.constraint(equalToConstant: 10),
            dot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 1),
            dot.topAnchor.constraint(equalTo: topAnchor, constant: -1),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("AgentIconView is created in code only")
    }

    private static func image(for agent: AgentKind) -> NSImage {
        if let cached = cache[agent] { return cached }
        let workspace = NSWorkspace.shared
        let appIcon = AgentIcon.bundleIDs(for: agent).lazy
            .compactMap { workspace.urlForApplication(withBundleIdentifier: $0) }
            .map { workspace.icon(forFile: $0.path) }
            .first
        let image =
            appIcon
            ?? NSImage(
                systemSymbolName: AgentIcon.symbolName(for: agent), accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 22, weight: .regular))
            ?? NSImage()
        cache[agent] = image
        return image
    }
}

extension NSColor {
    convenience init(_ color: ThemeColor) {
        self.init(
            srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
