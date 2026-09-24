import AppKit

/// The floating window itself: borderless, never key, never main, visible on
/// every Space, and floating above normal windows and the Dock.
final class OverlayPanel: NSPanel {
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
        becomesKeyOnlyIfNeeded = true
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

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
