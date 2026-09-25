import AppKit
import IslandCore

/// Performs a `TerminalTabFocus`: brings the exact tab (or VS Code terminal)
/// showing a task to the front. Returns false when the tab could not be found,
/// so the caller can fall back to just activating the app.
@MainActor
struct TerminalTabFocuser {
    /// Where the island VS Code extension (`vscode-extension/extension.js`) listens.
    static let vscodeDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/island/vscode", isDirectory: true)

    private static let vscodeResponseTimeout: TimeInterval = 1.0
    private static let pollInterval: TimeInterval = 0.05

    func focus(_ focus: TerminalTabFocus) -> Bool {
        switch focus {
        case .scriptable(let bundleID, .terminalID(let id)):
            return !Subprocess.appleScript(
                TerminalScript.focus(bundleID: bundleID, match: .terminalID(id))
            ).isEmpty
        case .scriptable(let bundleID, .titleProbe(let tty)):
            return focusByTitleProbe(bundleID: bundleID, tty: tty)
        case .appleTerminal(let tty):
            return Subprocess.appleScript(TerminalScript.appleTerminal(tty: tty)) == "true"
        case .iTerm(let tty):
            return Subprocess.appleScript(TerminalScript.iTerm(tty: tty)) == "true"
        case .vscode(let pids):
            return focusVSCodeTerminal(pids: pids)
        case .none:
            return false
        }
    }

    /// Ghostty cannot tell island which terminal owns a tty, so island marks
    /// the tty with a unique title, finds the terminal wearing it, and puts the
    /// original title back.
    private func focusByTitleProbe(bundleID: String, tty: String) -> Bool {
        let titles = TerminalScript.parseListing(
            Subprocess.appleScript(TerminalScript.listTerminals(bundleID: bundleID)))
        let probe = "island-\(UUID().uuidString)"
        guard write(TerminalScript.titleSequence(probe), to: tty) else { return false }

        var focusedID = ""
        for _ in 0..<5 where focusedID.isEmpty {
            Thread.sleep(forTimeInterval: Self.pollInterval)
            focusedID = Subprocess.appleScript(
                TerminalScript.focus(bundleID: bundleID, match: .titleProbe(tty: tty), probe: probe)
            )
        }
        // Unmatched means the tty is not in this app; clearing the title lets
        // the terminal fall back to its own.
        _ = write(TerminalScript.titleSequence(titles[focusedID] ?? ""), to: tty)
        return !focusedID.isEmpty
    }

    private func write(_ text: String, to tty: String) -> Bool {
        guard let handle = FileHandle(forWritingAtPath: tty) else { return false }
        defer { try? handle.close() }
        return (try? handle.write(contentsOf: Data(text.utf8))) != nil
    }

    /// Hands the pids to the island VS Code extension; the window owning the
    /// terminal shows it and answers with its workspace, which `open` raises.
    private func focusVSCodeTerminal(pids: [Int32]) -> Bool {
        let directory = Self.vscodeDirectory
        let request = VSCodeFocusRequest(id: UUID().uuidString, time: Date(), pids: pids)
        let responseURL = directory.appendingPathComponent("focus-response-\(request.id).json")
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try request.encoded().write(to: directory.appendingPathComponent("focus-request.json"))
        } catch {
            return false
        }

        let deadline = Date().addingTimeInterval(Self.vscodeResponseTimeout)
        while Date() < deadline {
            if let data = try? Data(contentsOf: responseURL) {
                try? FileManager.default.removeItem(at: responseURL)
                if let path = VSCodeFocusResponse.decode(data)?.windowPath {
                    _ = Subprocess.run([
                        "/usr/bin/open", "-b", TerminalTabFocus.vscodeBundleID, path,
                    ])
                } else {
                    NSRunningApplication.runningApplications(
                        withBundleIdentifier: TerminalTabFocus.vscodeBundleID
                    ).first?.activate()
                }
                return true
            }
            Thread.sleep(forTimeInterval: Self.pollInterval)
        }
        return false
    }
}
