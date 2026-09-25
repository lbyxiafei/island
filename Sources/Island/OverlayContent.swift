import AppKit
import IslandCore

/// The overlay body: an island capsule hanging from the top of the screen.
/// A header, then one row per finished agent run with a number keycap, the
/// agent's icon, title, `directory • agent`, and its age.
///
/// Two modes (see `setKeyboardMode`): when summoned by the user the panel is
/// key, the whole header is a search field (with an `N new` pill on the
/// right), and it takes typing, arrows, Enter, ⌘1–9, ⌘, and Esc; when it pops
/// up by itself the header reads `● N new` next to the hotkey, it never takes
/// focus, and rows are clicked with the mouse.
@MainActor
final class OverlayContentView: NSView, NSTextFieldDelegate {
    static let width: CGFloat = 520
    static let rowHeight: CGFloat = 52
    private static let headerHeight: CGFloat = 40
    private static let footerHeight: CGFloat = 28
    private static let padding: CGFloat = 10
    /// Bottom inset under the footer; the footer's own height already gives
    /// its text room, so it sits closer to the edge than the rows would.
    private static let footerInset: CGFloat = 4

    var onSelect: ((AgentInbox.Entry) -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    var onDismiss: (() -> Void)?
    /// ⌘, in keyboard mode.
    var onOpenSettings: (() -> Void)?
    /// The row count changed (typing filters the list), so the panel resizes.
    var onHeightChange: ((CGFloat) -> Void)?

    private(set) var theme = OverlayTheme.fallback
    private var palette = OverlayTheme.fallback.palette(systemIsDark: false)
    private var selection = OverlaySelection(entries: [])
    private var unread = 0
    private var hotkey: HotkeySpec?
    private var isKeyboardMode = false
    private(set) var showsHints = true

    private var showsFooter: Bool { isKeyboardMode && showsHints }

    private let blurView = NSVisualEffectView()
    private let shape = CapsuleShapeView()
    private let dot = NSView()
    private let status = NSTextField(labelWithString: "")
    private let spacer = NSView()
    private let searchIcon = NSImageView()
    private let searchField = NSTextField()
    private let newPill = KeycapView()
    private let hotkeyCap = KeycapView()
    private let list = NSStackView()
    private let footerBox = NSView()
    private let footer = NSTextField(labelWithString: "")
    private var footerHeightConstraint: NSLayoutConstraint?
    private var bottomInsetConstraint: NSLayoutConstraint?
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
        let bottom = showsFooter ? Self.footerHeight + Self.footerInset : Self.padding
        return Self.padding + Self.headerHeight + CGFloat(rows) * Self.rowHeight + bottom
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

    func setShowsHints(_ shows: Bool) {
        showsHints = shows
        render()
    }

    /// Keyboard mode starts from an empty query with the first row highlighted.
    func setKeyboardMode(_ enabled: Bool) {
        isKeyboardMode = enabled
        searchField.stringValue = ""
        selection.setQuery("")
        render()
    }

    /// Hands typing to the search field once the panel is key.
    func focusQuery() {
        window?.makeFirstResponder(searchField)
    }

    // MARK: - Rendering

    private func render() {
        for view in list.arrangedSubviews { view.removeFromSuperview() }
        rowViews = []

        if selection.rows.isEmpty {
            addEmptyRow()
        } else {
            for (index, entry) in selection.rows.enumerated() {
                let row = OverlayTaskRowView(
                    entry: entry, keycap: OverlaySelection.keycapLabel(row: index),
                    palette: palette)
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
        refreshHeader()
        onHeightChange?(preferredHeight)
    }

    private func addEmptyRow() {
        let text = selection.query.isEmpty ? "Nothing has finished yet" : "No matches"
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.textColor = NSColor(palette.muted)
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
    }

    private func highlight(_ index: Int) {
        selection.select(index: index)
        refreshHighlight()
    }

    private func refreshHighlight() {
        for (index, row) in rowViews.enumerated() {
            row.setSelected(index == selection.selectedIndex)
        }
    }

    private func refreshHeader() {
        let text = OverlayStatus.text(unread: unread)
        status.stringValue = text
        status.textColor = NSColor(unread > 0 ? palette.title : palette.subtitle)
        dot.layer?.backgroundColor = NSColor(unread > 0 ? palette.accent : palette.muted).cgColor

        // Passive: `● N new` … hotkey. Keyboard: 🔍 search … `N new`.
        dot.isHidden = isKeyboardMode
        status.isHidden = isKeyboardMode
        spacer.isHidden = isKeyboardMode
        hotkeyCap.isHidden = isKeyboardMode || hotkey == nil
        searchIcon.isHidden = !isKeyboardMode
        searchField.isHidden = !isKeyboardMode
        searchField.isEditable = isKeyboardMode
        newPill.isHidden = !isKeyboardMode || unread == 0

        hotkeyCap.set(text: hotkey?.displayString ?? "", palette: palette, fontSize: 11)
        newPill.set(
            text: text, textColor: NSColor(palette.accent),
            background: NSColor(palette.selectionBackground), fontSize: 11)
        let count = selection.rows.count
        searchField.placeholderAttributedString = NSAttributedString(
            string: count == 0
                ? "Search tasks" : count == 1 ? "Search 1 task" : "Search \(count) tasks",
            attributes: [
                .foregroundColor: NSColor(palette.muted),
                .font: NSFont.systemFont(ofSize: 15),
            ])

        footerBox.isHidden = !showsFooter
        footerHeightConstraint?.constant = showsFooter ? Self.footerHeight : 0
        bottomInsetConstraint?.constant = -(showsFooter ? Self.footerInset : Self.padding)
        footer.stringValue = "↑↓ move   ↩ open   ⌘1–9 jump   ⌘, settings   esc close"
    }

    private func applyPalette() {
        palette = theme.palette(systemIsDark: effectiveAppearance.isDark)
        blurView.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
        blurView.material = palette.isDark ? .hudWindow : .popover
        shape.fill = NSColor(palette.background)
        shape.stroke = NSColor(palette.border)
        searchField.textColor = NSColor(palette.title)
        searchIcon.contentTintColor = NSColor(palette.subtitle)
        footer.textColor = NSColor(palette.muted)
        render()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if theme == .system { applyPalette() }
    }

    override func layout() {
        super.layout()
        blurView.maskImage = CapsuleShapeView.maskImage(size: bounds.size)
    }

    // MARK: - Layout

    private func build() {
        blurView.blendingMode = .behindWindow
        blurView.state = .active
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)
        shape.translatesAutoresizingMaskIntoConstraints = false
        blurView.addSubview(shape)

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false

        searchIcon.image = NSImage(
            systemSymbolName: "magnifyingglass", accessibilityDescription: "filter")
        searchIcon.symbolConfiguration = .init(pointSize: 14, weight: .medium)
        searchField.font = .systemFont(ofSize: 15)
        searchField.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.cell?.usesSingleLineMode = true
        searchField.lineBreakMode = .byTruncatingTail
        searchField.delegate = self

        status.font = .systemFont(ofSize: 13, weight: .semibold)
        spacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        let header = NSStackView(views: [
            dot, status, searchIcon, searchField, spacer, newPill, hotkeyCap,
        ])
        header.orientation = .horizontal
        header.distribution = .fill
        header.alignment = .centerY
        header.spacing = 8
        header.setCustomSpacing(6, after: searchIcon)
        header.translatesAutoresizingMaskIntoConstraints = false
        status.setContentHuggingPriority(.required, for: .horizontal)
        status.setContentCompressionResistancePriority(.required, for: .horizontal)

        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0
        list.translatesAutoresizingMaskIntoConstraints = false

        footer.font = .systemFont(ofSize: 10.5)
        footer.alignment = .center
        footer.translatesAutoresizingMaskIntoConstraints = false
        footerBox.translatesAutoresizingMaskIntoConstraints = false
        footerBox.addSubview(footer)

        for view in [header, list, footerBox] { blurView.addSubview(view) }

        let footerHeight = footerBox.heightAnchor.constraint(equalToConstant: 0)
        footerHeightConstraint = footerHeight
        let bottomInset = footerBox.bottomAnchor.constraint(
            equalTo: blurView.bottomAnchor, constant: -Self.padding)
        bottomInsetConstraint = bottomInset
        let pad = Self.padding
        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            shape.leadingAnchor.constraint(equalTo: blurView.leadingAnchor),
            shape.trailingAnchor.constraint(equalTo: blurView.trailingAnchor),
            shape.topAnchor.constraint(equalTo: blurView.topAnchor),
            shape.bottomAnchor.constraint(equalTo: blurView.bottomAnchor),

            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            header.leadingAnchor.constraint(equalTo: blurView.leadingAnchor, constant: pad + 12),
            header.trailingAnchor.constraint(
                equalTo: blurView.trailingAnchor, constant: -pad - 12),
            header.topAnchor.constraint(equalTo: blurView.topAnchor, constant: pad),
            header.heightAnchor.constraint(equalToConstant: Self.headerHeight),

            list.leadingAnchor.constraint(equalTo: blurView.leadingAnchor, constant: pad),
            list.trailingAnchor.constraint(equalTo: blurView.trailingAnchor, constant: -pad),
            list.topAnchor.constraint(equalTo: header.bottomAnchor),

            footerBox.leadingAnchor.constraint(equalTo: list.leadingAnchor),
            footerBox.trailingAnchor.constraint(equalTo: list.trailingAnchor),
            footerHeight,
            bottomInset,
            footer.leadingAnchor.constraint(equalTo: footerBox.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: footerBox.trailingAnchor),
            footer.centerYAnchor.constraint(equalTo: footerBox.centerYAnchor),
        ])
    }

