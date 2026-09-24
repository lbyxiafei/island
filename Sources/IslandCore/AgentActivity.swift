import Foundation

/// One agent's on-disk session store, reduced to the one question island asks:
/// "which runs have finished?"
///
/// Implementations must be total: a missing directory, a half-written file or a
/// malformed line yields fewer tasks, never a crash.
public protocol AgentActivitySource: Sendable {
    var agent: AgentKind { get }
    func completedTasks() -> [AgentTask]
}

/// Runs every source and returns their completed tasks, newest first.
public struct AgentActivityScanner: Sendable {
    private let sources: [any AgentActivitySource]

    public init(sources: [any AgentActivitySource]) {
        self.sources = sources
    }

    /// The sources wired to this machine's standard agent locations. `sqlite`
    /// is supplied by the app; core has no process plumbing of its own.
    public static func standard(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        sqlite: any SQLiteQuerying = NoSQLiteQuerying()
    ) -> AgentActivityScanner {
        AgentActivityScanner(sources: [
            ClaudeCodeActivitySource.standard(home: home),
            PiActivitySource.standard(home: home),
            CodexActivitySource.standard(home: home, sqlite: sqlite),
        ])
    }

    public func completedTasks() -> [AgentTask] {
        sources.flatMap { $0.completedTasks() }
            .sorted { $0.completedAt > $1.completedAt }
    }
}

// MARK: - Claude Code

/// Claude Code keeps one live `~/.claude/sessions/<pid>.json` per running
/// process. `status` flips `busy` -> `idle` when a turn finishes.
public struct ClaudeCodeActivitySource: AgentActivitySource {
    public let agent = AgentKind.claudeCode

    private let sessionsDirectory: URL

    public init(sessionsDirectory: URL) {
        self.sessionsDirectory = sessionsDirectory
    }

    public static func standard(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> ClaudeCodeActivitySource {
        ClaudeCodeActivitySource(
            sessionsDirectory: home.appendingPathComponent(".claude/sessions"))
    }

    public func completedTasks() -> [AgentTask] {
        AgentFiles.directoryContents(sessionsDirectory)
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                    let state = try? JSONDecoder().decode(ClaudeSessionState.self, from: data)
                else { return nil }
                return Self.task(from: state)
            }
    }

    static func task(from state: ClaudeSessionState) -> AgentTask? {
        guard state.status == "idle", let sessionID = state.sessionId, !sessionID.isEmpty else {
            return nil
        }
        let completedAt = state.updatedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
        return AgentTask(
            agent: .claudeCode,
            sessionID: sessionID,
            title: Self.title(name: state.name, cwd: state.cwd),
            cwd: state.cwd,
            completedAt: completedAt,
            host: state.pid.map(AgentHost.terminal) ?? .unknown,
            resumeCommand: "claude --resume \(sessionID)"
        )
    }

    static func title(name: String?, cwd: String?) -> String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        return AgentTask.fallbackTitle(cwd: cwd)
    }

    struct ClaudeSessionState: Decodable {
        let pid: Int32?
        let sessionId: String?
        let cwd: String?
        let name: String?
        let status: String?
        let updatedAt: Double?
    }
}

// MARK: - pi

/// pi writes `~/.pi/agent/sessions/<slug>/<ts>_<id>.jsonl`; the last assistant
/// message carries `stopReason`, and `stop` means the turn is over.
public struct PiActivitySource: AgentActivitySource {
    public let agent = AgentKind.pi

    private let sessionsRoot: URL

    public init(sessionsRoot: URL) {
        self.sessionsRoot = sessionsRoot
    }

    public static func standard(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> PiActivitySource {
        PiActivitySource(sessionsRoot: home.appendingPathComponent(".pi/agent/sessions"))
    }

    public func completedTasks() -> [AgentTask] {
        AgentFiles.directoryContents(sessionsRoot).compactMap { project -> AgentTask? in
            let files = AgentFiles.directoryContents(project)
            // Only the newest session per project can be the one just finished.
            let newest =
                files
                .filter { $0.pathExtension == "jsonl" }
                .max { Self.modifiedAt($0) < Self.modifiedAt($1) }
            guard let newest,
                let contents = try? String(contentsOf: newest, encoding: .utf8),
                let scan = Self.scan(contents: contents, fileModified: Self.modifiedAt(newest)),
                scan.isComplete
            else { return nil }
            return AgentTask(
                agent: .pi,
                sessionID: scan.sessionID,
                title: scan.title ?? AgentTask.fallbackTitle(cwd: scan.cwd),
                cwd: scan.cwd,
                completedAt: scan.completedAt,
                host: .unknown,
                resumeCommand: "pi --session \(scan.sessionID)"
            )
        }
    }

    static func modifiedAt(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
    }

    struct SessionScan: Equatable {
        let sessionID: String
        let cwd: String?
        let title: String?
        let completedAt: Date
        let isComplete: Bool
    }

    /// Pure parser over a whole pi session file, so tests can feed fixtures.
    static func scan(contents: String, fileModified: Date) -> SessionScan? {
        var sessionID: String?
        var cwd: String?
        var firstUserText: String?
        var lastAssistantStop: String?
        var lastAssistantDate: Date?
        var lastTimestamp: Date?

        for line in contents.split(separator: "\n") {
            guard let object = JSON.object(fromLine: String(line)) else { continue }
            if let timestamp = object["timestamp"] as? String,
                let date = AgentTimestamp.date(from: timestamp)
            {
                lastTimestamp = date
            }
            switch object["type"] as? String {
            case "session":
                sessionID = object["id"] as? String
                cwd = object["cwd"] as? String
            case "message":
                guard let message = object["message"] as? [String: Any] else { continue }
                switch message["role"] as? String {
                case "user":
                    if firstUserText == nil {
                        firstUserText = JSON.firstText(in: message["content"])
                    }
                case "assistant":
                    lastAssistantStop = message["stopReason"] as? String
                    lastAssistantDate =
                        (object["timestamp"] as? String).flatMap(AgentTimestamp.date(from:))
                default:
                    break
                }
            default:
                break
            }
        }

        guard let sessionID else { return nil }
        return SessionScan(
            sessionID: sessionID,
            cwd: cwd,
            title: firstUserText.map { JSON.truncated($0) },
            completedAt: lastAssistantDate ?? lastTimestamp ?? fileModified,
            isComplete: lastAssistantStop == "stop"
        )
    }
}

// MARK: - Shared JSON helpers

enum AgentFiles {
    /// Directory listing that treats "does not exist" as "nothing to report".
    static func directoryContents(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil))
            ?? []
    }
}

enum AgentTimestamp {
    /// Codex and pi emit fractional seconds; Claude Code does not.
    static func date(from text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }
}

enum JSON {
    static func object(fromLine line: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
    }

    /// Content is either a bare string or a list of typed blocks; take the first
    /// block that carries human text.
    static func firstText(in content: Any?) -> String? {
        if let text = content as? String, !text.isEmpty { return text }
        guard let blocks = content as? [[String: Any]] else { return nil }
        for block in blocks {
            if let text = block["text"] as? String, !text.isEmpty { return text }
        }
        return nil
    }

    static func truncated(_ text: String, limit: Int = 72) -> String {
        let collapsed =
            text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return collapsed.count <= limit ? collapsed : String(collapsed.prefix(limit)) + "…"
    }
}
