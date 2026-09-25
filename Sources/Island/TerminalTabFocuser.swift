import AppKit
import IslandCore

enum TabFocusResult: Equatable {
    case focused
    /// The tab was not found (or the app is not scriptable); activate the app.
    case notFound
    /// The user declined island in Privacy & Security → Automation.
    case notAuthorized
}

/// Performs a `TerminalTabFocus`: brings the exact tab (or VS Code terminal)
/// showing a task to the front. Blocks on `osascript` and on the VS Code
/// handshake, so it runs off the main thread.
struct TerminalTabFocuser: Sendable {
    /// Where the island VS Code extension (`vscode-extension/extension.js`) listens.
    static let vscodeDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/island/vscode", isDirectory: true)

    private static let vscodeResponseTimeout: TimeInterval = 1.0
    private static let pollInterval: TimeInterval = 0.05

    func focus(_ focus: TerminalTabFocus) -> TabFocusResult {
        switch focus {
        case .scriptable(let bundleID, .terminalID(let id)):
            return result(
                Subprocess.appleScript(
                    TerminalScript.focus(bundleID: bundleID, match: .terminalID(id)))
            ) { !$0.isEmpty }
        case .scriptable(let bundleID, .titleProbe(let tty)):
            return focusByTitleProbe(bundleID: bundleID, tty: tty)
        case .appleTerminal(let tty):
            return result(Subprocess.appleScript(TerminalScript.appleTerminal(tty: tty))) {
                $0 == "true"
            }
        case .iTerm(let tty):
            return result(Subprocess.appleScript(TerminalScript.iTerm(tty: tty))) {
                $0 == "true"
            }
        case .vscode(let pids):
            return focusVSCodeTerminal(pids: pids) ? .focused : .notFound
        case .none:
            return .notFound
        }
    }

    private func result(_ outcome: AppleScriptOutcome, matched: (String) -> Bool) -> TabFocusResult
    {
        switch outcome {
        case .notAuthorized: return .notAuthorized
        case .failed: return .notFound
        case .output(let text): return matched(text) ? .focused : .notFound
        }
    }

    /// Ghostty cannot tell island which terminal owns a tty, so island marks
    /// the tty with a unique title, finds the terminal wearing it, and puts the
    /// original title back.
    private func focusByTitleProbe(bundleID: String, tty: String) -> TabFocusResult {
        // Ask first: without permission the probe title would be left behind.
        let listing = Subprocess.appleScript(TerminalScript.listTerminals(bundleID: bundleID))
        if listing == .notAuthorized { return .notAuthorized }
        let titles = TerminalScript.parseListing(listing.text)
        let probe = "island-\(UUID().uuidString)"
        guard write(TerminalScript.titleSequence(probe), to: tty) else { return .notFound }

        var focusedID = ""
        for _ in 0..<5 where focusedID.isEmpty {
            Thread.sleep(forTimeInterval: Self.pollInterval)
            focusedID =
                Subprocess.appleScript(
                    TerminalScript.focus(
                        bundleID: bundleID, match: .titleProbe(tty: tty), probe: probe)
                ).text
        }
        // Unmatched means the tty is not in this app; clearing the title lets
        // the terminal fall back to its own.
        _ = write(TerminalScript.titleSequence(titles[focusedID] ?? ""), to: tty)
        return focusedID.isEmpty ? .notFound : .focused
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
