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

    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { _ in
            NSColor.black.setFill()
            panelPath.fill()
            screenEdgePath.fill()
            return true
        }
        // Template images let macOS tint for light/dark menubars and highlight.
        image.isTemplate = true
        return image
    }

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
