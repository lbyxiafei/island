import Foundation

/// The process questions a source asks to tell an open session from a closed
/// one. Core has no process plumbing of its own; the app supplies the real
/// implementation.
public protocol ProcessInspecting: Sendable {
    func isRunning(_ pid: Int32) -> Bool
    /// Working directories of the running processes named one of `names`;
    /// nil when they cannot be listed.
    func workingDirectories(ofProcessesNamed names: Set<String>) -> Set<String>?
}

/// Used when the app supplies nothing: every pid runs, no directory is known,
/// so no session is ever judged closed.
public struct NoProcessInspecting: ProcessInspecting {
    public init() {}
    public func isRunning(_ pid: Int32) -> Bool { true }
    public func workingDirectories(ofProcessesNamed names: Set<String>) -> Set<String>? { nil }
}

/// Which sessions still exist, for the agents that can tell (issue
/// remove-closed-agent-title): a closed terminal or a deleted conversation
/// should not linger in the list.
public struct SessionPresence: Equatable, Sendable {
    /// Per agent, the ids of its open sessions. An agent missing here cannot
    /// tell, and keeps every row.
    public let live: [AgentKind: Set<String>]

    public init(live: [AgentKind: Set<String>]) {
        self.live = live
    }

    public func isGone(_ task: AgentTask) -> Bool {
        guard let open = live[task.agent] else { return false }
        return !open.contains(task.sessionID)
    }
}

extension AgentActivitySource {
    /// Sources cannot tell unless they say otherwise.
    public func liveSessionIDs(processes: any ProcessInspecting) -> Set<String>? { nil }
}

extension AgentActivityScanner {
    /// Asks only the sources of `agents`; one source that cannot tell makes
    /// its whole agent unknown, since its sessions would otherwise look gone.
    public func presence(
        of agents: Set<AgentKind>, processes: any ProcessInspecting
    ) -> SessionPresence {
        var live: [AgentKind: Set<String>] = [:]
        var unknown: Set<AgentKind> = []
        for source in sources where agents.contains(source.agent) {
            if let ids = source.liveSessionIDs(processes: processes) {
                live[source.agent, default: []].formUnion(ids)
            } else {
                unknown.insert(source.agent)
            }
        }
        return SessionPresence(live: live.filter { !unknown.contains($0.key) })
    }
}
