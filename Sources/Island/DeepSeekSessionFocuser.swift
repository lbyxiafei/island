import AppKit
import IslandCore

/// Opens one DeepSeek session: `dsh://open` only brings the window forward, so
/// the session is then picked in the app's sidebar through Accessibility —
/// pressing its row, after its workspace's row when the open workspace does
/// not list it. Without the Accessibility grant (asked for once, on the first
/// such click) it stays at bringing the window forward.
///
/// Runs on the reopen queue: it waits for the sidebar to render.
extension AgentReopenExecutor {
    static let askedAccessibilityKey = "IslandAskedAccessibilityForDeepSeek"

    func openDeepSeekSession(sessionID: String, title: String) {
        let bundleID = DeepSeekActivitySource.bundleID
        if let url = URL(string: "dsh://open"), NSWorkspace.shared.open(url) {
            log("opened dsh://open")
        } else {
            activate(bundleID: bundleID)
        }
        guard mayUseAccessibility(),
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first
        else { return }
        let sidebar = AXSidebar(pid: app.processIdentifier)
        if sidebar.pressRow(waiting: 2, where: { DeepSeekSidebar.rowShows($0, title) }) {
            log("DeepSeek: opened session \"\(title)\"")
            return
        }
        guard let data = try? Data(contentsOf: DeepSeekSidebar.workspacesFile()),
            let workspace = DeepSeekSidebar.workspaceLabel(sessionID, data),
            sidebar.pressRow(waiting: 0.5, where: { $0 == workspace }),
            sidebar.pressRow(waiting: 2, where: { DeepSeekSidebar.rowShows($0, title) })
        else {
            log("DeepSeek: session \"\(title)\" is not in the sidebar; left the app in front")
            return
        }
        log("DeepSeek: opened session \"\(title)\" in workspace \(workspace)")
    }

    /// True when island may read and press other apps' controls. The first
    /// time it may not, macOS is asked to show its Accessibility prompt.
    private func mayUseAccessibility() -> Bool {
        if AXIsProcessTrusted() { return true }
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.askedAccessibilityKey) {
            defaults.set(true, forKey: Self.askedAccessibilityKey)
            // The value of `kAXTrustedCheckOptionPrompt`, which Swift 6 will not
            // read as a global.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            log("DeepSeek: asked for Accessibility, needed to open a session")
        } else {
            log("DeepSeek: no Accessibility grant; left the app in front")
        }
        return false
    }
}

/// An Electron app's accessibility tree, searched for sidebar rows. Electron
/// builds the tree only once something asks for it (`AXManualAccessibility`).
private struct AXSidebar {
    let app: AXUIElement

    init(pid: pid_t) {
        app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Presses the first row whose text satisfies `matches`, polling up to
    /// `waiting` seconds for it to appear.
    func pressRow(waiting: TimeInterval, where matches: (String) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(waiting)
        repeat {
            if let row = row(in: app, depth: 0, matches: matches) {
                return AXUIElementPerformAction(row, kAXPressAction as CFString) == .success
            }
            Thread.sleep(forTimeInterval: 0.15)
        } while Date() < deadline
        return false
    }

    private func row(in element: AXUIElement, depth: Int, matches: (String) -> Bool)
        -> AXUIElement?
    {
        guard depth < 60 else { return nil }
        let children = Self.children(of: element)
        if Self.string(element, kAXRoleAttribute) == kAXRowRole as String {
            for child in children
            where Self.string(child, kAXRoleAttribute) == kAXStaticTextRole as String {
                if let text = Self.string(child, kAXValueAttribute)
                    ?? Self.string(child, kAXTitleAttribute), matches(text)
                {
                    return element
                }
            }
        }
        for child in children {
            if let found = row(in: child, depth: depth + 1, matches: matches) { return found }
        }
        return nil
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
        return value as? [AXUIElement] ?? []
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return value as? String
    }
}