    // MARK: - Keyboard

    func controlTextDidChange(_ notification: Notification) {
        selection.setQuery(searchField.stringValue)
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

    /// ⌘1…⌘9 open the row with that keycap; ⌘, opens settings.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if isKeyboardMode, modifiers == .command, event.charactersIgnoringModifiers == "," {
            onOpenSettings?()
            return true
        }
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

/// The capsule outline: flat where it meets the top of the screen, generously
/// rounded at the bottom, like an island hanging from the menu bar.
@MainActor
final class CapsuleShapeView: NSView {
    static let bottomRadius: CGFloat = 26

    var fill = NSColor.clear { didSet { needsDisplay = true } }
    var stroke = NSColor.clear { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        fill.setFill()
        Self.path(in: bounds, closed: true).fill()
        stroke.setStroke()
        let outline = Self.path(in: bounds.insetBy(dx: 0.5, dy: 0.5), closed: false)
        outline.lineWidth = 1
        outline.stroke()
    }

    /// Open paths leave out the top edge, which touches the menu bar.
    static func path(in rect: NSRect, closed: Bool) -> NSBezierPath {
        let radius = min(bottomRadius, rect.height / 2, rect.width / 2)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY + radius))
        path.appendArc(
            withCenter: NSPoint(x: rect.minX + radius, y: rect.minY + radius), radius: radius,
            startAngle: 180, endAngle: 270)
        path.line(to: NSPoint(x: rect.maxX - radius, y: rect.minY))
        path.appendArc(
            withCenter: NSPoint(x: rect.maxX - radius, y: rect.minY + radius), radius: radius,
            startAngle: 270, endAngle: 360)
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        if closed { path.close() }
        return path
    }

    /// Clips the blur to the same shape (a layer mask does not clip
    /// behind-window vibrancy).
    static func maskImage(size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            path(in: rect, closed: true).fill()
            return true
        }
    }
}

