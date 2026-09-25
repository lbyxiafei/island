import AppKit

/// The floating window itself: borderless, never main, visible on every Space,
/// and floating above normal windows and the Dock.
///
/// It only becomes key while `acceptsKeyboard` is on — when the user summons it
/// and wants to type. Being a non-activating panel, it takes the keyboard
/// without activating island, so the app underneath stays frontmost. When it
/// pops up by itself, `acceptsKeyboard` is off and it never steals focus.
final class OverlayPanel: NSPanel {
    var acceptsKeyboard = false
    /// Called when the panel loses key status, e.g. the user clicked elsewhere.
    var onResignKey: (() -> Void)?

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 96),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
        becomesKeyOnlyIfNeeded = false
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    /// Grows/shrinks with the number of tasks shown, keeping the top edge put.
    func setContentSize(width: CGFloat, height: CGFloat) {
        var frame = self.frame
        frame.size = NSSize(width: width, height: height)
        setFrame(frame, display: true)
        positionNearTopOfScreen()
    }

    /// Centered horizontally, near the top of the screen — the "island" spot.
    func positionNearTopOfScreen() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = frame.size
        setFrameOrigin(
            NSPoint(
                x: visible.midX - size.width / 2,
                y: visible.maxY - size.height - 60
            )
        )
    }
}
