import Foundation

/// The AI agents island knows how to watch. Everything that differs between
/// them is in `AgentProfile`.
public enum AgentKind: String, Sendable, CaseIterable {
    case claudeCode = "claude-code"
    case claudeDesktop = "claude-desktop"
    case pi
    case codex
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
    /// A URL that opens this exact task in its app (Claude Desktop's
    /// `claude://` links), tried before merely activating the app.
    public let deepLink: String?
    /// The `AgentScenario.id` this run belongs to; what Settings → Agents
    /// switches on and off.
    public let scenario: String

    public init(
        agent: AgentKind,
        sessionID: String,
        title: String,
        cwd: String?,
        completedAt: Date,
        host: AgentHost,
        resumeCommand: String?,
        deepLink: String? = nil,
        scenario: String? = nil
    ) {
        self.agent = agent
        self.sessionID = sessionID
        self.title = title
        self.cwd = cwd
        self.completedAt = completedAt
        self.host = host
        self.resumeCommand = resumeCommand
        self.deepLink = deepLink
        self.scenario = scenario ?? agent.profile.primaryScenario.id
    }

    /// Identity of one *run*, not of the session: the same Claude Code session
    /// completing another turn is a new entry (PLAN: only incremental runs).
    public var id: String {
        "\(agent.rawValue):\(sessionID):\(Int(completedAt.timeIntervalSince1970 * 1000))"
    }

    /// Identity of the session across runs: the overlay shows one row per
    /// session, however many turns it finishes.
    public var sessionKey: String { "\(agent.rawValue):\(sessionID)" }

    /// A copy with a host resolved at click time (some agents do not record one).
    public func withHost(_ host: AgentHost) -> AgentTask {
        AgentTask(
            agent: agent,
            sessionID: sessionID,
            title: title,
            cwd: cwd,
            completedAt: completedAt,
            host: host,
            resumeCommand: resumeCommand,
            deepLink: deepLink,
            scenario: scenario
        )
    }

    /// `~/Repos/island` when the agent reported no title.
    public static func fallbackTitle(cwd: String?) -> String {
        guard let cwd, !cwd.isEmpty, cwd != "/" else { return "(untitled)" }
        let name = (cwd as NSString).lastPathComponent
        return name.isEmpty || name == "/" ? "(untitled)" : name
    }
}

/// What island puts in a task row: the agent's own title when it has one, else
/// the last message of the run, else the directory (PLAN § Design / 下拉框 UX #1).
public enum TaskTitle {
    public static func resolve(title: String?, lastMessage: String?, cwd: String?) -> String {
        cleaned(title) ?? cleaned(lastMessage) ?? AgentTask.fallbackTitle(cwd: cwd)
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : JSON.truncated(trimmed)
    }
}