/// A small rounded keycap: the `1`…`9` on rows, the hotkey and the `N new`
/// pill in the header.
@MainActor
final class KeycapView: NSView {
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 5
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        // Keycaps stay as small as their text; never take a stack's slack.
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("KeycapView is created in code only")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(20, label.intrinsicContentSize.width + 12), height: 20)
    }

    func set(text: String, palette: OverlayPalette, fontSize: CGFloat) {
        set(
            text: text, textColor: NSColor(palette.keycapText),
            background: NSColor(palette.keycapBackground), fontSize: fontSize)
    }

    func set(text: String, textColor: NSColor, background: NSColor, fontSize: CGFloat) {
        defer { invalidateIntrinsicContentSize() }
        label.stringValue = text
        label.font = .monospacedDigitSystemFont(ofSize: fontSize, weight: .medium)
        label.textColor = textColor
        layer?.backgroundColor = background.cgColor
    }
}

/// One task row: number keycap, agent icon (with an unread dot), title,
/// `directory • agent`, and a short age on the right.
@MainActor
final class OverlayTaskRowView: NSView {
    let entry: AgentInbox.Entry
    var onClick: ((AgentInbox.Entry) -> Void)?
    var onHover: (() -> Void)?

    private let palette: OverlayPalette
    private var trackingArea: NSTrackingArea?

