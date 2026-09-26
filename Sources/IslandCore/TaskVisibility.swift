import Foundation

/// Whether the user is already looking at a task, as far as island can tell
/// without asking the host app.
public enum TaskViewPlan: Equatable, Sendable {
    case hidden
    case visible
    /// The app showing the task is frontmost; whether the focused tab is the
    /// task's own has to be asked of the app (`FocusedTab`). `cwd` is the task's
    /// directory when `leaf` is the agent itself, nil when it is a tmux client.
    case checkTab(host: RunningApp, leaf: TerminalLeaf, chain: [Int32], cwd: String?)
}

/// Decides whether a finished task needs a notification at all: a run the user
/// is watching finish needs neither a pop-up nor an unread dot. Errs towards
/// "hidden" — a missed notification is worse than a redundant one.
public enum TaskVisibility {
    public static func plan(
        for task: AgentTask,
        frontmost: RunningApp?,
        apps: [RunningApp],
        processNodes: [ProcessNode],
        tmuxPanes: [TmuxPane],
        tmuxClients: [TmuxClient]
    ) -> TaskViewPlan {
        guard let frontmost else { return .hidden }
        switch task.host {
        case .desktop(let bundleID):
            // Desktop apps expose no conversation to compare, so the app it is.
            return frontmost.bundleID == bundleID ? .visible : .hidden
        case .unknown:
            return .hidden
        case .terminal(let pid):
            let chain = ProcessTree.ancestors(of: pid, in: processNodes)
            if let pane = tmuxPanes.first(where: { chain.contains($0.pid) }) {
                guard pane.isCurrent else { return .hidden }
                let session = TmuxClient.session(ofPane: pane.paneTarget)
                for client in tmuxClients where client.session == session {
                    let clientChain = ProcessTree.ancestors(of: client.pid, in: processNodes)
                    if HostApp.nearest(in: clientChain, among: apps)?.pid == frontmost.pid {
                        return .checkTab(
                            host: frontmost, leaf: TerminalLeaf(pid: client.pid, tty: client.tty),
                            chain: clientChain, cwd: nil)
                    }
                }
                return .hidden
            }
            guard HostApp.nearest(in: chain, among: apps)?.pid == frontmost.pid else {
                return .hidden
            }
            return .checkTab(
                host: frontmost, leaf: TerminalLeaf(pid: pid, tty: nil), chain: chain,
                cwd: task.cwd)
        }
    }
}

/// Asks a scriptable terminal which tab it is showing, read-only — unlike the
/// title probe `TerminalTabFocuser` uses, nothing the user sees changes.
public enum FocusedTab {
    /// AppleScript reporting the focused tab, or nil when the host cannot tell.
    public static func script(for focus: TerminalTabFocus) -> String? {
        switch focus {
        case .appleTerminal:
            return """
                tell application id "\(TerminalTabFocus.terminalBundleID)"
                    return tty of selected tab of front window
                end tell
                """
        case .iTerm:
            return """
                tell application id "\(TerminalTabFocus.iTermBundleID)"
                    return tty of current session of current window
                end tell
                """
        case .scriptable(let bundleID, _):
            return focusedTerminal(bundleID: bundleID)
        case .vscode, .none:
            return nil
        }
    }

    /// Reads the output of `script(for:)`.
    public static func matches(_ focus: TerminalTabFocus, output: String, cwd: String?) -> Bool {
        switch focus {
        case .appleTerminal(let tty), .iTerm(let tty):
            return output == tty
        case .scriptable(_, let match):
            var lines = output.split(separator: "\n").map(String.init)
            guard !lines.isEmpty else { return false }
            let focused = lines.removeFirst()
            let terminals = TerminalScript.parseListing(lines.joined(separator: "\n"))
            switch match {
            case .terminalID(let id):
                return focused == id
            case .titleProbe:
                // No id to compare: accept only an unambiguous match.
                if terminals.count == 1 { return terminals[focused] != nil }
                guard let cwd, !cwd.isEmpty else { return false }
                return terminals.filter { $0.value == cwd }.map(\.key) == [focused]
            }
        case .vscode, .none:
            return false
        }
    }

    /// First line: the focused terminal's id; then `id<TAB>directory` per terminal.
    private static func focusedTerminal(bundleID: String) -> String {
        """
        set separator to tab
        set newline to linefeed
        tell application id \(TerminalScript.quoted(bundleID))
            set out to (id of focused terminal of selected tab of front window) & newline
            repeat with t in terminals
                set dir to ""
                try
                    set dir to (working directory of t) as text
                end try
                set out to out & (id of t) & separator & dir & newline
            end repeat
            return out
        end tell
        """
    }
}
