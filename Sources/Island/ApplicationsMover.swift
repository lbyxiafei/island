import AppKit
import IslandCore

/// Offers to copy island into /Applications when it runs from a dmg or a
/// translocated path, where the login item and the bundle itself do not last.
@MainActor
enum ApplicationsMover {
    /// True when a copy in /Applications is about to relaunch, so this
    /// instance should quit instead of finishing its launch.
    static func offerIfNeeded(log: (String) -> Void) -> Bool {
        let source = Bundle.main.bundlePath
        let location = AppLocation.classify(bundlePath: source)
        guard let prompt = MoveToApplications.prompt(for: location) else { return false }
        log("running from a \(location) location: \(source)")

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = prompt.message
        alert.informativeText = prompt.informativeText
        alert.addButton(withTitle: MoveToApplications.moveButton)
        alert.addButton(withTitle: MoveToApplications.laterButton)
        guard alert.runModal() == .alertFirstButtonReturn else {
            log("move to Applications declined")
            return false
        }

        let destination = MoveToApplications.destination(forBundlePath: source)
        do {
            try copy(from: source, to: destination)
        } catch {
            log("move to Applications failed: \(error.localizedDescription)")
            let failure = NSAlert(error: error)
            failure.informativeText =
                "Drag Island into the Applications folder in Finder, then open it from there."
            failure.runModal()
            return false
        }
        let relaunch = MoveToApplications.relaunchCommand(
            pid: ProcessInfo.processInfo.processIdentifier, appPath: destination)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: relaunch.executable)
        process.arguments = relaunch.arguments
        do {
            try process.run()
        } catch {
            log("could not relaunch \(destination): \(error.localizedDescription)")
            return false
        }
        log("copied to \(destination); relaunching from there")
        return true
    }

    /// Replaces any older copy (to the Trash, so it is recoverable), then
    /// strips the quarantine flag so the copy is not translocated in turn.
    private static func copy(from source: String, to destination: String) throws {
        let files = FileManager.default
        let target = URL(fileURLWithPath: destination)
        if files.fileExists(atPath: destination) {
            try files.trashItem(at: target, resultingItemURL: nil)
        }
        try files.copyItem(at: URL(fileURLWithPath: source), to: target)
        let clear = MoveToApplications.clearQuarantineCommand(appPath: destination)
        _ = Subprocess.runWithStatus([clear.executable] + clear.arguments)
    }
}