    init(entry: AgentInbox.Entry, keycap: String?, palette: OverlayPalette) {
        self.entry = entry
        self.palette = palette
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 14
        build(keycap: keycap)
    }

    required init?(coder: NSCoder) {
        fatalError("OverlayTaskRowView is created in code only")
    }

    func setSelected(_ selected: Bool) {
        layer?.backgroundColor =
            selected ? NSColor(palette.selectionBackground).cgColor : NSColor.clear.cgColor
        layer?.borderColor = NSColor(palette.selectionBorder).cgColor
        layer?.borderWidth = selected ? 1 : 0
    }

    private func build(keycap label: String?) {
        let keycap = KeycapView()
        keycap.set(text: label ?? "", palette: palette, fontSize: 11)
        keycap.alphaValue = label == nil ? 0 : 1

        let icon = AgentIconView(agent: entry.task.agent, unread: !entry.isRead)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: entry.task.title)
        title.font = .systemFont(ofSize: 14, weight: entry.isRead ? .regular : .semibold)
        title.textColor = NSColor(palette.title)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let subtitle = NSTextField(labelWithString: Self.subtitle(for: entry.task))
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = NSColor(palette.subtitle)
        subtitle.lineBreakMode = .byTruncatingMiddle
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let age = NSTextField(labelWithString: ShortAge.text(since: entry.task.completedAt))
        age.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        age.textColor = NSColor(palette.muted)
        age.alignment = .right
        age.setContentHuggingPriority(.required, for: .horizontal)
        age.setContentCompressionResistancePriority(.required, for: .horizontal)

        let text = NSStackView(views: [title, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        // The text column takes the slack so the age hugs the right edge.
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [keycap, icon, text, age])
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = 10
        row.setCustomSpacing(12, after: keycap)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            title.widthAnchor.constraint(equalTo: text.widthAnchor),
            subtitle.widthAnchor.constraint(equalTo: text.widthAnchor),
            icon.widthAnchor.constraint(equalToConstant: 26),
            icon.heightAnchor.constraint(equalToConstant: 26),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    /// `island • Claude Code`: where it ran first, then which agent.
    private static func subtitle(for task: AgentTask) -> String {
        var pieces: [String] = []
        if let cwd = task.cwd, !cwd.isEmpty {
            pieces.append((cwd as NSString).lastPathComponent)
        }
        pieces.append(task.agent.displayName)
        return pieces.joined(separator: " • ")
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
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.isHidden = !unread
        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)

        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: leadingAnchor),
            image.trailingAnchor.constraint(equalTo: trailingAnchor),
            image.topAnchor.constraint(equalTo: topAnchor),
            image.bottomAnchor.constraint(equalTo: bottomAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            dot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 2),
            dot.topAnchor.constraint(equalTo: topAnchor, constant: -2),
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
            .withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
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
