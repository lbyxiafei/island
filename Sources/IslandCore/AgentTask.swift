import Foundation

/// The AI agents island knows how to watch.
public enum AgentKind: String, Sendable, CaseIterable {
    case claudeCode = "claude-code"
    case pi
    case codex

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .pi: return "pi"
        case .codex: return "Codex"
        }
    }
}

/// Where a task runs, so island can decide how to bring it back to the front.
public enum AgentHost: Equatable, Sendable {
    /// A terminal agent; the process that owns the session (used to walk up to
    /// tmux or the host terminal app).
    case terminal(processID: Int32)
    /// A desktop app, identified by its bundle id.
    case desktop(bundleID: String)
    case unknown
}

/// One completed agent run — what island shows and lets the user jump back to.
public struct AgentTask: Equatable, Sendable {
    public let agent: AgentKind
    public let sessionID: String
    public let title: String
    public let cwd: String?
    public let completedAt: Date
    public let host: AgentHost
    /// Command that resumes the session; island copies it when it cannot focus
    /// the original window (PLAN § Design, second best path).
    public let resumeCommand: String?

    public init(
        agent: AgentKind,
        sessionID: String,
        title: String,
        cwd: String?,
        completedAt: Date,
        host: AgentHost,
        resumeCommand: String?
    ) {
        self.agent = agent
        self.sessionID = sessionID
        self.title = title
        self.cwd = cwd
        self.completedAt = completedAt
        self.host = host
        self.resumeCommand = resumeCommand
    }

    /// Identity of one *run*, not of the session: the same Claude Code session
    /// completing another turn is a new entry (PLAN: only incremental runs).
    public var id: String {
        "\(agent.rawValue):\(sessionID):\(Int(completedAt.timeIntervalSince1970 * 1000))"
    }

    /// `~/Repos/island` when the agent reported no title.
    public static func fallbackTitle(cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty, cwd != "/" else { return "(untitled)" }
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? "(untitled)" : name
    }
}
