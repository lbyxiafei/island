import AppKit
import IslandCore

/// Pet mode's two windows: the pet itself (always on top, draggable, fades to
/// the idle opacity) and, beside it, a stack of speech bubbles — one per
/// unread run — that stay until clicked or dismissed. Layout decisions live in
/// `PetLayout`; this file only draws and forwards clicks.
@MainActor
final class PetController {
    static let size = CGSize(width: 64, height: 64)

    var onSelect: ((AgentInbox.Entry) -> Void)?
    var onDismiss: ((AgentInbox.Entry) -> Void)?
    var onDismissAll: (() -> Void)?
    var onOpenList: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onHide: (() -> Void)?

    private let store: UserDefaultsPetStore
    private var settings: PetSettings
    private let petPanel = PetPanel(size: PetController.size)
    private let petView = PetView(frame: NSRect(origin: .zero, size: PetController.size))
    private let bubblePanel = PetPanel(size: CGSize(width: PetBubbleStack.width, height: 40))
    private let bubbleStack = PetBubbleStack()
    private var unread: [AgentInbox.Entry] = []
    private var hovering = false

    init(settings: PetSettings, store: UserDefaultsPetStore) {
        self.settings = settings
        self.store = store
        petPanel.contentView = petView
        bubblePanel.contentView = bubbleStack
        petView.onClick = { [weak self] in self?.onOpenList?() }
        petView.onHover = { [weak self] hovering in
            self?.hovering = hovering
            self?.refreshOpacity()
        }
        petView.onDrag = { [weak self] in self?.placeBubbles() }
        petView.onDragEnd = { [weak self] origin in self?.store.saveOrigin(origin) }
        petView.menuProvider = { [weak self] in self?.contextMenu() ?? NSMenu() }
        bubbleStack.onSelect = { [weak self] entry in self?.onSelect?(entry) }
        bubbleStack.onDismiss = { [weak self] entry in self?.onDismiss?(entry) }
        bubbleStack.onMore = { [weak self] in self?.onOpenList?() }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.placePet() }
        }
        apply(settings)
    }

    func apply(_ settings: PetSettings) {
        self.settings = settings
        guard settings.isEnabled else {
            petPanel.orderOut(nil)
            bubblePanel.orderOut(nil)
            return
        }
        petView.setAvatar(settings.avatar)
        petView.setAnimates(settings.animates)
        if !petPanel.isVisible {
            placePet()
            petPanel.orderFrontRegardless()
        }
        refreshBubbles()
    }

    /// The unread runs changed; `alerted` means one arrived the user did not
    /// watch finish, worth a hop.
    func update(unread: [AgentInbox.Entry], alerted: Bool) {
        self.unread = unread
        guard settings.isEnabled else { return }
        refreshBubbles()
        if alerted { petView.hop() }
    }

    // MARK: - Placement

    private func placePet() {
        let screens = NSScreen.screens.map(\.visibleFrame)
        let origin = PetLayout.origin(
            remembered: store.loadOrigin(), size: Self.size, screens: screens)
        petPanel.setFrameOrigin(origin)
        placeBubbles()
    }

    private func refreshBubbles() {
        let bubbles = PetLayout.bubbles(for: unread)
        petView.setBadge(unread.count)
        refreshOpacity()
        guard !bubbles.shown.isEmpty else {
            bubblePanel.orderOut(nil)
            return
        }
        bubbleStack.show(bubbles, growth: growth)
        placeBubbles()
        bubblePanel.orderFrontRegardless()
    }

    private var screenFrame: CGRect {
        (petPanel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
    }

    private var growth: PetLayout.Growth {
        PetLayout.growth(of: petPanel.frame, in: screenFrame)
    }

    private func placeBubbles() {
        guard !bubbleStack.isEmpty else { return }
        // Dragging across the middle flips the stack's direction.
        bubbleStack.setGrowth(growth)
        let frame = PetLayout.bubbleFrame(
            size: bubbleStack.fittingSize, pet: petPanel.frame, screen: screenFrame)
        bubblePanel.setFrame(frame, display: true)
    }

    private func refreshOpacity() {
        let target = settings.opacity(hasUnread: !unread.isEmpty, hovering: hovering)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            petPanel.animator().alphaValue = target
        }
    }

    // MARK: - Menu

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        let list = menu.addItem(
            withTitle: "Show task list", action: #selector(MenuTarget.fire(_:)), keyEquivalent: "")
        bind(list) { [weak self] in self?.onOpenList?() }
        if !unread.isEmpty {
            let clear = menu.addItem(
                withTitle: "Dismiss all bubbles", action: #selector(MenuTarget.fire(_:)),
                keyEquivalent: "")
            bind(clear) { [weak self] in self?.onDismissAll?() }
        }
        menu.addItem(.separator())
        let settingsItem = menu.addItem(
            withTitle: "Pet settings…", action: #selector(MenuTarget.fire(_:)), keyEquivalent: "")
        bind(settingsItem) { [weak self] in self?.onOpenSettings?() }
        let hide = menu.addItem(
            withTitle: "Turn off pet mode", action: #selector(MenuTarget.fire(_:)),
            keyEquivalent: "")
        bind(hide) { [weak self] in self?.onHide?() }
        return menu
    }

    private func bind(_ item: NSMenuItem, _ action: @escaping () -> Void) {
        let target = MenuTarget(action)
        item.target = target
        item.representedObject = target  // keeps the target alive with the item
    }
}

