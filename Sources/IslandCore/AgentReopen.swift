import Foundation

/// One row of `ps -axo pid=,ppid=`.
public struct ProcessNode: Equatable, Sendable {
    public let pid: Int32
    public let parentPID: Int32

    public init(pid: Int32, parentPID: Int32) {
        self.pid = pid
        self.parentPID = parentPID
    }
}

/// Answers "which processes is this agent nested under?" — the step that turns a
/// Claude Code pid into the tmux pane hosting it.
public enum ProcessTree {
    public static func parse(_ text: String) -> [ProcessNode] {
        text.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2,
                let pid = Int32(fields[0]),
                let parentPID = Int32(fields[1])
            else { return nil }
            return ProcessNode(pid: pid, parentPID: parentPID)
        }
    }

    /// `pid` first, then its parents up to (but excluding) launchd. Cycles and
    /// unknown pids end the walk instead of looping.
    public static func ancestors(of pid: Int32, in nodes: [ProcessNode]) -> [Int32] {
        var parentByPID: [Int32: Int32] = [:]
        for node in nodes { parentByPID[node.pid] = node.parentPID }

        var chain: [Int32] = [pid]
        var seen: Set<Int32> = [pid]
        var current = pid
        while let parent = parentByPID[current], parent > 1, !seen.contains(parent) {
            chain.append(parent)
            seen.insert(parent)
            current = parent
        }
        return chain
    }
}

/// One pane from `tmux list-panes -a`. `pane_pid` is the shell running inside
/// the pane, which is what the agent's ancestor chain points at.
public struct TmuxPane: Equatable, Sendable {
    public let pid: Int32
    public let windowTarget: String
    public let paneTarget: String

    public init(pid: Int32, windowTarget: String, paneTarget: String) {
        self.pid = pid
        self.windowTarget = windowTarget
        self.paneTarget = paneTarget
    }

    /// Parses `#{pane_pid} #{session_name}:#{window_index}.#{pane_index}`.
    public static func parse(_ text: String) -> [TmuxPane] {
        text.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2, let pid = Int32(fields[0]) else { return nil }
            let paneTarget = String(fields[1])
            let windowTarget =
                paneTarget.lastIndex(of: ".").map { String(paneTarget[..<$0]) } ?? paneTarget
            return TmuxPane(pid: pid, windowTarget: windowTarget, paneTarget: paneTarget)
        }
    }
}

/// What island does when the user picks a task.
public enum AgentReopenAction: Equatable, Sendable {
    case focusTmux(windowTarget: String, paneTarget: String)
    case activateApp(bundleID: String)
    case copyToClipboard(String)
    case nothing
}

/// PLAN § Design: get the user back to the task, best effort. tmux first (it is
/// the only host island can locate precisely), then the desktop app, then the
/// resume command on the clipboard.
public enum AgentReopen {
    public static func plan(
        for task: AgentTask,
        processNodes: [ProcessNode],
        tmuxPanes: [TmuxPane]
    ) -> AgentReopenAction {
        if case .terminal(let pid) = task.host {
            let chain = ProcessTree.ancestors(of: pid, in: processNodes)
            if let pane = tmuxPanes.first(where: { chain.contains($0.pid) }) {
                return .focusTmux(windowTarget: pane.windowTarget, paneTarget: pane.paneTarget)
            }
        }

        switch task.host {
        case .desktop(let bundleID):
            return .activateApp(bundleID: bundleID)
        case .terminal, .unknown:
            guard let command = task.resumeCommand, !command.isEmpty else { return .nothing }
            return .copyToClipboard(command)
        }
    }
}
