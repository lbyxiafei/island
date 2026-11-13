import AppKit

/// The menu-bar mark: a rounded panel floating above the screen edge.
///
/// Geometry mirrors `hai/reference/icon/menubar-icon.svg` by hand — the runtime
/// deliberately reads nothing from `reference/` (see AGENTS.md § Reference), so
/// changing the icon means changing both places.
@MainActor
enum IslandGlyph {
    /// Canvas the design is laid out on; the menu bar scales it down to ~16pt.
    static let canvas: CGFloat = 18

    /// `badged` adds a red dot to the top-right corner (an update waits). A
    /// template image cannot carry color, so the badged one draws the glyph in
    /// `labelColor`, which the drawing handler resolves for the menu bar's
    /// light or dark appearance each time it renders.
    static func menuBarImage(badged: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { _ in
            (badged ? NSColor.labelColor : NSColor.black).setFill()
            panelPath.fill()
            screenEdgePath.fill()
            if badged {
                NSColor.systemRed.setFill()
                NSBezierPath(ovalIn: badgeRect).fill()
            }
            return true
        }
        // Template images let macOS tint for light/dark menubars and highlight.
        image.isTemplate = !badged
        return image
    }

    private static let badgeRect = NSRect(x: 11.5, y: 11.5, width: 6.5, height: 6.5)

    private static var panelPath: NSBezierPath {
        NSBezierPath(
            roundedRect: NSRect(x: 3.5, y: 6.2, width: 11, height: 8),
            xRadius: 2.6,
            yRadius: 2.6
        )
    }

    private static var screenEdgePath: NSBezierPath {
        NSBezierPath(
            roundedRect: NSRect(x: 2, y: 2.2, width: 14, height: 2),
            xRadius: 1,
            yRadius: 1
        )
    }
}