/// Lets a menu item run a closure.
private final class MenuTarget: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire(_ sender: Any?) { action() }
}

/// Borderless, never key, on every Space, above normal windows.
final class PetPanel: NSPanel {
    init(size: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - The pet

/// The avatar plus an unread badge. A press that moves drags the window; one
/// that does not is a click. Right click opens the pet's menu.
final class PetView: NSView {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var onDrag: (() -> Void)?
    var onDragEnd: ((CGPoint) -> Void)?
    var menuProvider: (() -> NSMenu)?

    private let body = NSView()
    private let emoji = NSTextField(labelWithString: "")
    private let image = NSImageView()
    private let badge = NSTextField(labelWithString: "")
    private var pressStart: CGPoint?
    private var windowStart: CGPoint = .zero
    private var dragging = false
    private var animates = true

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        body.wantsLayer = true
        body.frame = bounds.insetBy(dx: 4, dy: 4)
        // Nearly invisible, but it makes the whole circle clickable; fully
        // transparent pixels would let clicks fall through to the app below.
        body.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.02).cgColor
        body.layer?.cornerRadius = body.frame.width / 2
        addSubview(body)

        emoji.font = .systemFont(ofSize: 40)
        emoji.alignment = .center
        emoji.frame = body.bounds.offsetBy(dx: 0, dy: -4)
        body.addSubview(emoji)
        image.imageScaling = .scaleProportionallyUpOrDown
        image.frame = body.bounds.insetBy(dx: 4, dy: 4)
        image.wantsLayer = true
        image.layer?.cornerRadius = 8
        image.layer?.masksToBounds = true
        body.addSubview(image)

        badge.font = .monospacedDigitSystemFont(ofSize: 10, weight: .bold)
        badge.textColor = .white
        badge.alignment = .center
        badge.wantsLayer = true
        badge.drawsBackground = false
        badge.layer?.backgroundColor = NSColor.systemRed.cgColor
        badge.layer?.cornerRadius = 8
        badge.frame = NSRect(x: bounds.maxX - 20, y: bounds.maxY - 18, width: 18, height: 16)
        addSubview(badge)

        addTrackingArea(
            NSTrackingArea(
                rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self))
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setAvatar(_ avatar: PetAvatar) {
        switch avatar {
        case .builtIn(let character):
            emoji.stringValue = character.emoji
            emoji.isHidden = false
            image.isHidden = true
        case .image(let path):
            if let picture = NSImage(contentsOfFile: path) {
                image.image = picture
                image.isHidden = false
                emoji.isHidden = true
            } else {
                // The file moved away: fall back to the default look.
                setAvatar(PetSettings().avatar)
            }
        }
    }

    func setBadge(_ count: Int) {
        badge.isHidden = count == 0
        badge.stringValue = count > 9 ? "9+" : "\(count)"
    }

    func setAnimates(_ animates: Bool) {
        self.animates = animates
        guard let layer = body.layer else { return }
        layer.removeAnimation(forKey: "bob")
        guard animates else { return }
        let bob = CABasicAnimation(keyPath: "transform.translation.y")
        bob.fromValue = -1.5
        bob.toValue = 1.5
        bob.duration = 1.4
        bob.autoreverses = true
        bob.repeatCount = .infinity
        bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(bob, forKey: "bob")
    }

    /// A little jump when a run arrives.
    func hop() {
        guard animates, let layer = body.layer else { return }
        let hop = CAKeyframeAnimation(keyPath: "transform.translation.y")
        hop.values = [0, 12, 0, 5, 0]
        hop.keyTimes = [0, 0.3, 0.55, 0.75, 1]
        hop.duration = 0.6
        layer.add(hop, forKey: "hop")
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) {
        pressStart = NSEvent.mouseLocation
        windowStart = window?.frame.origin ?? .zero
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressStart, let window else { return }
        let now = NSEvent.mouseLocation
        if !dragging, !PetLayout.isDrag(from: start, to: now) { return }
        dragging = true
        window.setFrameOrigin(
            CGPoint(x: windowStart.x + now.x - start.x, y: windowStart.y + now.y - start.y))
        onDrag?()
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressStart = nil }
        if dragging, let window {
            onDragEnd?(window.frame.origin)
        } else if event.clickCount <= 1 {
            onClick?()
        }
        dragging = false
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

// MARK: - Bubbles

/// The speech bubbles, newest next to the pet, plus a "+N more" chip at the
/// far end when there are more unread runs than bubbles.
final class PetBubbleStack: NSView {
    static let width: CGFloat = 280

    var onSelect: ((AgentInbox.Entry) -> Void)?
    var onDismiss: ((AgentInbox.Entry) -> Void)?
    var onMore: (() -> Void)?

    private let stack = NSStackView()
    private var bubbles = PetLayout.Bubbles(shown: [], overflow: 0)
    private var growth = PetLayout.Growth.up

    var isEmpty: Bool { bubbles.shown.isEmpty }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 40))
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: Self.width),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func show(_ bubbles: PetLayout.Bubbles, growth: PetLayout.Growth) {
        self.bubbles = bubbles
        self.growth = growth
        rebuild()
    }

    func setGrowth(_ growth: PetLayout.Growth) {
        guard growth != self.growth else { return }
        self.growth = growth
        rebuild()
    }

    private func rebuild() {
        for view in stack.arrangedSubviews { view.removeFromSuperview() }
        var views: [NSView] = bubbles.shown.map { entry in
            let bubble = PetBubbleView(entry: entry)
            bubble.onSelect = { [weak self] in self?.onSelect?(entry) }
            bubble.onDismiss = { [weak self] in self?.onDismiss?(entry) }
            return bubble
        }
        if bubbles.overflow > 0 {
            let more = NSButton(
                title: "+\(bubbles.overflow) more", target: self, action: #selector(moreTapped))
            more.bezelStyle = .recessed
            more.controlSize = .small
            views.append(more)
        }
        // `views` is newest first with the chip last; the chip stays farthest
        // from the pet either way.
        for view in PetLayout.topToBottom(views, growth: growth) {
            stack.addArrangedSubview(view)
            if view is PetBubbleView {
                view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
        }
        layoutSubtreeIfNeeded()
        setFrameSize(fittingSize)
    }

    @objc private func moreTapped() { onMore?() }
}

/// One run: agent icon, title, agent and age; click opens it, × dismisses it.
final class PetBubbleView: NSView {
    var onSelect: (() -> Void)?
    var onDismiss: (() -> Void)?

    private let close = NSButton()

    init(entry: AgentInbox.Entry) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        background.translatesAutoresizingMaskIntoConstraints = false
        addSubview(background)

        let icon = AgentIconView(agent: entry.task.agent, unread: false)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: entry.task.title)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let subtitle = NSTextField(
            labelWithString:
                "\(entry.task.agent.displayName) · \(ShortAge.text(since: entry.task.completedAt))")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor

        let text = NSStackView(views: [title, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        text.translatesAutoresizingMaskIntoConstraints = false

        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss")
        close.isBordered = false
        close.imagePosition = .imageOnly
        close.contentTintColor = .secondaryLabelColor
        close.target = self
        close.action = #selector(closeTapped)
        close.toolTip = "Dismiss (marks it read)"
        close.translatesAutoresizingMaskIntoConstraints = false

        for view in [icon, text, close] { addSubview(view) }
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: leadingAnchor),
            background.trailingAnchor.constraint(equalTo: trailingAnchor),
            background.topAnchor.constraint(equalTo: topAnchor),
            background.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            text.trailingAnchor.constraint(lessThanOrEqualTo: close.leadingAnchor, constant: -6),
            text.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            text.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            close.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            close.centerYAnchor.constraint(equalTo: centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 16),
            close.heightAnchor.constraint(equalToConstant: 16),
        ])
        toolTip = [entry.task.title, entry.task.cwd].compactMap { $0 }.joined(separator: "\n")
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) { onSelect?() }
    }

    // The visual effect view would otherwise swallow the click.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        if close.frame.contains(local) { return close }
        return bounds.contains(local) ? self : nil
    }

    @objc private func closeTapped() { onDismiss?() }
}
